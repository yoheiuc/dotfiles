# scripts/lib/claude-checks.sh — pure predicates for Claude Code config state.
# Sourced by ai-audit.sh and doctor.sh so the two scripts share read logic.
# Each predicate returns 0 (true) / 1 (false). Call sites format their own
# user-facing messages so each script keeps its own UI tone (and to preserve
# existing test assertions).
#
# Requires lib/ai-config.sh + lib/claude-plugins.sh to be sourced first.

# autoUpdatesChannel == "latest"
claude_autoupdate_is_latest() {
  [[ "$(ai_config_json_read "${HOME}/.claude/settings.json" "d.get('autoUpdatesChannel','')" 2>/dev/null || true)" == "latest" ]]
}

# env.ENABLE_TOOL_SEARCH == "auto:5"
claude_enable_tool_search_is_set() {
  [[ "$(ai_config_json_read "${HOME}/.claude/settings.json" "d.get('env',{}).get('ENABLE_TOOL_SEARCH','')" 2>/dev/null || true)" == "auto:5" ]]
}

# True if a hook block contains the given command string anywhere.
# Tolerates user-added matchers — only checks for command presence.
claude_hook_command_present() {
  local cmd="$1"
  local cmds
  cmds="$(ai_config_json_read "${HOME}/.claude/settings.json" "sorted({h.get('command','') for events in d.get('hooks',{}).values() if isinstance(events,list) for entry in events if isinstance(entry,dict) for h in entry.get('hooks',[]) if isinstance(h,dict)})" 2>/dev/null || true)"
  [[ "${cmds}" == *"${cmd}"* ]]
}

# Generic MCP presence check by name.
claude_mcp_present() {
  local file="$1" name="$2"
  [[ -f "${file}" ]] || return 1
  [[ "$(ai_config_json_read "${file}" "'present' if '${name}' in d.get('mcpServers',{}) else ''" 2>/dev/null || true)" == "present" ]]
}

# stdio MCP matches expected command + pipe-joined args.
claude_mcp_stdio_matches() {
  local file="$1" name="$2" expected_cmd="$3" expected_args="$4"
  local actual_cmd actual_args
  actual_cmd="$(ai_config_json_read "${file}" "d.get('mcpServers',{}).get('${name}',{}).get('command','')" 2>/dev/null || true)"
  actual_args="$(ai_config_json_read "${file}" "'|'.join(d.get('mcpServers',{}).get('${name}',{}).get('args',[]))" 2>/dev/null || true)"
  [[ "${actual_cmd}" == "${expected_cmd}" && "${actual_args}" == "${expected_args}" ]]
}

# HTTP MCP matches expected url and has type=http.
claude_mcp_http_matches() {
  local file="$1" name="$2" expected_url="$3"
  local actual_url actual_type
  actual_url="$(ai_config_json_read "${file}" "d.get('mcpServers',{}).get('${name}',{}).get('url','')" 2>/dev/null || true)"
  actual_type="$(ai_config_json_read "${file}" "d.get('mcpServers',{}).get('${name}',{}).get('type','')" 2>/dev/null || true)"
  [[ "${actual_url}" == "${expected_url}" && "${actual_type}" == "http" ]]
}

# Echoes plugin names from CLAUDE_LSP_PLUGINS that are NOT installed,
# one per line. Empty output = all installed.
claude_lsp_plugins_missing() {
  local p
  for p in "${CLAUDE_LSP_PLUGINS[@]}"; do
    claude_plugin_is_installed "${p}" || echo "${p}"
  done
}

# Same for CLAUDE_GENERAL_PLUGINS.
claude_general_plugins_missing() {
  local p
  for p in "${CLAUDE_GENERAL_PLUGINS[@]}"; do
    claude_plugin_is_installed "${p}" || echo "${p}"
  done
}
