#!/usr/bin/env bash
# ai-audit.sh — focused audit for local AI client configs and shared guidance
#
# Usage:
#   ./scripts/ai-audit.sh [-q|--quiet]
#
# Flags:
#   -q, --quiet   Suppress section / ok / info lines and the final summary.
#                 Only attention items are printed, so CI / notification
#                 pipelines can grep stdout (empty = clean).
#                 Also makes the script exit non-zero (1) when at least one
#                 attention item is found, so CI can fail the job directly.
#                 Default mode always exits 0 (informational).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ui.sh"
source "${SCRIPT_DIR}/lib/ai-config.sh"
source "${SCRIPT_DIR}/lib/claude-plugins.sh"
source "${SCRIPT_DIR}/lib/claude-checks.sh"

QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quiet) QUIET=1; shift ;;
    -h|--help)
      # Render the leading comment block as plain help text: skip the shebang,
      # take consecutive `#`-prefixed lines, strip the leading `#` / `# `,
      # and stop at the first non-comment line. Avoids line-number drift.
      awk 'NR==1{next} /^#/{sub(/^#[[:space:]]?/,""); print; next} {exit}' \
        "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      printf 'ai-audit: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

# In quiet mode, silence the structural / success-path output. attention()
# still calls warn() (defined in ui.sh) so problem lines stay visible.
if [[ "${QUIET}" == "1" ]]; then
  section() { :; }
  ok()      { :; }
  info()    { :; }
fi

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

if [[ "${QUIET}" != "1" ]]; then
  echo
  printf '\033[1m=== AI config audit ===\033[0m\n'
fi

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

# session-topic の UserPromptSubmit hook 廃止後の残骸を flag。
# ai-repair.sh が ~/.claude/session-topic.sh と ~/.claude/session-topics/ を能動削除する以上、
# audit 側でも対応する flag を出して audit-repair invariant を保つ。
for _retired_session_topic in "${HOME}/.claude/session-topic.sh" "${HOME}/.claude/session-topics"; do
  if [[ -e "${_retired_session_topic}" ]]; then
    attention "Retired session-topics state still on disk: ${_retired_session_topic} — run make ai-repair to scrub"
  fi
done
unset _retired_session_topic

section "Claude Code Baseline"
if [[ -f "${HOME}/.claude/settings.json" ]]; then
  if claude_autoupdate_is_latest; then
    ok "Claude Code: auto-update channel is latest"
  else
    attention "Claude Code: auto-update channel should be latest"
  fi

  if claude_enable_tool_search_is_set; then
    ok "Claude Code: ENABLE_TOOL_SEARCH env is set"
  else
    attention "Claude Code: ENABLE_TOOL_SEARCH env should be auto:5 — run make ai-repair"
  fi

  if claude_effort_is_high; then
    ok "Claude Code: effortLevel is high"
  else
    attention "Claude Code: effortLevel should be high (dotfiles baseline) — run make ai-repair"
  fi

  # Hooks are baseline-managed by dotfiles. Verify each expected command is
  # wired up; tolerate extra user-added hooks under other matchers.
  for _expected_cmd in '$HOME/.claude/lsp-hint.sh' '$HOME/.claude/auto-save.sh' '$HOME/.claude/chezmoi-auto-apply.sh'; do
    if claude_hook_command_present "${_expected_cmd}"; then
      ok "Claude Code: hook registered (${_expected_cmd})"
    else
      attention "Claude Code: hook missing (${_expected_cmd}) — run make ai-repair"
    fi
  done
  unset _expected_cmd
else
  attention "Claude Code settings: missing (${HOME}/.claude/settings.json)"
fi

_claude_json="${HOME}/.claude.json"
if [[ -f "${_claude_json}" ]]; then
  if claude_mcp_stdio_matches "${_claude_json}" vision "npx" '-y|@tuannvm/vision-mcp-server'; then
    ok "Claude Code vision MCP: registered"
  else
    attention "Claude Code vision MCP: missing or drifted — run make ai-repair"
  fi
  if claude_mcp_stdio_matches "${_claude_json}" sequential-thinking "npx" '-y|@modelcontextprotocol/server-sequential-thinking'; then
    ok "Claude Code sequential-thinking MCP: registered"
  else
    attention "Claude Code sequential-thinking MCP: missing or drifted — run make ai-repair"
  fi
  if claude_mcp_http_matches "${_claude_json}" exa "https://mcp.exa.ai/mcp?tools=web_search_exa,web_fetch_exa,web_search_advanced_exa"; then
    ok "Claude Code exa MCP: registered"
  else
    attention "Claude Code exa MCP: missing or drifted — run make ai-repair"
  fi
  if claude_mcp_http_matches "${_claude_json}" jamf-docs "https://developer.jamf.com/mcp"; then
    ok "Claude Code jamf-docs MCP: registered"
  else
    attention "Claude Code jamf-docs MCP: missing or drifted — run make ai-repair"
  fi
  if claude_mcp_http_matches "${_claude_json}" slack "https://mcp.slack.com/mcp"; then
    ok "Claude Code slack MCP: registered"
  else
    attention "Claude Code slack MCP: missing or drifted — run make ai-repair"
  fi

  # Warn on legacy MCP entries that have been retired.
  #   playwright       → @playwright/cli + skill
  #   filesystem       → native Claude Code Read/Write/Edit/Grep/Glob tools
  #   drawio           → Mermaid (inline in .md) or mermaid-cli (mmdc)
  #   notion           → ntn CLI + makenotion/skills
  #   github           → gh CLI
  #   owlocr           → vision (@tuannvm/vision-mcp-server; upstream owlocr-mcp repo retired)
  #   chrome-devtools  → @playwright/cli (pwedge zsh helper for AI-dedicated Edge)
  #   brave-search     → Exa MCP alone covers web search
  for _legacy in playwright filesystem drawio notion github owlocr chrome-devtools brave-search serena; do
    if claude_mcp_present "${_claude_json}" "${_legacy}"; then
      attention "Claude Code ${_legacy} MCP: legacy entry present — run make ai-repair"
    fi
  done
  unset _legacy
else
  attention "Claude Code MCP config: missing (${_claude_json})"
fi

section "Claude Code Plugins"
# Plugin install summary lives in scripts/lib/claude-plugins.sh so doctor
# and ai-audit cannot drift in message shape.
if _msg="$(claude_plugins_check_summary LSP claude_lsp_plugins_missing "${#CLAUDE_LSP_PLUGINS[@]}")"; then
  ok "${_msg}"
else
  attention "${_msg}"
fi
if _msg="$(claude_plugins_check_summary general claude_general_plugins_missing "${#CLAUDE_GENERAL_PLUGINS[@]}")"; then
  ok "${_msg}"
else
  attention "${_msg}"
fi
unset _msg

# Retired bulk-installed skills (gws-* / recipe-* / persona-*) and
# document-skills plugin / anthropic-agent-skills marketplace. ai-repair scrubs
# them; flag here so drift detection catches stragglers from machines that
# haven't run ai-repair yet.
if [[ -d "${HOME}/.claude/skills" ]]; then
  shopt -s nullglob
  _legacy_bulk=("${HOME}/.claude/skills"/gws-* "${HOME}/.claude/skills"/recipe-* "${HOME}/.claude/skills"/persona-*)
  shopt -u nullglob
  if (( ${#_legacy_bulk[@]} > 0 )); then
    attention "Retired bulk skills (${#_legacy_bulk[@]}) under ~/.claude/skills/{gws,recipe,persona}-* — run make ai-repair"
  fi
  unset _legacy_bulk
fi
if [[ -f "${HOME}/.claude/plugins/installed_plugins.json" ]] && \
   jq -e '.plugins | has("'"${CLAUDE_LEGACY_DOCUMENT_PLUGIN_NAME}"'@'"${CLAUDE_LEGACY_DOCUMENT_MARKETPLACE_NAME}"'")' \
     "${HOME}/.claude/plugins/installed_plugins.json" >/dev/null 2>&1; then
  attention "Retired plugin ${CLAUDE_LEGACY_DOCUMENT_PLUGIN_NAME}@${CLAUDE_LEGACY_DOCUMENT_MARKETPLACE_NAME} still installed — run make ai-repair"
fi
if [[ -f "${HOME}/.claude/plugins/known_marketplaces.json" ]] && \
   jq -e 'has("'"${CLAUDE_LEGACY_DOCUMENT_MARKETPLACE_NAME}"'")' \
     "${HOME}/.claude/plugins/known_marketplaces.json" >/dev/null 2>&1; then
  attention "Retired marketplace ${CLAUDE_LEGACY_DOCUMENT_MARKETPLACE_NAME} still registered — run make ai-repair"
fi
for _legacy_cache in \
  "${HOME}/.claude/plugins/cache/${CLAUDE_LEGACY_DOCUMENT_MARKETPLACE_NAME}" \
  "${HOME}/.claude/plugins/marketplaces/${CLAUDE_LEGACY_DOCUMENT_MARKETPLACE_NAME}"; do
  if [[ -e "${_legacy_cache}" ]]; then
    attention "Retired plugin cache still on disk: ${_legacy_cache} — run make ai-repair"
  fi
done
unset _legacy_cache

section "Retired Serena state"
# Serena MCP was retired in favor of Claude Code's native LSP tool plus the
# per-language plugins shipped via claude-plugins-official. Leftover state from
# the old install is harmless but flagged so the user can clean up. The
# per-MCP legacy scan above already covers the .claude.json registration.
if [[ -e "${HOME}/.serena" ]]; then
  attention "Retired Serena state still on disk: ${HOME}/.serena (safe to rm -rf if no longer needed)"
fi
_audit_repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -e "${_audit_repo_root}/.serena" ]]; then
  attention "Retired Serena state still in repo: ${_audit_repo_root}/.serena (safe to rm -rf, ai-repair will scrub)"
fi
unset _audit_repo_root
if [[ -e "${HOME}/.local/bin/serena-mcp" ]]; then
  attention "Retired Serena wrapper still present: ${HOME}/.local/bin/serena-mcp (should be removed by chezmoi apply)"
fi

section "Retired Hookify state"
# Hookify trial was retired 2026-04-27 (see decisions-archive.md). Flag any
# leftover so the user can scrub it. ai-repair handles the repo-local rule
# files automatically; the plugin uninstall is left manual since it requires
# the `claude` CLI on PATH.
_audit_repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
shopt -s nullglob
_hookify_rules=("${_audit_repo_root}/.claude"/hookify.*.local.md)
shopt -u nullglob
if (( ${#_hookify_rules[@]} > 0 )); then
  attention "Retired Hookify rule files still in repo: ${_audit_repo_root}/.claude/hookify.*.local.md — run make ai-repair to scrub"
fi
unset _hookify_rules _audit_repo_root
if claude_plugin_is_installed "hookify" "${CLAUDE_PLUGIN_MARKETPLACE_NAME}"; then
  attention "Retired Hookify plugin still installed — run: claude plugin uninstall hookify@${CLAUDE_PLUGIN_MARKETPLACE_NAME}"
fi

section "Playwright Wrapper"
# Ephemeral pwopen contract: profile is wiped on browser close so AI session
# state (cookie / token / cache) doesn't linger on disk, and per-invocation
# unique profile path prevents cross-session sharing. L1 / L2 mandate this; if
# the wrapper drifts, surface it here so `make ai-audit -q` catches it in CI.
if [[ -f "${HOME}/.config/zsh/playwright.zsh" ]]; then
  if playwright_pwopen_is_ephemeral; then
    ok "playwright pwopen: ephemeral cleanup wired (close+delete-data+rm on EXIT/INT/TERM, chmod 700, per-invocation profile)"
  else
    attention "playwright pwopen: ephemeral cleanup not wired — sessions persist on disk after browser close. Run: chezmoi apply"
  fi
else
  ok "playwright pwopen: zsh wrapper not installed (skipped)"
fi

section "Backup Files"
report_optional_backups "Claude settings backups" "${HOME}/.claude/settings.json.pre-unmanage-*"

if [[ "${QUIET}" != "1" ]]; then
  echo
  if [[ "${ATTENTION_COUNT}" -eq 0 ]]; then
    printf '\033[1;32mAI config audit looks good.\033[0m\n'
  else
    printf '\033[1;33mAI config audit needs attention: %s item(s).\033[0m\n' "${ATTENTION_COUNT}"
  fi
elif [[ "${ATTENTION_COUNT}" -gt 0 ]]; then
  # Quiet mode is for CI / scripted use — propagate the failure via exit code
  # so callers can `if ! ai-audit -q; then ...` without grep'ing stdout.
  exit 1
fi
