#!/usr/bin/env bash
# ai-audit.sh — focused audit for local AI client configs and shared guidance
#
# Usage:
#   ./scripts/ai-audit.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ai-config.sh"

SECURITY_BIN="${SECURITY_BIN:-security}"
KEYCHAIN_SERVICE="dotfiles.ai.mcp"

ATTENTION_COUNT=0

section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
ok() { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
info() { printf '  - %s\n' "$*"; }
attention() {
  warn "$*"
  ATTENTION_COUNT=$((ATTENTION_COUNT + 1))
}

describe_file() {
  local label="$1"
  local path="$2"

  if [[ -f "${path}" ]]; then
    info "$(ai_config_describe_file "${label}" "${path}" 1)"
  else
    attention "${label}: missing (${path})"
  fi
}

scan_file_for_legacy_patterns() {
  local label="$1"
  local path="$2"

  if [[ ! -f "${path}" ]]; then
    return 0
  fi

  if ai_config_has_legacy_settings "${path}"; then
    attention "${label}: legacy bridge or unsafe approval settings detected"
  else
    ok "${label}: no legacy bridge settings detected"
  fi
}

report_optional_backups() {
  local label="$1"
  local glob_pattern="$2"
  local matches

  matches="$(ai_config_backup_matches "${glob_pattern}")"
  if [[ -z "${matches}" ]]; then
    ok "${label}: none found"
    return 0
  fi

  attention "${label}: found backup files to review or delete"
  printf '%s\n' "${matches}" | sed 's/^/    /'
}

echo
printf '\033[1m=== AI config audit ===\033[0m\n'

section "Local Config Files"
describe_file "Codex config" "${HOME}/.codex/config.toml"
describe_file "Claude settings" "${HOME}/.claude/settings.json"
describe_file "Gemini settings" "${HOME}/.gemini/settings.json"
describe_file "Serena config" "${HOME}/.serena/serena_config.yml"

section "Shared Guidance"
describe_file "Codex hooks" "${HOME}/.codex/hooks.json"
describe_file "Claude guidance" "${HOME}/.claude/CLAUDE.md"
describe_file "AGENTS" "${HOME}/AGENTS.md"

section "Legacy Pattern Scan"
scan_file_for_legacy_patterns "Codex config" "${HOME}/.codex/config.toml"
scan_file_for_legacy_patterns "Claude settings" "${HOME}/.claude/settings.json"
scan_file_for_legacy_patterns "Gemini settings" "${HOME}/.gemini/settings.json"
scan_file_for_legacy_patterns "Codex hooks" "${HOME}/.codex/hooks.json"
scan_file_for_legacy_patterns "Claude guidance" "${HOME}/.claude/CLAUDE.md"
scan_file_for_legacy_patterns "AGENTS" "${HOME}/AGENTS.md"

section "Claude Code Baseline"
if [[ -f "${HOME}/.claude/settings.json" ]]; then
  if [[ "$(ai_config_json_read "${HOME}/.claude/settings.json" "d.get('autoUpdatesChannel','')" 2>/dev/null || true)" == "latest" ]]; then
    ok "Claude Code: auto-update channel is latest"
  else
    attention "Claude Code: auto-update channel should be latest"
  fi

  if [[ "$(ai_config_json_read "${HOME}/.claude/settings.json" "d.get('env',{}).get('ENABLE_TOOL_SEARCH','')" 2>/dev/null || true)" == "auto:5" ]]; then
    ok "Claude Code: ENABLE_TOOL_SEARCH env is set"
  else
    attention "Claude Code: ENABLE_TOOL_SEARCH env should be auto:5 — run make ai-repair"
  fi

  # Hooks are baseline-managed by dotfiles. Verify each expected command is
  # wired up; tolerate extra user-added hooks under other matchers.
  _claude_hooks_cmds="$(ai_config_json_read "${HOME}/.claude/settings.json" "sorted({h.get('command','') for events in d.get('hooks',{}).values() if isinstance(events,list) for entry in events if isinstance(entry,dict) for h in entry.get('hooks',[]) if isinstance(h,dict)})" 2>/dev/null || true)"
  for _expected_cmd in '$HOME/.claude/lsp-hint.sh' '$HOME/.claude/auto-save.sh' '$HOME/.claude/session-topic.sh'; do
    if [[ "${_claude_hooks_cmds}" == *"${_expected_cmd}"* ]]; then
      ok "Claude Code: hook registered (${_expected_cmd})"
    else
      attention "Claude Code: hook missing (${_expected_cmd}) — run make ai-repair"
    fi
  done
  unset _claude_hooks_cmds _expected_cmd
else
  attention "Claude Code settings: missing (${HOME}/.claude/settings.json)"
fi

# Check a Claude Code stdio MCP by command + args.
# Usage: check_claude_stdio_mcp <json_file> <server_name> <expected_cmd> <expected_args_pipe_joined>
check_claude_stdio_mcp() {
  local file="$1" name="$2" expected_cmd="$3" expected_args="$4"
  local actual_cmd actual_args
  actual_cmd="$(ai_config_json_read "${file}" "d.get('mcpServers',{}).get('${name}',{}).get('command','')" 2>/dev/null || true)"
  actual_args="$(ai_config_json_read "${file}" "'|'.join(d.get('mcpServers',{}).get('${name}',{}).get('args',[]))" 2>/dev/null || true)"
  if [[ "${actual_cmd}" == "${expected_cmd}" && "${actual_args}" == "${expected_args}" ]]; then
    ok "Claude Code ${name} MCP: registered"
  else
    attention "Claude Code ${name} MCP: missing or drifted — run make ai-repair"
  fi
}

# Check a Claude Code HTTP MCP by url (and optionally type).
# Usage: check_claude_http_mcp <json_file> <server_name> <expected_url>
check_claude_http_mcp() {
  local file="$1" name="$2" expected_url="$3"
  local actual_url actual_type
  actual_url="$(ai_config_json_read "${file}" "d.get('mcpServers',{}).get('${name}',{}).get('url','')" 2>/dev/null || true)"
  actual_type="$(ai_config_json_read "${file}" "d.get('mcpServers',{}).get('${name}',{}).get('type','')" 2>/dev/null || true)"
  if [[ "${actual_url}" == "${expected_url}" && "${actual_type}" == "http" ]]; then
    ok "Claude Code ${name} MCP: registered"
  else
    attention "Claude Code ${name} MCP: missing or drifted — run make ai-repair"
  fi
}

# Check a Claude Code MCP by command only (ignoring args).
# Usage: check_claude_cmd_mcp <json_file> <server_name> <expected_cmd>
check_claude_cmd_mcp() {
  local file="$1" name="$2" expected_cmd="$3"
  local actual_cmd
  actual_cmd="$(ai_config_json_read "${file}" "d.get('mcpServers',{}).get('${name}',{}).get('command','')" 2>/dev/null || true)"
  if [[ "${actual_cmd}" == "${expected_cmd}" ]]; then
    ok "Claude Code ${name} MCP: registered"
  else
    attention "Claude Code ${name} MCP: missing or drifted — run make ai-repair"
  fi
}

_claude_json="${HOME}/.claude.json"
if [[ -f "${_claude_json}" ]]; then
  check_claude_stdio_mcp "${_claude_json}" chrome-devtools "npx" '-y|chrome-devtools-mcp@latest'
  check_claude_stdio_mcp "${_claude_json}" vision "npx" '-y|@tuannvm/vision-mcp-server'
  check_claude_http_mcp  "${_claude_json}" exa "https://mcp.exa.ai/mcp"
  check_claude_http_mcp  "${_claude_json}" slack "https://mcp.slack.com/mcp"
  check_claude_cmd_mcp   "${_claude_json}" brave-search "${HOME}/.local/bin/mcp-with-keychain-secret"

  # Warn on legacy MCP entries that have been retired.
  #   playwright  → @playwright/cli + skill
  #   filesystem  → native Claude Code Read/Write/Edit/Grep/Glob tools
  #   drawio      → Mermaid (inline in .md) or mermaid-cli (mmdc)
  #   notion      → ntn CLI + makenotion/skills
  #   github      → gh CLI
  #   owlocr      → vision (@tuannvm/vision-mcp-server; upstream owlocr-mcp repo retired)
  # Match on key presence so HTTP-type entries without `command` are still caught.
  for _legacy in playwright filesystem drawio notion github owlocr; do
    if [[ "$(ai_config_json_read "${_claude_json}" "'present' if '${_legacy}' in d.get('mcpServers',{}) else ''" 2>/dev/null || true)" == "present" ]]; then
      attention "Claude Code ${_legacy} MCP: legacy entry present — run make ai-repair"
    fi
  done
  unset _legacy
else
  attention "Claude Code MCP config: missing (${_claude_json})"
fi

# Check a Codex TOML setting.
# Usage: check_codex_setting <file> <python_expr> <expected> <ok_msg> <fail_msg>
check_codex_setting() {
  local file="$1" expr="$2" expected="$3" ok_msg="$4" fail_msg="$5"
  if [[ "$(ai_config_toml_read "${file}" "${expr}" 2>/dev/null || true)" == "${expected}" ]]; then
    ok "${ok_msg}"
  else
    attention "${fail_msg}"
  fi
}

section "Codex Baseline"
_codex_config="${HOME}/.codex/config.toml"
if [[ -f "${_codex_config}" ]]; then
  check_codex_setting "${_codex_config}" "d.get('model','')" "gpt-5.4" \
    "Codex: model is gpt-5.4" "Codex: model should be gpt-5.4"
  check_codex_setting "${_codex_config}" "d.get('model_reasoning_effort','')" "medium" \
    "Codex: default reasoning effort is medium" "Codex: default reasoning effort should be medium"
  check_codex_setting "${_codex_config}" "d.get('sandbox_mode','')" "workspace-write" \
    "Codex: sandbox mode is workspace-write" "Codex: sandbox mode should be workspace-write"
  check_codex_setting "${_codex_config}" "d.get('approval_policy','')" "on-request" \
    "Codex: approval policy is on-request" "Codex: approval policy should be on-request"
  check_codex_setting "${_codex_config}" "d.get('features',{}).get('codex_hooks',False)" "True" \
    "Codex: hooks enabled" "Codex: hooks should be enabled"
  check_codex_setting "${_codex_config}" "d.get('features',{}).get('multi_agent',False)" "True" \
    "Codex: multi-agent enabled" "Codex: multi-agent should be enabled"

  case "$(ai_config_codex_mcp_url_state "${_codex_config}" openaiDeveloperDocs "https://developers.openai.com/mcp")" in
    ok)
      ok "Codex OpenAI Docs MCP: registered"
      ;;
    wrong-url)
      attention "Codex OpenAI Docs MCP: wrong URL — run make ai-repair"
      ;;
    missing)
      attention "Codex OpenAI Docs MCP: missing — run make ai-repair"
      ;;
  esac

  for _server in chrome-devtools vision; do
    case "$(ai_config_toml_read "${_codex_config}" "d.get('mcp_servers',{}).get('${_server}',{}).get('command','')" 2>/dev/null || true)" in
      "")
        attention "Codex ${_server} MCP: missing — run make ai-repair"
        ;;
      *)
        ok "Codex ${_server} MCP: registered"
        ;;
    esac
  done

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('mcp_servers',{}).get('exa',{}).get('url','')" 2>/dev/null || true)" == "https://mcp.exa.ai/mcp" ]]; then
    ok "Codex exa MCP: registered"
  else
    attention "Codex exa MCP: missing — run make ai-repair"
  fi

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('mcp_servers',{}).get('slack',{}).get('url','')" 2>/dev/null || true)" == "https://mcp.slack.com/mcp" ]]; then
    ok "Codex slack MCP: registered"
  else
    attention "Codex slack MCP: missing — run make ai-repair"
  fi

  if [[ -n "$(ai_config_toml_read "${_codex_config}" "d.get('mcp_servers',{}).get('brave-search',{}).get('command','')" 2>/dev/null || true)" ]]; then
    ok "Codex brave-search MCP: registered"
  else
    attention "Codex brave-search MCP: missing — run make ai-repair"
  fi

  # Warn on legacy MCP entries that have been retired. Match on key presence.
  # owlocr → vision (@tuannvm/vision-mcp-server; upstream owlocr-mcp repo retired)
  for _legacy in playwright filesystem drawio notion github owlocr; do
    if [[ "$(ai_config_toml_read "${_codex_config}" "'present' if '${_legacy}' in d.get('mcp_servers',{}) else ''" 2>/dev/null || true)" == "present" ]]; then
      attention "Codex ${_legacy} MCP: legacy entry present — run make ai-repair"
    fi
  done
  unset _legacy

else
  attention "Codex config: missing (${_codex_config})"
fi

section "Serena Config"
if [[ -f "${HOME}/.serena/serena_config.yml" ]]; then
  if ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^language_backend:[[:space:]]*LSP([[:space:]]|$)'; then
    ok "Serena config: language_backend is LSP"
  else
    attention "Serena config: language_backend should be LSP"
  fi

  if ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^web_dashboard:[[:space:]]*true([[:space:]]|$)'; then
    ok "Serena config: web_dashboard enabled"
  else
    attention "Serena config: web_dashboard should be true"
  fi

  if ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^web_dashboard_open_on_launch:[[:space:]]*false([[:space:]]|$)'; then
    ok "Serena config: dashboard auto-open disabled"
  else
    attention "Serena config: web_dashboard_open_on_launch should be false"
  fi

  if ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^project_serena_folder_location:[[:space:]]*"\$projectDir/\.serena"([[:space:]]|$)'; then
    ok "Serena config: project metadata stored in-project"
  else
    attention 'Serena config: project_serena_folder_location should be "$projectDir/.serena"'
  fi
else
  attention "Serena config: missing (${HOME}/.serena/serena_config.yml)"
fi

section "MCP Registration"
_serena_wrapper="${HOME}/.local/bin/serena-mcp"

_claude_json="${HOME}/.claude.json"
case "$(ai_config_mcp_registration_state "${_claude_json}" serena "${_serena_wrapper}")" in
  ok)
    ok "Claude Code Serena MCP: registered"
    ;;
  wrong-command)
    attention "Claude Code Serena MCP: wrong command — run make ai-repair"
    ;;
  missing)
    attention "Claude Code Serena MCP: missing — run make ai-repair"
    ;;
esac

case "$(ai_config_codex_mcp_state "${_codex_config}" "${_serena_wrapper}")" in
  ok)
    ok "Codex Serena MCP: registered via wrapper"
    ;;
  wrong-command)
    attention "Codex Serena MCP: wrong command — run make ai-repair"
    ;;
  missing)
    attention "Codex Serena MCP: missing — run make ai-repair"
    ;;
esac
unset _serena_wrapper _claude_json _codex_config

section "MCP Credentials (Keychain)"
# Brave Search MCP requires a key in macOS Keychain (service: dotfiles.ai.mcp,
# account: brave-api-key) so the mcp-with-keychain-secret wrapper can inject it.
if ! command -v "${SECURITY_BIN}" >/dev/null 2>&1; then
  info "security CLI unavailable — skipping Keychain checks (non-macOS?)"
elif "${SECURITY_BIN}" find-generic-password -s "${KEYCHAIN_SERVICE}" -a brave-api-key >/dev/null 2>&1; then
  ok "Brave API key: present in Keychain (service=${KEYCHAIN_SERVICE}, account=brave-api-key)"
else
  attention "Brave API key: missing in Keychain — run: ai-secrets"
fi

section "Backup Files"
report_optional_backups "Codex config backups" "${HOME}/.codex/config.toml.pre-unmanage-*"
report_optional_backups "Claude settings backups" "${HOME}/.claude/settings.json.pre-unmanage-*"
report_optional_backups "Gemini settings backups" "${HOME}/.gemini/settings.json.pre-unmanage-*"

echo
if [[ "${ATTENTION_COUNT}" -eq 0 ]]; then
  printf '\033[1;32mAI config audit looks good.\033[0m\n'
else
  printf '\033[1;33mAI config audit needs attention: %s item(s).\033[0m\n' "${ATTENTION_COUNT}"
fi
