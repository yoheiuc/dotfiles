#!/usr/bin/env bash
# status.sh — compact daily status for this dotfiles repo and local AI configs
#
# Usage:
#   ./scripts/status.sh
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ACTIVE_PROFILE="$(bash "${REPO_ROOT}/scripts/profile.sh" get)"
PROFILE_IS_EXPLICIT=0
if bash "${REPO_ROOT}/scripts/profile.sh" exists; then
  PROFILE_IS_EXPLICIT=1
fi

ATTENTION_COUNT=0

section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
ok() { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
info() { printf '  - %s\n' "$*"; }
attention() {
  warn "$*"
  ATTENTION_COUNT=$((ATTENTION_COUNT + 1))
}

extract_brewfile_entries() {
  local kind="$1"
  local file="$2"

  [[ -f "${file}" ]] || return 0

  case "${kind}" in
    formula)
      sed -nE 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' "${file}" | sort -u
      ;;
    cask)
      sed -nE 's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/p' "${file}" | sort -u
      ;;
    *)
      return 1
      ;;
  esac
}

forbidden_profile_entries() {
  local kind="$1"
  local home_entries

  [[ "${ACTIVE_PROFILE}" == "core" ]] || return 1

  home_entries="$(extract_brewfile_entries "${kind}" "${REPO_ROOT}/home/dot_Brewfile.home")"
  [[ -n "${home_entries}" ]] || return 1
  printf '%s\n' "${home_entries}" | sed '/^$/d' | sort -u
}

installed_brew_entries() {
  local kind="$1"

  case "${kind}" in
    formula)
      brew list --formula | sort -u
      ;;
    cask)
      brew list --cask | sort -u
      ;;
    *)
      return 1
      ;;
  esac
}

report_profile_drift() {
  local kind="$1"
  local label forbidden installed unexpected

  case "${kind}" in
    formula) label="formulae" ;;
    cask) label="casks" ;;
    *) return 1 ;;
  esac

  forbidden="$(forbidden_profile_entries "${kind}" || true)"
  [[ -n "${forbidden}" ]] || return 1

  installed="$(installed_brew_entries "${kind}" || true)"
  unexpected="$(comm -12 <(printf '%s\n' "${forbidden}" | sort -u) <(printf '%s\n' "${installed}" | sort -u))"

  [[ -n "${unexpected}" ]] || return 1

  attention "Brew profile drift: ${label} from 'home' are installed on a 'core' machine"
  printf '%s\n' "${unexpected}" | sed 's/^/    /'
  return 0
}

audit_local_file() {
  local label="$1"
  local path="$2"

  if [[ -f "${path}" ]]; then
    info "${label}: present (${path})"
  else
    info "${label}: missing (${path})"
  fi
}

echo
printf '\033[1m=== dotfiles status ===\033[0m\n'
printf 'Active profile: %s\n' "${ACTIVE_PROFILE}"
if [[ "${PROFILE_IS_EXPLICIT}" -ne 1 ]]; then
  warn "No persisted machine profile yet; defaulting to 'core'."
fi

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
brew_check_out="$(bash "${REPO_ROOT}/scripts/brew-bundle.sh" check "${ACTIVE_PROFILE}" 2>&1)"
brew_check_code=$?
set -e

if printf '%s\n' "${brew_check_out}" | grep -q "The Brewfile's dependencies are satisfied."; then
  ok "${ACTIVE_PROFILE} Brew profile: all declared packages present"
else
  attention "${ACTIVE_PROFILE} Brew profile: missing packages or check failed"
  printf '%s\n' "${brew_check_out}" | grep -v '^Using ' | sed 's/^/    /' || true
fi

if [[ "${PROFILE_IS_EXPLICIT}" -ne 1 ]]; then
  warn "Brew profile drift: skipped until a machine profile is explicitly saved"
else
  drift_found=0
  if command -v brew >/dev/null 2>&1; then
    if report_profile_drift formula; then
      drift_found=1
    fi
    if report_profile_drift cask; then
      drift_found=1
    fi
    if [[ "${drift_found}" -eq 0 ]]; then
      ok "Brew profile drift: none"
    fi
  else
    attention "brew not found"
  fi
  unset drift_found
fi

unset brew_check_code

section "AI Config"
audit_local_file "Codex config" "${HOME}/.codex/config.toml"
audit_local_file "Claude settings" "${HOME}/.claude/settings.json"
audit_local_file "Gemini settings" "${HOME}/.gemini/settings.json"
audit_local_file "Shared Codex hooks" "${HOME}/.codex/hooks.json"
audit_local_file "Shared Claude guidance" "${HOME}/.claude/CLAUDE.md"
audit_local_file "Shared AGENTS" "${HOME}/AGENTS.md"

if [[ -f "${HOME}/.codex/config.toml" ]]; then
  if grep -Eq 'approval_policy[[:space:]]*=[[:space:]]*"never"|sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"|BEGIN CCB|END CCB|ai-bridge|cc-bridge' "${HOME}/.codex/config.toml"; then
    attention "Codex config: legacy bridge/auto-approval settings detected"
  else
    ok "Codex config: no legacy bridge settings detected"
  fi
else
  info "Codex config audit skipped: file is missing"
fi

echo
if [[ "${ATTENTION_COUNT}" -eq 0 ]]; then
  printf '\033[1;32mStatus looks good.\033[0m\n'
else
  printf '\033[1;33mAttention needed: %s item(s).\033[0m\n' "${ATTENTION_COUNT}"
  printf 'Run `make preview` or `make doctor` for deeper checks.\n'
fi
