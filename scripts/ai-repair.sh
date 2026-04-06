#!/usr/bin/env bash
# ai-repair.sh — normalize local AI runtime settings that commonly drift
#
# Usage:
#   ./scripts/ai-repair.sh
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"

log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }

SERENA_WRAPPER="${HOME}/.local/bin/serena-mcp"
SERENA_CONFIG_DIR="${HOME}/.serena"
SERENA_CONFIG_PATH="${SERENA_CONFIG_DIR}/serena_config.yml"
SERENA_CONFIG_BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"

restart_needed=0

run_mcp() {
  local timeout_seconds="$1"
  shift
  ai_config_run_with_timeout "${timeout_seconds}" "$@"
}

write_serena_config() {
  mkdir -p "${SERENA_CONFIG_DIR}"
  cat > "${SERENA_CONFIG_PATH}" <<'EOF'
language_backend: LSP
web_dashboard: true
web_dashboard_open_on_launch: false
project_serena_folder_location: "$projectDir/.serena"
EOF
}

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

log "Serena wrapper..."
if [[ -x "${SERENA_WRAPPER}" ]]; then
  ok "Wrapper present: ${SERENA_WRAPPER}"
else
  warn "Wrapper missing: ${SERENA_WRAPPER}"
  warn "  Run: chezmoi apply"
fi

log "Claude Code MCP registration..."
if command -v claude >/dev/null 2>&1; then
  if run_mcp 10 claude mcp get serena >/dev/null 2>&1; then
    if run_mcp 10 claude mcp get serena 2>/dev/null | grep -Fq -- "Command: ${SERENA_WRAPPER}"; then
      ok "Claude Code already uses the Serena wrapper"
    else
      if run_mcp 10 claude mcp remove serena -s user >/dev/null 2>&1 && \
         run_mcp 10 claude mcp add --scope user serena -- "${SERENA_WRAPPER}" claude-code >/dev/null 2>&1; then
        ok "Claude Code Serena registration repaired"
        restart_needed=1
      else
        warn "Claude Code Serena registration repair failed or timed out"
      fi
    fi
  else
    if run_mcp 10 claude mcp add --scope user serena -- "${SERENA_WRAPPER}" claude-code >/dev/null 2>&1; then
      ok "Claude Code Serena registration created"
      restart_needed=1
    else
      warn "Claude Code Serena registration create failed or timed out"
    fi
  fi
else
  warn "claude CLI not found — skipped"
fi

log "Codex MCP registration..."
if command -v codex >/dev/null 2>&1; then
  if run_mcp 10 codex mcp get serena --json >/dev/null 2>&1; then
    if run_mcp 10 codex mcp get serena --json 2>/dev/null | grep -Fq -- "\"${SERENA_WRAPPER}\""; then
      ok "Codex already uses the Serena wrapper"
    else
      if run_mcp 10 codex mcp remove serena >/dev/null 2>&1 && \
         run_mcp 10 codex mcp add serena -- "${SERENA_WRAPPER}" codex >/dev/null 2>&1; then
        ok "Codex Serena registration repaired"
        restart_needed=1
      else
        warn "Codex Serena registration repair failed or timed out"
      fi
    fi
  else
    if run_mcp 10 codex mcp add serena -- "${SERENA_WRAPPER}" codex >/dev/null 2>&1; then
      ok "Codex Serena registration created"
      restart_needed=1
    else
      warn "Codex Serena registration create failed or timed out"
    fi
  fi
else
  warn "codex CLI not found — skipped"
fi

printf '\nVerify with: make ai-audit\n'
if [[ "${restart_needed}" == "1" ]]; then
  printf 'Then restart Claude Code / Codex and close any old terminals still using stale MCP settings.\n'
fi
