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
claude_vision_cmd="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('vision',{}).get('command','')" 2>/dev/null || true)"
claude_vision_args="$(ai_config_json_read "${CLAUDE_JSON}" "'|'.join(d.get('mcpServers',{}).get('vision',{}).get('args',[]))" 2>/dev/null || true)"
claude_exa_url="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('exa',{}).get('url','')" 2>/dev/null || true)"
claude_jamf_docs_url="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('jamf-docs',{}).get('url','')" 2>/dev/null || true)"
claude_slack_url="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('slack',{}).get('url','')" 2>/dev/null || true)"

_vision_expected_args='-y|@tuannvm/vision-mcp-server'
if [[ "${claude_vision_cmd}" != "npx" || "${claude_vision_args}" != "${_vision_expected_args}" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" vision "${VISION_CLAUDE_ENTRY}"
  ok "Claude Code: vision MCP registered"
  restart_needed=1
else
  ok "Claude Code: vision MCP already registered"
fi
unset _vision_expected_args

if [[ "${claude_exa_url}" != "https://mcp.exa.ai/mcp?tools=web_search_exa,web_fetch_exa,web_search_advanced_exa" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" exa "${EXA_CLAUDE_ENTRY}"
  ok "Claude Code: exa MCP registered"
  restart_needed=1
else
  ok "Claude Code: exa MCP already registered"
fi

if [[ "${claude_jamf_docs_url}" != "https://developer.jamf.com/mcp" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" jamf-docs "${JAMF_DOCS_CLAUDE_ENTRY}"
  ok "Claude Code: jamf-docs MCP registered"
  restart_needed=1
else
  ok "Claude Code: jamf-docs MCP already registered"
fi

if [[ "${claude_slack_url}" != "https://mcp.slack.com/mcp" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" slack "${SLACK_CLAUDE_ENTRY}"
  ok "Claude Code: slack MCP registered"
  restart_needed=1
else
  ok "Claude Code: slack MCP already registered"
fi

unset claude_vision_cmd claude_vision_args claude_exa_url claude_jamf_docs_url claude_slack_url

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
unset _orphan_scripts
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
unset _orphan

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
#   perf                        → Lighthouse + pwattach orchestration; rare
#                                 enough to leave to general knowledge + L1
#   playwright                  → CDP-attach security guardrails were the only
#                                 truly critical content; moved to L1 inline
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

# Strip legacy MCP registrations that have been retired.
#   playwright       → @playwright/cli + skill (see post-setup.sh)
#   filesystem       → native Claude Code Read/Write/Edit/Grep/Glob tools
#   drawio           → Mermaid (inline in .md) or mermaid-cli (mmdc) for PNG/SVG output
#   notion           → ntn CLI + makenotion/skills (see post-setup.sh)
#   github           → gh CLI (gh pr, gh issue, gh api …)
#   owlocr           → vision (@tuannvm/vision-mcp-server; upstream owlocr-mcp repo retired)
#   chrome-devtools  → playwright-cli attach --cdp=chrome (see pwattach zsh helper);
#                      MCP kept spawning its own throwaway Chrome which defeats the
#                      whole point of driving the user's logged-in session
#   brave-search     → Exa MCP covers the same web-search surface; brave required
#                      a Keychain-backed API key whose value stopped justifying the
#                      extra wrapper + ai-secrets flow
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

# effortLevel: xhigh is the Opus 4.7 official recommended default ("ほぼ全タスクで
# xhigh、最難関だけ max"). Treated as a team-shareable baseline like
# autoUpdatesChannel — local `/effort` overrides persist until the next
# `make ai-repair` snaps it back. See L2 judgment log (2026-04-26).
if [[ "$(ai_config_json_read "${CLAUDE_SETTINGS_JSON}" "d.get('effortLevel','')" 2>/dev/null || true)" == "xhigh" ]]; then
  ok "Claude Code: effortLevel already xhigh"
else
  ai_config_json_upsert_key "${CLAUDE_SETTINGS_JSON}" effortLevel '"xhigh"'
  ok "Claude Code: effortLevel set to xhigh"
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
