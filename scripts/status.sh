#!/usr/bin/env bash
# status.sh — compact daily status for this dotfiles repo and local AI configs
#
# Usage:
#   ./scripts/status.sh
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"
source "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh"
source "${REPO_ROOT}/scripts/lib/brew-profile.sh"

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

report_profile_drift() {
  local kind="$1"
  local label unexpected

  case "${kind}" in
    formula) label="formulae" ;;
    cask) label="casks" ;;
    *) return 1 ;;
  esac

  unexpected="$(brew_profile_drift_entries "${ACTIVE_PROFILE}" "${REPO_ROOT}" "${kind}" || true)"
  [[ -n "${unexpected}" ]] || return 1

  attention "Brew profile drift: ${label} from 'home' are installed on a 'core' machine"
  printf '%s\n' "${unexpected}" | sed 's/^/    /'
  return 0
}

audit_local_file() {
  local label="$1"
  local path="$2"

  info "$(ai_config_describe_file "${label}" "${path}")"
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
audit_local_file "Codex config" "${HOME}/.codex/config.toml"
audit_local_file "Claude settings" "${HOME}/.claude/settings.json"
audit_local_file "Gemini settings" "${HOME}/.gemini/settings.json"
audit_local_file "Serena config" "${HOME}/.serena/serena_config.yml"
audit_local_file "Shared Codex hooks" "${HOME}/.codex/hooks.json"
audit_local_file "Shared Claude guidance" "${HOME}/.claude/CLAUDE.md"
audit_local_file "Shared AGENTS" "${HOME}/AGENTS.md"

if [[ -f "${HOME}/.codex/config.toml" ]]; then
  if ai_config_has_legacy_settings "${HOME}/.codex/config.toml"; then
    attention "Codex config: legacy bridge/auto-approval settings detected"
  else
    ok "Codex config: no legacy bridge settings detected"
  fi

  if [[ "$(ai_config_toml_read "${HOME}/.codex/config.toml" "d.get('sandbox_mode','')" 2>/dev/null || true)" == "workspace-write" ]]; then
    ok "Codex config: sandbox mode is workspace-write"
  else
    attention "Codex config: sandbox mode should be workspace-write"
  fi

  if [[ "$(ai_config_toml_read "${HOME}/.codex/config.toml" "d.get('approval_policy','')" 2>/dev/null || true)" == "on-request" ]]; then
    ok "Codex config: approval policy is on-request"
  else
    attention "Codex config: approval policy should be on-request"
  fi

  case "$(ai_config_codex_mcp_url_state "${HOME}/.codex/config.toml" openaiDeveloperDocs "https://developers.openai.com/mcp")" in
    ok)
      ok "Codex OpenAI Docs MCP: registered"
      ;;
    wrong-url|missing)
      attention "Codex OpenAI Docs MCP: missing or wrong URL"
      ;;
  esac
else
  info "Codex config audit skipped: file is missing"
fi

if [[ -f "${HOME}/.claude/settings.json" ]]; then
  if [[ "$(ai_config_json_read "${HOME}/.claude/settings.json" "d.get('autoUpdatesChannel','')" 2>/dev/null || true)" == "latest" ]]; then
    ok "Claude settings: auto-update channel is latest"
  else
    attention "Claude settings: auto-update channel should be latest"
  fi
fi

if [[ -f "${HOME}/.serena/serena_config.yml" ]]; then
  serena_config_attention=0
  if ! ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^language_backend:[[:space:]]*LSP([[:space:]]|$)'; then
    serena_config_attention=1
  fi
  if ! ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^web_dashboard:[[:space:]]*true([[:space:]]|$)'; then
    serena_config_attention=1
  fi
  if ! ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^web_dashboard_open_on_launch:[[:space:]]*false([[:space:]]|$)'; then
    serena_config_attention=1
  fi
  if ! ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^project_serena_folder_location:[[:space:]]*"\$projectDir/\.serena"([[:space:]]|$)'; then
    serena_config_attention=1
  fi

  if [[ "${serena_config_attention}" == "0" ]]; then
    ok "Serena config: expected defaults detected"
  else
    attention "Serena config: expected defaults drifted"
  fi
  unset serena_config_attention
else
  attention "Serena config: missing"
fi

echo
if [[ "${ATTENTION_COUNT}" -eq 0 ]]; then
  printf '\033[1;32mStatus looks good.\033[0m\n'
else
  printf '\033[1;33mAttention needed: %s item(s).\033[0m\n' "${ATTENTION_COUNT}"
  printf 'Run `make preview` or `make doctor` for deeper checks.\n'
fi
