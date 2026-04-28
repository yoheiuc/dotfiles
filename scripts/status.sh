#!/usr/bin/env bash
# status.sh — compact daily status for this dotfiles repo and local AI configs
#
# Usage:
#   ./scripts/status.sh
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${REPO_ROOT}/scripts/lib/ui.sh"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"
source "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh"

ATTENTION_COUNT=0

attention() {
  warn "$*"
  ATTENTION_COUNT=$((ATTENTION_COUNT + 1))
}

audit_local_file() {
  local label="$1"
  local path="$2"

  info "$(ai_config_describe_file "${label}" "${path}")"
}

echo
printf '\033[1m=== dotfiles status ===\033[0m\n'

section "Repo"
if git_status_out="$(git -C "${REPO_ROOT}" status --short --branch 2>&1)"; then
  branch_line="$(printf '%s\n' "${git_status_out}" | head -n 1 | sed 's/^## //')"
  if [[ -n "${branch_line}" ]]; then
    ok "git: ${branch_line}"
  else
    ok "git: repository detected"
  fi

  worktree_lines="$(printf '%s\n' "${git_status_out}" | tail -n +2 | sed '/^$/d')"
  if [[ -z "${worktree_lines}" ]]; then
    ok "working tree: clean"
  else
    attention "working tree: local changes detected"
    printf '%s\n' "${worktree_lines}" | sed 's/^/    /'
  fi
else
  attention "git status failed"
  printf '%s\n' "${git_status_out}" | sed 's/^/    /'
fi

section "chezmoi"
if command -v chezmoi >/dev/null 2>&1; then
  set +e
  chezmoi_status_out="$(chezmoi status 2>&1)"
  chezmoi_status_code=$?
  set -e

  if [[ "${chezmoi_status_code}" -ne 0 ]]; then
    attention "chezmoi status failed"
    printf '%s\n' "${chezmoi_status_out}" | sed 's/^/    /'
  elif [[ -z "$(printf '%s\n' "${chezmoi_status_out}" | sed '/^$/d')" ]]; then
    ok "chezmoi managed files: clean"
  else
    attention "chezmoi managed files: pending changes detected"
    printf '%s\n' "${chezmoi_status_out}" | sed 's/^/    /'
  fi
else
  attention "chezmoi not found"
fi

section "Brew"
set +e
brew_check_out="$(bash "${REPO_ROOT}/scripts/brew-bundle.sh" check 2>&1)"
set -e

if printf '%s\n' "${brew_check_out}" | grep -q "The Brewfile's dependencies are satisfied."; then
  ok "Brewfile: all declared packages present"
else
  attention "Brewfile: missing packages or check failed"
  printf '%s\n' "${brew_check_out}" | grep -v '^Using ' | sed 's/^/    /' || true
fi

section "Playwright CLI"
if command -v playwright-cli >/dev/null 2>&1; then
  ok "playwright-cli: $(playwright-cli --version 2>&1 | head -1)"
  if [[ -n "${PLAYWRIGHT_CLI_SESSION:-}" ]]; then
    info "PLAYWRIGHT_CLI_SESSION=${PLAYWRIGHT_CLI_SESSION}"
  fi
else
  warn "playwright-cli not found — run: ./scripts/post-setup.sh"
fi

section "Document toolchain"
if command -v pandoc >/dev/null 2>&1; then
  ok "pandoc: $(pandoc --version 2>&1 | head -1)"
else
  warn "pandoc not found — install via Brewfile (brew \"pandoc\")"
fi
if command -v pdflatex >/dev/null 2>&1; then
  ok "pdflatex: available (needed for pandoc PDF output)"
else
  warn "pdflatex not found — install via Brewfile (cask \"basictex\") and open a new terminal"
fi
if command -v mmdc >/dev/null 2>&1; then
  ok "mmdc (mermaid-cli): $(mmdc --version 2>&1 | head -1)"
else
  warn "mmdc not found — install via Brewfile (brew \"mermaid-cli\")"
fi

section "brew-autoupdate"
if command -v brew >/dev/null 2>&1 && command -v launchctl >/dev/null 2>&1 && command -v plutil >/dev/null 2>&1; then
  if brew_autoupdate_is_loaded || [[ -f "$(brew_autoupdate_plist_path)" ]]; then
    attention "brew autoupdate: enabled, but dotfiles policy is disabled — run: ./scripts/post-setup.sh"
  else
    ok "brew autoupdate: disabled by dotfiles policy"
  fi
else
  info "brew autoupdate audit skipped: brew/launchctl/plutil unavailable"
fi

section "AI Config"
audit_local_file "Claude settings" "${HOME}/.claude/settings.json"
audit_local_file "Shared Claude guidance" "${HOME}/.claude/CLAUDE.md"

if [[ -f "${HOME}/.claude/settings.json" ]]; then
  if [[ "$(ai_config_json_read "${HOME}/.claude/settings.json" "d.get('autoUpdatesChannel','')" 2>/dev/null || true)" == "latest" ]]; then
    ok "Claude settings: auto-update channel is latest"
  else
    attention "Claude settings: auto-update channel should be latest"
  fi
fi

echo
if [[ "${ATTENTION_COUNT}" -eq 0 ]]; then
  printf '\033[1;32mStatus looks good.\033[0m\n'
else
  printf '\033[1;33mAttention needed: %s item(s).\033[0m\n' "${ATTENTION_COUNT}"
  printf 'Run `make preview` or `make doctor` for deeper checks.\n'
fi
