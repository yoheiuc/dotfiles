#!/usr/bin/env bash
# serena-bootstrap.sh — project-local bootstrap for Serena
#
# Usage:
#   ./scripts/serena-bootstrap.sh [project_dir]
#
# - Ensure Serena index for the project is up to date
# - Print ready-to-paste prompts for Claude Code / Codex
set -euo pipefail

log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }

PROJECT_DIR="${1:-${PWD}}"

if [[ -z "${PROJECT_DIR}" ]]; then
  warn "project directory is empty"
  exit 64
fi

if [[ ! -d "${PROJECT_DIR}" ]]; then
  warn "project directory not found: ${PROJECT_DIR}"
  exit 66
fi

PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"

if ! command -v uvx >/dev/null 2>&1; then
  warn "uvx not found. Install uv first (brew install uv)."
  exit 1
fi

SERENA_WRAPPER="${HOME}/.local/bin/serena-mcp"
if [[ ! -x "${SERENA_WRAPPER}" ]]; then
  warn "serena wrapper not found: ${SERENA_WRAPPER}"
  warn "Run: chezmoi apply && ./scripts/post-setup.sh"
  exit 1
fi

log "Indexing project with Serena"
uvx --from git+https://github.com/oraios/serena serena index-project "${PROJECT_DIR}"
ok "Serena index updated: ${PROJECT_DIR}"

if command -v claude >/dev/null 2>&1; then
  log "Claude MCP status"
  claude mcp list 2>/dev/null | sed 's/^/    /' || warn "claude mcp list failed"
else
  warn "claude CLI not found"
fi

if command -v codex >/dev/null 2>&1; then
  log "Codex MCP status"
  codex mcp list 2>/dev/null | sed 's/^/    /' || warn "codex mcp list failed"
else
  warn "codex CLI not found"
fi

printf '\nNext prompts in Claude/Codex:\n'
printf '  1) /mcp__serena__initial_instructions\n'
printf '  2) プロジェクト %s を有効化してください\n' "${PROJECT_DIR}"
