#!/usr/bin/env bash
# ai-repair.sh — normalize local AI runtime settings that commonly drift
#
# Usage:
#   ./scripts/ai-repair.sh
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${REPO_ROOT}/scripts/lib/ui.sh"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }

# Serialize concurrent runs via atomic mkdir lock. Guards against two shells
# invoking `make ai-repair` simultaneously and fighting over ~/.claude.json
# mid-write. The $(id -u) suffix prevents a local user from squatting another
# user's lock directory on shared /tmp (macOS $TMPDIR is already per-user, but
# we add the uid for Linux/CI correctness).
LOCK_DIR="${TMPDIR:-/tmp}/dotfiles-ai-repair-$(id -u).lock"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  printf 'ERROR: another ai-repair run is in progress (lock: %s)\n' "${LOCK_DIR}" >&2
  printf '  If stale, remove with: rmdir %s\n' "${LOCK_DIR}" >&2
  exit 1
fi
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

CLAUDE_JSON="${HOME}/.claude.json"
CLAUDE_SETTINGS_JSON="${HOME}/.claude/settings.json"

restart_needed=0

# Private helpers for the 5 baseline MCP upsert blocks below. Identity fields
# (url for HTTP, command+args for stdio) are compared partially — Claude Code
# may add fields like sessionId at runtime, so a deep-equality check would
# trigger endless re-upserts. Helpers stay local; lib/ai-config.sh keeps its
# pure-mutation surface.
_upsert_http_mcp() {
  # _upsert_http_mcp <name> <entry_json> <expected_url>
  local name="$1" entry_json="$2" expected_url="$3"
  local current
  current="$(ai_config_json_read_mcp_field "${CLAUDE_JSON}" "${name}" url 2>/dev/null || true)"
  if [[ "${current}" == "${expected_url}" ]]; then
    ok "Claude Code: ${name} MCP already registered"
  else
    ai_config_json_upsert_mcp "${CLAUDE_JSON}" "${name}" "${entry_json}"
    ok "Claude Code: ${name} MCP registered"
    restart_needed=1
  fi
}

_upsert_stdio_mcp() {
  # _upsert_stdio_mcp <name> <entry_json> <expected_command> <expected_args_pipe>
  local name="$1" entry_json="$2" expected_command="$3" expected_args_pipe="$4"
  local current_cmd current_args
  current_cmd="$(ai_config_json_read_mcp_field "${CLAUDE_JSON}" "${name}" command 2>/dev/null || true)"
  current_args="$(ai_config_json_read_mcp_field "${CLAUDE_JSON}" "${name}" args 2>/dev/null || true)"
  if [[ "${current_cmd}" == "${expected_command}" && "${current_args}" == "${expected_args_pipe}" ]]; then
    ok "Claude Code: ${name} MCP already registered"
  else
    ai_config_json_upsert_mcp "${CLAUDE_JSON}" "${name}" "${entry_json}"
    ok "Claude Code: ${name} MCP registered"
    restart_needed=1
  fi
}

# ---- Claude Code MCP registration (JSON direct) -----------------------------
log "Claude Code MCP registration..."
# Exa MCP `?tools=` is a filter parameter (per https://exa.ai/docs/reference/exa-mcp).
# Listing all 3 tools enables web_search_exa + web_fetch_exa (defaults) plus
# web_search_advanced_exa (domain / date / category filter for technical queries).
EXA_CLAUDE_ENTRY='{"type":"http","url":"https://mcp.exa.ai/mcp?tools=web_search_exa,web_fetch_exa,web_search_advanced_exa"}'
# Jamf 公式 docs MCP (https://developer.jamf.com/mcp) — Jamf Pro API 仕様検索のみ。
# Read-only / 無認証 / remote HTTP なので L2 「remote MCP > local stdio MCP」と完全 fit。
# 端末 / ポリシーへの実書き込みは別 MCP (jamf-mcp-server) が必要、それは判断保留中。
JAMF_DOCS_CLAUDE_ENTRY='{"type":"http","url":"https://developer.jamf.com/mcp"}'
# Slack's clientId / callbackPort below are public values published in Slack's
# official docs (https://docs.slack.dev/ai/slack-mcp-server/connect-to-claude/),
# not secrets. OAuth tokens themselves are managed by Claude Code, not dotfiles.
SLACK_CLAUDE_ENTRY='{"type":"http","url":"https://mcp.slack.com/mcp","oauth":{"clientId":"1601185624273.8899143856786","callbackPort":3118}}'
# vision-mcp-server is an npm-distributed Apple Vision Framework OCR MCP
# (@tuannvm/vision-mcp-server). Runs via `npx -y` — no wrapper, no Python
# toolchain. Requires macOS 13+ and Node.js 18+. If MCP connect fails,
# verify with: npx -y @tuannvm/vision-mcp-server --help
VISION_CLAUDE_ENTRY='{"type":"stdio","command":"npx","args":["-y","@tuannvm/vision-mcp-server"]}'
# sequential-thinking MCP (@modelcontextprotocol/server-sequential-thinking) —
# tight CoT scaffolding integration that loses value as a CLI (per L2 matrix).
# Moved from post-setup.sh to here on 2026-04-26 so drift detection is uniform
# with the other 4 baseline MCPs (vision / exa / jamf-docs / slack).
SEQ_THINK_CLAUDE_ENTRY='{"type":"stdio","command":"npx","args":["-y","@modelcontextprotocol/server-sequential-thinking"],"env":{}}'

_upsert_stdio_mcp vision "${VISION_CLAUDE_ENTRY}" npx '-y|@tuannvm/vision-mcp-server'
_upsert_stdio_mcp sequential-thinking "${SEQ_THINK_CLAUDE_ENTRY}" npx '-y|@modelcontextprotocol/server-sequential-thinking'
_upsert_http_mcp exa "${EXA_CLAUDE_ENTRY}" 'https://mcp.exa.ai/mcp?tools=web_search_exa,web_fetch_exa,web_search_advanced_exa'
_upsert_http_mcp jamf-docs "${JAMF_DOCS_CLAUDE_ENTRY}" 'https://developer.jamf.com/mcp'
_upsert_http_mcp slack "${SLACK_CLAUDE_ENTRY}" 'https://mcp.slack.com/mcp'

# Strip retired hook artifacts. The hooks block itself is wholesale-rewritten
# below (so orphan UserPromptSubmit entries for session-topic disappear from
# settings.json), but chezmoi does not auto-remove the script file / cache dir
# once their source is deleted. Clean them up actively so other machines
# converge on `make ai-repair`.
_orphan_scripts=("${HOME}/.claude/session-topic.sh" "${HOME}/.local/bin/serena-mcp")
for _orphan in "${_orphan_scripts[@]}"; do
  if [[ -e "${_orphan}" ]]; then
    rm -f "${_orphan}"
    ok "Claude Code: removed retired helper ${_orphan/#${HOME}/\~}"
  fi
done
unset _orphan _orphan_scripts
if [[ -d "${HOME}/.claude/session-topics" ]]; then
  rm -rf "${HOME}/.claude/session-topics"
  ok "Claude Code: removed retired session-topics cache"
fi
# frontend-design was retired entirely on 2026-04-24 (commit c606583).
# chezmoi doesn't auto-drop previously managed dirs, so prune the stale
# vendored copy here so old machines converge on `make ai-repair`.
if [[ -d "${HOME}/.claude/skills/frontend-design" ]]; then
  rm -rf "${HOME}/.claude/skills/frontend-design"
  ok "Claude Code: removed retired vendored skill ~/.claude/skills/frontend-design"
fi
# ui-ux-pro-max: vendor → upstream-install transition (2026-04-26). Same
# pattern as security-best-practices below — marker file `.upstream-installed`
# distinguishes upstream-installed copies from legacy vendored ones.
if [[ -d "${HOME}/.claude/skills/ui-ux-pro-max" ]] && \
   [[ ! -f "${HOME}/.claude/skills/ui-ux-pro-max/.upstream-installed" ]]; then
  rm -rf "${HOME}/.claude/skills/ui-ux-pro-max"
  ok "Claude Code: removed legacy vendored skill ~/.claude/skills/ui-ux-pro-max (will be re-installed from upstream)"
fi
# security-best-practices: vendor → upstream-install transition (2026-04-26).
# The skill is now installed by post-setup.sh via `npx skills add` from
# tech-leads-club/agent-skills (L2 "upstream CLI skill distribution" tier).
# Drop the stale vendored copy so post-setup's existence check sees no files
# and re-installs the upstream version on the next `make sync` / post-setup.
# A SKILL.md hash check is overkill — the upstream re-install is idempotent.
if [[ -d "${HOME}/.claude/skills/security-best-practices" ]] && \
   [[ ! -f "${HOME}/.claude/skills/security-best-practices/.upstream-installed" ]]; then
  # Use a marker file to distinguish vendored copies from upstream-installed
  # ones. Vendored copies (pre-2026-04-26) don't have the marker; upstream
  # installs by post-setup.sh write it on success.
  rm -rf "${HOME}/.claude/skills/security-best-practices"
  ok "Claude Code: removed legacy vendored skill ~/.claude/skills/security-best-practices (will be re-installed from upstream)"
fi
# Codex CLI was retired on 2026-04 alongside Gemini (see docs/notes/current-state.md).
# `home/dot_codex/` source was removed but chezmoi doesn't auto-prune the target,
# so ~/.codex/ persists on machines that synced before the source was deleted.
# Drop it here so `make ai-repair` converges old machines and ai-audit goes green.
if [[ -d "${HOME}/.codex" ]]; then
  rm -rf "${HOME}/.codex"
  ok "Codex: removed retired ~/.codex"
fi
# Serena MCP was retired in favor of native LSP + per-language plugins. The
# MCP registration is removed by the legacy-MCP scan below and the
# ~/.local/bin/serena-mcp wrapper is covered by the _orphan_scripts loop
# above, but ~/.serena/ (cache + memories) is not cleared by chezmoi alone.
# Drop it here so `make ai-repair` fully converges and ai-audit's
# "Retired Serena state" section goes green.
if [[ -e "${HOME}/.serena" ]]; then
  rm -rf "${HOME}/.serena"
  ok "Serena: removed retired ~/.serena"
fi
# dotfiles repo 内に Serena が遺した cache + memories の残骸も能動的に除去。
# `.gitignore` 済みなので `git status` には出ないが、ai-audit / 手動 ls の判断
# ノイズになるので home dir 側 (~/.serena) と同じ扱いにする。
if [[ -e "${REPO_ROOT}/.serena" ]]; then
  rm -rf "${REPO_ROOT}/.serena"
  ok "Serena: removed retired ${REPO_ROOT/#${HOME}/\~}/.serena"
fi
# Hookify trial residue (retired 2026-04-27, see decisions-archive.md). Rule
# files at ${REPO_ROOT}/.claude/hookify.*.local.md were placed during the
# 2026-04-25 trial; gitignored and cwd-relative, so chezmoi does not touch
# them. Scrub here so ai-audit / 手動 ls の判断ノイズが消える。~/.claude/
# 側の rule files は touch しない（hookify は cwd 相対設計で他 project の
# user 領域、勝手に消すと意図せぬ削除になる）。
shopt -s nullglob
_hookify_rules=("${REPO_ROOT}/.claude"/hookify.*.local.md)
shopt -u nullglob
if (( ${#_hookify_rules[@]} > 0 )); then
  rm -f "${_hookify_rules[@]}"
  ok "Hookify: removed retired rule files from ${REPO_ROOT/#${HOME}/\~}/.claude"
fi
unset _hookify_rules
# ~/.claude/.mcp.json was never loaded by Claude Code — none of the 3 valid MCP
# scopes (local / project / user) read that path. The chezmoi source
# `home/dot_claude/dot_mcp.json` was removed; drop the orphan target on existing
# machines so the dead-config drift source disappears. Real MCP registrations
# live in ~/.claude.json (managed by the upsert blocks above).
if [[ -e "${HOME}/.claude/.mcp.json" ]]; then
  rm -f "${HOME}/.claude/.mcp.json"
  ok "Claude Code: removed dead ~/.claude/.mcp.json (Claude never read it)"
fi

# Slash commands fully removed in 2026-04-26 cleanup. The L1 rule "Claude Code
# 標準機能で代替できないか先に確認" plus user signal "コマンド系使ったことない"
# made it clear the whole bundle was dead code (slash commands only load when
# the user types /<name>; if that never happens, the file content might as
# well not exist for Claude). Categories that were removed:
#   debug / security-review     → shadow Claude Code built-in commands
#   doc / notebook / pdf /
#   presentation / screenshot /
#   spreadsheet / ui-ux         → duplicate same-domain skill in ~/.claude/skills/
#                                 (skill auto-trigger covers invocation)
#   api-design / ci / diagram /
#   docker / refactor / test    → generic engineering methodology Claude already
#                                 carries natively
#   research                    → workflow scaffolding around Exa MCP, but L1
#                                 already directs Exa via the tool table
#   perf                        → Lighthouse orchestration; rare enough to
#                                 leave to general knowledge + L1
#   playwright                  → security guardrails were the only truly
#                                 critical content; moved to L1 inline
#                                 (read every turn, not gated on user invoke)
# chezmoi does not prune orphaned target files when the source disappears,
# so explicitly rm them here on every machine. Safe to re-run.
for _retired_command in api-design ci debug diagram doc docker notebook pdf perf playwright presentation refactor research screenshot security-review spreadsheet test ui-ux; do
  _retired_path="${HOME}/.claude/commands/${_retired_command}.md"
  if [[ -e "${_retired_path}" ]]; then
    rm -f "${_retired_path}"
    ok "Claude Code: removed retired slash command ${_retired_path/#${HOME}/\~}"
  fi
done
unset _retired_command _retired_path

# Document skills migration: vendored ~/.claude/skills/{doc,pdf,presentation,
# spreadsheet} were superseded by the document-skills plugin in the
# anthropic-agent-skills marketplace, then the plugin itself was retired on
# 2026-05-06 — the all-or-nothing 16-skill bundle costs ~2-3k token/turn for
# capabilities (algorithmic-art, slack-gif-creator etc.) used near-zero.
# Project-scoped install remains available; see post-setup.sh header.
for _legacy_doc_skill in doc pdf presentation spreadsheet; do
  if [[ -d "${HOME}/.claude/skills/${_legacy_doc_skill}" ]]; then
    rm -rf "${HOME}/.claude/skills/${_legacy_doc_skill}"
    ok "Document skills: removed legacy vendored ~/.claude/skills/${_legacy_doc_skill}"
  fi
done
unset _legacy_doc_skill

# Retire the document-skills plugin and its anthropic-agent-skills marketplace.
# Idempotent: silently skips when nothing is installed. `claude plugin
# uninstall` rewrites installed_plugins.json; `marketplace remove` drops the
# registration so post-setup doesn't re-pin it.
if command -v claude &>/dev/null; then
  if [[ -f "${HOME}/.claude/plugins/installed_plugins.json" ]] && \
     jq -e '.plugins | has("document-skills@anthropic-agent-skills")' \
       "${HOME}/.claude/plugins/installed_plugins.json" >/dev/null 2>&1; then
    if claude plugin uninstall document-skills@anthropic-agent-skills >/dev/null 2>&1; then
      ok "Claude Code: uninstalled retired plugin document-skills@anthropic-agent-skills"
    else
      warn "Claude Code: uninstall document-skills@anthropic-agent-skills failed — run manually"
    fi
  fi
  if [[ -f "${HOME}/.claude/plugins/known_marketplaces.json" ]] && \
     jq -e 'has("anthropic-agent-skills")' \
       "${HOME}/.claude/plugins/known_marketplaces.json" >/dev/null 2>&1; then
    if claude plugin marketplace remove anthropic-agent-skills >/dev/null 2>&1; then
      ok "Claude Code: removed retired marketplace anthropic-agent-skills"
    else
      warn "Claude Code: marketplace remove anthropic-agent-skills failed — run manually"
    fi
  fi
fi
# Belt-and-braces: claude plugin uninstall + marketplace remove only rewrite the
# JSON state files; the on-disk caches under ~/.claude/plugins/{cache,marketplaces}/
# can linger and Claude Code may still scan SKILL.md files there. Drop the dirs
# explicitly. ${marketplace_name}/ subtrees are large (skill bundles), so this
# is the bulk of the actual disk reclamation too.
for _legacy_cache in \
  "${HOME}/.claude/plugins/cache/anthropic-agent-skills" \
  "${HOME}/.claude/plugins/marketplaces/anthropic-agent-skills"; do
  if [[ -e "${_legacy_cache}" ]]; then
    rm -rf "${_legacy_cache}"
    ok "Claude Code: removed retired plugin cache ${_legacy_cache/#${HOME}/\~}"
  fi
done
unset _legacy_cache

# Retire the bulk googleworkspace/cli skill install (gws-* + recipe-* + persona-*).
# All ~92 skills came from a single `npx skills add ... -g`; project-scoped
# install remains available for projects that actually use them. We rm by glob
# rather than enumerating skill names so the cleanup stays correct even when
# upstream renames or adds skills.
shopt -s nullglob
_legacy_skill_dirs=(
  "${HOME}/.claude/skills"/gws-*
  "${HOME}/.claude/skills"/recipe-*
  "${HOME}/.claude/skills"/persona-*
)
shopt -u nullglob
if (( ${#_legacy_skill_dirs[@]} > 0 )); then
  for _legacy_skill_dir in "${_legacy_skill_dirs[@]}"; do
    rm -rf "${_legacy_skill_dir}"
  done
  ok "Claude Code: removed ${#_legacy_skill_dirs[@]} retired bulk-installed skills (gws-/recipe-/persona-)"
fi
unset _legacy_skill_dirs _legacy_skill_dir

# Strip legacy MCP registrations that have been retired.
#   playwright       → @playwright/cli + skill (see post-setup.sh)
#   filesystem       → native Claude Code Read/Write/Edit/Grep/Glob tools
#   drawio           → Mermaid (inline in .md) or mermaid-cli (mmdc) for PNG/SVG output
#   notion           → ntn CLI + makenotion/skills (see post-setup.sh)
#   github           → gh CLI (gh pr, gh issue, gh api …)
#   owlocr           → vision (@tuannvm/vision-mcp-server; upstream owlocr-mcp repo retired)
#   chrome-devtools  → @playwright/cli (pwedge zsh helper for AI-dedicated Edge);
#                      MCP kept spawning its own throwaway Chromium which defeats
#                      the whole point of using a persistent isolated profile
#   brave-search     → Exa MCP covers the same web-search surface; brave required
#                      a Keychain-backed API key whose value stopped justifying the
#                      extra wrapper plumbing
#   serena           → Claude Code native LSP tool + official per-language LSP
#                      plugins (claude-plugins-official: pyright-lsp / typescript-lsp /
#                      gopls-lsp / rust-analyzer-lsp / clangd-lsp / csharp-lsp /
#                      jdtls-lsp / kotlin-lsp / lua-lsp / php-lsp / ruby-lsp /
#                      swift-lsp). Cross-file rename / find-refs / diagnostics are
#                      covered by native tool; Serena wrapper + uvx dependency removed.
for _legacy in playwright filesystem drawio notion github owlocr chrome-devtools brave-search serena; do
  if [[ "$(ai_config_json_remove_mcp "${CLAUDE_JSON}" "${_legacy}" 2>/dev/null || true)" == "removed" ]]; then
    ok "Claude Code: legacy ${_legacy} MCP removed"
    restart_needed=1
  fi
done
unset _legacy

# ---- Claude Code local settings baseline -----------------------------------
# settings.json is partly local-managed (permissions / model / statusLine are
# written by Claude Code itself). We upsert the baseline keys dotfiles owns —
# auto-update channel, the ENABLE_TOOL_SEARCH env toggle, effortLevel, and
# hooks wired to dotfiles-managed scripts. Sibling keys stay untouched.
CLAUDE_HOOKS_BLOCK='{
  "PreToolUse": [
    {
      "matcher": "Grep",
      "hooks": [
        { "type": "command", "command": "$HOME/.claude/lsp-hint.sh" }
      ]
    }
  ],
  "Stop": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "$HOME/.claude/auto-save.sh" },
        { "type": "command", "command": "$HOME/.claude/chezmoi-auto-apply.sh" }
      ]
    }
  ],
  "Notification": [
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "osascript -e '"'"'display notification \"'"'"'\"$CLAUDE_NOTIFICATION_MESSAGE\"'"'"'\" with title \"Claude Code\" sound name \"Glass\"'"'"'" }
      ]
    }
  ]
}'

log "Claude Code local settings..."
mkdir -p "$(dirname "${CLAUDE_SETTINGS_JSON}")"
if [[ "$(ai_config_json_read "${CLAUDE_SETTINGS_JSON}" "d.get('autoUpdatesChannel','')" 2>/dev/null || true)" == "latest" ]]; then
  ok "Claude Code: auto-update channel already set to latest"
else
  ai_config_json_upsert_key "${CLAUDE_SETTINGS_JSON}" autoUpdatesChannel '"latest"'
  ok "Claude Code: auto-update channel set to latest"
fi

if [[ "$(ai_config_json_read "${CLAUDE_SETTINGS_JSON}" "d.get('env',{}).get('ENABLE_TOOL_SEARCH','')" 2>/dev/null || true)" == "auto:5" ]]; then
  ok "Claude Code: ENABLE_TOOL_SEARCH env already set"
else
  ai_config_json_upsert_nested_key "${CLAUDE_SETTINGS_JSON}" env.ENABLE_TOOL_SEARCH '"auto:5"'
  ok "Claude Code: ENABLE_TOOL_SEARCH env set"
fi

# effortLevel: high is the dotfiles baseline (降格 2026-04-27 from xhigh per
# user preference — xhigh tends to overthink for routine work). Treated as a
# team-shareable baseline like autoUpdatesChannel — local `/effort` overrides
# persist until the next `make ai-repair` snaps it back. See L2 judgment log.
if [[ "$(ai_config_json_read "${CLAUDE_SETTINGS_JSON}" "d.get('effortLevel','')" 2>/dev/null || true)" == "high" ]]; then
  ok "Claude Code: effortLevel already high"
else
  ai_config_json_upsert_key "${CLAUDE_SETTINGS_JSON}" effortLevel '"high"'
  ok "Claude Code: effortLevel set to high"
fi

# Hooks point at dotfiles-managed scripts (auto-save.sh / lsp-hint.sh), so the
# block is owned end-to-end by dotfiles — replace wholesale rather than merge.
# This does NOT clobber user-added hooks: Claude Code concatenates hooks across
# settings.json and settings.local.json (append semantics, not override). Any
# personal / per-machine hooks belong in ~/.claude/settings.local.json, which
# dotfiles never touches. Source: https://code.claude.com/docs/en/hooks.md
_claude_hooks_current="$(ai_config_json_read "${CLAUDE_SETTINGS_JSON}" "json.dumps(d.get('hooks',{}),sort_keys=True)" 2>/dev/null || true)"
_claude_hooks_expected="$(python3 -c "import json,sys; print(json.dumps(json.loads(sys.stdin.read()),sort_keys=True))" <<<"${CLAUDE_HOOKS_BLOCK}")"
if [[ "${_claude_hooks_current}" == "${_claude_hooks_expected}" ]]; then
  ok "Claude Code: hooks already match baseline"
else
  ai_config_json_upsert_key "${CLAUDE_SETTINGS_JSON}" hooks "${CLAUDE_HOOKS_BLOCK}"
  ok "Claude Code: hooks reset to baseline"
fi
unset _claude_hooks_current _claude_hooks_expected

printf '\nVerify with: make ai-audit\n'
if [[ "${restart_needed}" == "1" ]]; then
  printf 'Then restart Claude Code and close any old terminals still using stale MCP settings.\n'
fi
