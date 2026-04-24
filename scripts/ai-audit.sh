#!/usr/bin/env bash
# ai-audit.sh — focused audit for local AI client configs and shared guidance
#
# Usage:
#   ./scripts/ai-audit.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ui.sh"
source "${SCRIPT_DIR}/lib/ai-config.sh"

ATTENTION_COUNT=0

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
describe_file "Claude settings" "${HOME}/.claude/settings.json"

section "Shared Guidance"
describe_file "Claude guidance" "${HOME}/.claude/CLAUDE.md"

section "Legacy Pattern Scan"
scan_file_for_legacy_patterns "Claude settings" "${HOME}/.claude/settings.json"
scan_file_for_legacy_patterns "Claude guidance" "${HOME}/.claude/CLAUDE.md"

section "Retired Agent Configs"
# Codex / Gemini were retired from this dotfiles setup. Stale state under
# ~/.codex or ~/.gemini is harmless but flagged so the user can remove it.
for _retired_path in "${HOME}/.codex" "${HOME}/.gemini"; do
  if [[ -e "${_retired_path}" ]]; then
    attention "Retired agent state still on disk: ${_retired_path} (safe to rm -rf if no longer needed)"
  else
    ok "No retired agent state at ${_retired_path}"
  fi
done
unset _retired_path

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
  for _expected_cmd in '$HOME/.claude/lsp-hint.sh' '$HOME/.claude/auto-save.sh'; do
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
  check_claude_stdio_mcp "${_claude_json}" vision "npx" '-y|@tuannvm/vision-mcp-server'
  check_claude_http_mcp  "${_claude_json}" exa "https://mcp.exa.ai/mcp"
  check_claude_http_mcp  "${_claude_json}" slack "https://mcp.slack.com/mcp"

  # Warn on legacy MCP entries that have been retired.
  #   playwright       → @playwright/cli + skill
  #   filesystem       → native Claude Code Read/Write/Edit/Grep/Glob tools
  #   drawio           → Mermaid (inline in .md) or mermaid-cli (mmdc)
  #   notion           → ntn CLI + makenotion/skills
  #   github           → gh CLI
  #   owlocr           → vision (@tuannvm/vision-mcp-server; upstream owlocr-mcp repo retired)
  #   chrome-devtools  → playwright-cli attach --cdp=chrome (pwattach helper)
  #   brave-search     → Exa MCP alone covers web search
  # Match on key presence so HTTP-type entries without `command` are still caught.
  for _legacy in playwright filesystem drawio notion github owlocr chrome-devtools brave-search serena; do
    if [[ "$(ai_config_json_read "${_claude_json}" "'present' if '${_legacy}' in d.get('mcpServers',{}) else ''" 2>/dev/null || true)" == "present" ]]; then
      attention "Claude Code ${_legacy} MCP: legacy entry present — run make ai-repair"
    fi
  done
  unset _legacy
else
  attention "Claude Code MCP config: missing (${_claude_json})"
fi

section "Retired Serena state"
# Serena MCP was retired in favor of Claude Code's native LSP tool plus the
# per-language plugins shipped via claude-plugins-official. Leftover state from
# the old install is harmless but flagged so the user can clean up. The
# per-MCP legacy scan above already covers the .claude.json registration.
if [[ -e "${HOME}/.serena" ]]; then
  attention "Retired Serena state still on disk: ${HOME}/.serena (safe to rm -rf if no longer needed)"
fi
if [[ -e "${HOME}/.local/bin/serena-mcp" ]]; then
  attention "Retired Serena wrapper still present: ${HOME}/.local/bin/serena-mcp (should be removed by chezmoi apply)"
fi

section "Backup Files"
report_optional_backups "Claude settings backups" "${HOME}/.claude/settings.json.pre-unmanage-*"

echo
if [[ "${ATTENTION_COUNT}" -eq 0 ]]; then
  printf '\033[1;32mAI config audit looks good.\033[0m\n'
else
  printf '\033[1;33mAI config audit needs attention: %s item(s).\033[0m\n' "${ATTENTION_COUNT}"
fi
