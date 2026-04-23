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
# invoking `make ai-repair` simultaneously and fighting over ~/.claude.json /
# ~/.codex/config.toml mid-write. The $(id -u) suffix prevents a local user
# from squatting another user's lock directory on shared /tmp (macOS $TMPDIR
# is already per-user, but we add the uid for Linux/CI correctness).
LOCK_DIR="${TMPDIR:-/tmp}/dotfiles-ai-repair-$(id -u).lock"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  printf 'ERROR: another ai-repair run is in progress (lock: %s)\n' "${LOCK_DIR}" >&2
  printf '  If stale, remove with: rmdir %s\n' "${LOCK_DIR}" >&2
  exit 1
fi
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

SERENA_WRAPPER="${HOME}/.local/bin/serena-mcp"
SERENA_CONFIG_DIR="${HOME}/.serena"
SERENA_CONFIG_PATH="${SERENA_CONFIG_DIR}/serena_config.yml"
SERENA_CONFIG_BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"

CLAUDE_JSON="${HOME}/.claude.json"
CLAUDE_SETTINGS_JSON="${HOME}/.claude/settings.json"
CODEX_CONFIG="${HOME}/.codex/config.toml"
OPENAI_DOCS_MCP_URL="https://developers.openai.com/mcp"

restart_needed=0

write_serena_config() {
  mkdir -p "${SERENA_CONFIG_DIR}"
  cat > "${SERENA_CONFIG_PATH}" <<'EOF'
language_backend: LSP
web_dashboard: true
web_dashboard_open_on_launch: false
project_serena_folder_location: "$projectDir/.serena"
projects: []
EOF
}

# ---- Serena local config -----------------------------------------------------
log "Serena local config..."
if [[ ! -f "${SERENA_CONFIG_PATH}" ]]; then
  write_serena_config
  ok "Created Serena config at ${SERENA_CONFIG_PATH}"
else
  serena_config_ok=1
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^language_backend:[[:space:]]*LSP([[:space:]]|$)'; then
    serena_config_ok=0
  fi
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^web_dashboard:[[:space:]]*true([[:space:]]|$)'; then
    serena_config_ok=0
  fi
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^web_dashboard_open_on_launch:[[:space:]]*false([[:space:]]|$)'; then
    serena_config_ok=0
  fi
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^project_serena_folder_location:[[:space:]]*"\$projectDir/\.serena"([[:space:]]|$)'; then
    serena_config_ok=0
  fi
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^projects:'; then
    serena_config_ok=0
  fi

  if [[ "${serena_config_ok}" == "1" ]]; then
    ok "Serena config already matches expected defaults"
  else
    cp "${SERENA_CONFIG_PATH}" "${SERENA_CONFIG_PATH}.pre-ai-repair-${SERENA_CONFIG_BACKUP_SUFFIX}"
    write_serena_config
    ok "Reset Serena config to expected defaults"
    ok "Backup saved to ${SERENA_CONFIG_PATH}.pre-ai-repair-${SERENA_CONFIG_BACKUP_SUFFIX}"
  fi
  unset serena_config_ok
fi

# ---- Serena wrapper ----------------------------------------------------------
log "Serena wrapper..."
if [[ -x "${SERENA_WRAPPER}" ]]; then
  ok "Wrapper present: ${SERENA_WRAPPER}"
else
  warn "Wrapper missing: ${SERENA_WRAPPER}"
  warn "  Run: chezmoi apply"
fi

# ---- Claude Code MCP registration (JSON direct) -----------------------------
log "Claude Code MCP registration..."
SERENA_CLAUDE_ENTRY='{"type":"stdio","command":"'"${SERENA_WRAPPER}"'","args":["claude-code"],"env":{"UV_NATIVE_TLS":"true"}}'
EXA_CLAUDE_ENTRY='{"type":"http","url":"https://mcp.exa.ai/mcp"}'
# Slack's clientId / callbackPort below are public values published in Slack's
# official docs (https://docs.slack.dev/ai/slack-mcp-server/connect-to-claude/),
# not secrets. OAuth tokens themselves are managed by Claude Code, not dotfiles.
SLACK_CLAUDE_ENTRY='{"type":"http","url":"https://mcp.slack.com/mcp","oauth":{"clientId":"1601185624273.8899143856786","callbackPort":3118}}'
# vision-mcp-server is an npm-distributed Apple Vision Framework OCR MCP
# (@tuannvm/vision-mcp-server). Runs via `npx -y` — no wrapper, no Python
# toolchain. Requires macOS 13+ and Node.js 18+. If MCP connect fails,
# verify with: npx -y @tuannvm/vision-mcp-server --help
VISION_CLAUDE_ENTRY='{"type":"stdio","command":"npx","args":["-y","@tuannvm/vision-mcp-server"]}'
serena_cmd_state="$(ai_config_mcp_registration_state "${CLAUDE_JSON}" serena "${SERENA_WRAPPER}")"
serena_uv_tls="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('serena',{}).get('env',{}).get('UV_NATIVE_TLS','')" 2>/dev/null || true)"
claude_vision_cmd="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('vision',{}).get('command','')" 2>/dev/null || true)"
claude_vision_args="$(ai_config_json_read "${CLAUDE_JSON}" "'|'.join(d.get('mcpServers',{}).get('vision',{}).get('args',[]))" 2>/dev/null || true)"
claude_exa_url="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('exa',{}).get('url','')" 2>/dev/null || true)"
claude_slack_url="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('slack',{}).get('url','')" 2>/dev/null || true)"

if [[ "${serena_cmd_state}" == "ok" && "${serena_uv_tls}" == "true" ]]; then
  ok "Claude Code: serena already registered with wrapper and UV_NATIVE_TLS"
else
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" serena "${SERENA_CLAUDE_ENTRY}"
  if [[ "${serena_cmd_state}" != "ok" ]]; then
    ok "Claude Code: serena registration repaired/created"
  else
    ok "Claude Code: serena UV_NATIVE_TLS env added"
  fi
  restart_needed=1
fi
unset serena_cmd_state serena_uv_tls

_vision_expected_args='-y|@tuannvm/vision-mcp-server'
if [[ "${claude_vision_cmd}" != "npx" || "${claude_vision_args}" != "${_vision_expected_args}" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" vision "${VISION_CLAUDE_ENTRY}"
  ok "Claude Code: vision MCP registered"
  restart_needed=1
else
  ok "Claude Code: vision MCP already registered"
fi
unset _vision_expected_args

if [[ "${claude_exa_url}" != "https://mcp.exa.ai/mcp" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" exa "${EXA_CLAUDE_ENTRY}"
  ok "Claude Code: exa MCP registered"
  restart_needed=1
else
  ok "Claude Code: exa MCP already registered"
fi

if [[ "${claude_slack_url}" != "https://mcp.slack.com/mcp" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" slack "${SLACK_CLAUDE_ENTRY}"
  ok "Claude Code: slack MCP registered"
  restart_needed=1
else
  ok "Claude Code: slack MCP already registered"
fi

unset claude_vision_cmd claude_vision_args claude_exa_url claude_slack_url

# Strip retired hook artifacts. The hooks block itself is wholesale-rewritten
# below (so orphan UserPromptSubmit entries for session-topic disappear from
# settings.json), but chezmoi does not auto-remove the script file / cache dir
# once their source is deleted. Clean them up actively so other machines
# converge on `make ai-repair`.
_orphan_scripts=("${HOME}/.claude/session-topic.sh")
for _orphan in "${_orphan_scripts[@]}"; do
  if [[ -e "${_orphan}" ]]; then
    rm -f "${_orphan}"
    ok "Claude Code: removed retired hook script ${_orphan/#${HOME}/\~}"
  fi
done
unset _orphan_scripts
if [[ -d "${HOME}/.claude/session-topics" ]]; then
  rm -rf "${HOME}/.claude/session-topics"
  ok "Claude Code: removed retired session-topics cache"
fi
unset _orphan

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
for _legacy in playwright filesystem drawio notion github owlocr chrome-devtools brave-search; do
  if [[ "$(ai_config_json_remove_mcp "${CLAUDE_JSON}" "${_legacy}" 2>/dev/null || true)" == "removed" ]]; then
    ok "Claude Code: legacy ${_legacy} MCP removed"
    restart_needed=1
  fi
done
unset _legacy

# ---- Claude Code local settings baseline -----------------------------------
# settings.json is local-managed (permissions / model / effortLevel etc. are
# written by Claude Code itself). We only upsert the baseline keys dotfiles
# owns — env toggles, hooks wired to dotfiles-managed scripts, and the
# auto-update channel. Sibling keys stay untouched.
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
        { "type": "command", "command": "$HOME/.claude/auto-save.sh" }
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

# Hooks point at dotfiles-managed scripts (auto-save.sh / lsp-hint.sh), so the
# block is owned end-to-end by dotfiles — replace wholesale rather than merge.
_claude_hooks_current="$(ai_config_json_read "${CLAUDE_SETTINGS_JSON}" "json.dumps(d.get('hooks',{}),sort_keys=True)" 2>/dev/null || true)"
_claude_hooks_expected="$(python3 -c "import json,sys; print(json.dumps(json.loads(sys.stdin.read()),sort_keys=True))" <<<"${CLAUDE_HOOKS_BLOCK}")"
if [[ "${_claude_hooks_current}" == "${_claude_hooks_expected}" ]]; then
  ok "Claude Code: hooks already match baseline"
else
  ai_config_json_upsert_key "${CLAUDE_SETTINGS_JSON}" hooks "${CLAUDE_HOOKS_BLOCK}"
  ok "Claude Code: hooks reset to baseline"
fi
unset _claude_hooks_current _claude_hooks_expected

# ---- Codex baseline ---------------------------------------------------------
log "Codex baseline..."
mkdir -p "$(dirname "${CODEX_CONFIG}")"
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" model '"gpt-5.4"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" model_reasoning_effort '"medium"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" personality '"pragmatic"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" sandbox_mode '"workspace-write"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" approval_policy '"on-request"'
ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[features]" $'multi_agent = true\ncodex_hooks = true'
ok "Codex: baseline model/sandbox settings normalized"

# ---- Codex MCP registration (TOML direct) -----------------------------------
log "Codex MCP registration..."
case "$(ai_config_codex_mcp_state "${CODEX_CONFIG}" "${SERENA_WRAPPER}")" in
  ok)
    ok "Codex: serena already registered with wrapper"
    ;;
  wrong-command)
    ai_config_codex_upsert_mcp "${CODEX_CONFIG}" serena "${SERENA_WRAPPER}" codex
    ok "Codex: serena registration repaired"
    restart_needed=1
    ;;
  missing)
    ai_config_codex_upsert_mcp "${CODEX_CONFIG}" serena "${SERENA_WRAPPER}" codex
    ok "Codex: serena registration created"
    restart_needed=1
    ;;
esac

case "$(ai_config_codex_mcp_url_state "${CODEX_CONFIG}" openaiDeveloperDocs "${OPENAI_DOCS_MCP_URL}")" in
  ok)
    ok "Codex: OpenAI Docs MCP already registered"
    ;;
  wrong-url|missing)
    ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.openaiDeveloperDocs]" "url = \"${OPENAI_DOCS_MCP_URL}\""
    ok "Codex: OpenAI Docs MCP registered"
    restart_needed=1
    ;;
esac

codex_vision_cmd="$(ai_config_toml_read "${CODEX_CONFIG}" "d.get('mcp_servers',{}).get('vision',{}).get('command','')" 2>/dev/null || true)"
codex_vision_args="$(ai_config_toml_read "${CODEX_CONFIG}" "'|'.join(d.get('mcp_servers',{}).get('vision',{}).get('args',[]))" 2>/dev/null || true)"
codex_exa_url="$(ai_config_toml_read "${CODEX_CONFIG}" "d.get('mcp_servers',{}).get('exa',{}).get('url','')" 2>/dev/null || true)"
codex_slack_url="$(ai_config_toml_read "${CODEX_CONFIG}" "d.get('mcp_servers',{}).get('slack',{}).get('url','')" 2>/dev/null || true)"

_codex_vision_expected_args='-y|@tuannvm/vision-mcp-server'
if [[ "${codex_vision_cmd}" != "npx" || "${codex_vision_args}" != "${_codex_vision_expected_args}" ]]; then
  ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.vision]" $'command = "npx"\nargs = ["-y", "@tuannvm/vision-mcp-server"]'
  ok "Codex: vision MCP registered"
  restart_needed=1
else
  ok "Codex: vision MCP already registered"
fi
unset _codex_vision_expected_args

if [[ "${codex_exa_url}" != "https://mcp.exa.ai/mcp" ]]; then
  ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.exa]" 'url = "https://mcp.exa.ai/mcp"'
  ok "Codex: exa MCP registered"
  restart_needed=1
else
  ok "Codex: exa MCP already registered"
fi

if [[ "${codex_slack_url}" != "https://mcp.slack.com/mcp" ]]; then
  ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.slack]" 'url = "https://mcp.slack.com/mcp"'
  ok "Codex: slack MCP registered"
  restart_needed=1
else
  ok "Codex: slack MCP already registered"
fi

unset codex_vision_cmd codex_vision_args codex_exa_url codex_slack_url

# Strip legacy Codex MCP registrations retired in favor of CLIs / native tools
# or replaced by a newer MCP (owlocr → vision). chrome-devtools retired in
# favor of playwright-cli attach --cdp=chrome — MCP kept launching its own
# throwaway Chrome instead of driving the user's logged-in session.
# brave-search retired in favor of Exa MCP alone.
for _legacy in playwright filesystem drawio notion github owlocr chrome-devtools brave-search; do
  if [[ "$(ai_config_toml_remove_mcp_section "${CODEX_CONFIG}" "${_legacy}" 2>/dev/null || true)" == "removed" ]]; then
    ok "Codex: legacy ${_legacy} MCP removed"
    restart_needed=1
  fi
done
unset _legacy

printf '\nVerify with: make ai-audit\n'
if [[ "${restart_needed}" == "1" ]]; then
  printf 'Then restart Claude Code / Codex and close any old terminals still using stale MCP settings.\n'
fi
