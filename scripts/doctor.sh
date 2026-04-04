#!/usr/bin/env bash
# doctor.sh — verify dotfiles setup health
#
# Exit code: 0 = all required checks passed, 1 = at least one required check failed
# Optional (warn-only) items never affect the exit code.
#
# Usage: ./scripts/doctor.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTIVE_PROFILE="$(bash "${REPO_ROOT}/scripts/profile.sh" get)"
PROFILE_IS_EXPLICIT=0
if bash "${REPO_ROOT}/scripts/profile.sh" exists; then
  PROFILE_IS_EXPLICIT=1
fi

ok()      { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn()    { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
fail()    { printf '  \033[1;31m✗\033[0m  %s\n' "$*"; REQUIRED_FAILED=1; }
section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
strip_codex_path_warning() { sed '/^WARNING: proceeding, even though we could not update PATH:/d'; }
extract_brewfile_entries() {
  local kind="$1"
  local file="$2"

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
  local work_entries home_entries

  work_entries="$(extract_brewfile_entries "${kind}" "${REPO_ROOT}/home/dot_Brewfile.work")"
  home_entries="$(extract_brewfile_entries "${kind}" "${REPO_ROOT}/home/dot_Brewfile.home")"

  case "${ACTIVE_PROFILE}" in
    core)
      printf '%s\n%s\n' "${work_entries}" "${home_entries}" | sed '/^$/d' | sort -u
      ;;
    work)
      comm -23 <(printf '%s\n' "${home_entries}" | sed '/^$/d' | sort -u) <(printf '%s\n' "${work_entries}" | sed '/^$/d' | sort -u)
      ;;
    home)
      comm -23 <(printf '%s\n' "${work_entries}" | sed '/^$/d' | sort -u) <(printf '%s\n' "${home_entries}" | sed '/^$/d' | sort -u)
      ;;
    *)
      return 1
      ;;
  esac
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

  forbidden="$(forbidden_profile_entries "${kind}")"
  [[ -n "${forbidden}" ]] || return 0

  installed="$(installed_brew_entries "${kind}")"
  unexpected="$(comm -12 <(printf '%s\n' "${forbidden}" | sort -u) <(printf '%s\n' "${installed}" | sort -u))"

  if [[ -n "${unexpected}" ]]; then
    warn "Brew profile drift: ${label} installed outside '${ACTIVE_PROFILE}' profile"
    printf '%s\n' "${unexpected}" | sed 's/^/    /'
    warn "  Preview cleanup with: ./scripts/brew-bundle.sh preview ${ACTIVE_PROFILE}"
    return 0
  fi

  return 1
}
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout = float(sys.argv[1])
cmd = sys.argv[2:]

def write_maybe_bytes(stream, value):
    if value is None:
        return
    if isinstance(value, bytes):
        stream.write(value.decode("utf-8", errors="replace"))
    else:
        stream.write(value)

try:
    completed = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
except subprocess.TimeoutExpired as exc:
    write_maybe_bytes(sys.stdout, exc.stdout)
    write_maybe_bytes(sys.stderr, exc.stderr)
    sys.stderr.write(f"Timed out after {timeout:g}s\n")
    raise SystemExit(124)

write_maybe_bytes(sys.stdout, completed.stdout)
write_maybe_bytes(sys.stderr, completed.stderr)
raise SystemExit(completed.returncode)
PY
}

REQUIRED_FAILED=0

echo
printf '\033[1m=== dotfiles doctor ===\033[0m\n'
printf 'Active profile: %s\n' "${ACTIVE_PROFILE}"
if [[ "${PROFILE_IS_EXPLICIT}" -ne 1 ]]; then
  warn "No persisted machine profile yet; defaulting to 'core'"
fi

# ===========================================================================
# REQUIRED checks — failures increment REQUIRED_FAILED and affect exit code
# ===========================================================================

section "Homebrew (required)"
if brew --version &>/dev/null; then
  ok "brew $(brew --version | head -1)"
else
  fail "brew not found — install from https://brew.sh"
fi

section "chezmoi (required)"
if chezmoi --version &>/dev/null; then
  ok "$(chezmoi --version)"

  # chezmoi doctor — runs built-in self-checks (gpg, age, diff tool, etc.)
  printf '  chezmoi doctor:\n'
  chezmoi_doctor_out="$(chezmoi doctor 2>&1 || true)"
  printf '%s\n' "$chezmoi_doctor_out" | sed 's/^/    /'
  if printf '%s\n' "$chezmoi_doctor_out" | grep -Ev '^[[:space:]]*failed[[:space:]]+latest-version[[:space:]]' | grep -Eq '^[[:space:]]*failed[[:space:]]'; then
    warn "chezmoi doctor: reported failed checks above"
  fi

  # Pending diff (warn only — user may intentionally defer apply)
  diff_out=$(chezmoi diff 2>&1 || true)
  if [[ -z "$diff_out" ]]; then
    ok "chezmoi diff: clean (no pending changes)"
  else
    warn "chezmoi diff: unapplied changes detected"
    warn "  Preview: chezmoi apply -n -v"
  fi
else
  fail "chezmoi not found — run: brew install chezmoi"
fi

section "Active Brew profile (required)"
brew_check_out="$(bash "${REPO_ROOT}/scripts/brew-bundle.sh" check "${ACTIVE_PROFILE}" 2>&1 || true)"
if printf '%s\n' "$brew_check_out" | grep -q "The Brewfile's dependencies are satisfied."; then
  ok "${ACTIVE_PROFILE} Brew profile: all packages present"
else
  fail "${ACTIVE_PROFILE} Brew profile: missing packages — run: ./scripts/brew-bundle.sh sync ${ACTIVE_PROFILE}"
  printf '%s\n' "$brew_check_out" | grep -v '^Using ' | sed 's/^/    /' || true
fi

section "Brew profile drift (optional)"
if [[ "${PROFILE_IS_EXPLICIT}" -ne 1 ]]; then
  warn "skipped until a machine profile is explicitly saved"
else
  drift_found=0
  if report_profile_drift formula; then
    drift_found=1
  fi
  if report_profile_drift cask; then
    drift_found=1
  fi
  if [[ "${drift_found}" -eq 0 ]]; then
    ok "No work/home-only Brew packages are installed outside '${ACTIVE_PROFILE}' profile"
  fi
  unset drift_found
fi

section "Git identity/privacy (required)"
expected_git_name="yoheiuc"
expected_git_email="16657439+yoheiuc@users.noreply.github.com"
expected_hooks_path="${HOME}/.config/git/hooks"

git_name="$(git config --global --get user.name || true)"
git_email="$(git config --global --get user.email || true)"
git_hooks_path="$(git config --global --path --get core.hooksPath || true)"

if [[ "${git_name}" == "${expected_git_name}" ]]; then
  ok "git user.name: ${git_name}"
else
  fail "git user.name mismatch — expected '${expected_git_name}', got '${git_name:-<unset>}'"
fi

if [[ "${git_email}" == "${expected_git_email}" ]]; then
  ok "git user.email: ${git_email}"
else
  fail "git user.email mismatch — expected '${expected_git_email}', got '${git_email:-<unset>}'"
fi

if [[ "${git_hooks_path}" == "${expected_hooks_path}" ]]; then
  ok "git hooksPath: ${git_hooks_path}"
else
  fail "git hooksPath mismatch — expected '${expected_hooks_path}', got '${git_hooks_path:-<unset>}'"
fi

if [[ -x "${expected_hooks_path}/pre-commit" ]]; then
  ok "git pre-commit hook: present"
else
  fail "git pre-commit hook missing — run: chezmoi apply"
fi

# ===========================================================================
# OPTIONAL checks — warn only, never fail the script
# ===========================================================================

section "node (optional)"
if node --version &>/dev/null; then
  ok "node $(node --version)"
else
  warn "node not found — needed for Codex CLI installs via npm"
fi

section "uv (optional)"
if uv --version &>/dev/null; then
  ok "$(uv --version)"
else
  warn "uv not found — needed for Serena MCP (uvx)"
fi

section "Ghostty (optional)"
# Ghostty CLI may not be in PATH when installed as a .app bundle.
# /Applications/Ghostty.app/Contents/MacOS/ghostty is the binary path.
_ghostty=""
if command -v ghostty &>/dev/null; then
  _ghostty="ghostty"
elif [[ -x "/Applications/Ghostty.app/Contents/MacOS/ghostty" ]]; then
  _ghostty="/Applications/Ghostty.app/Contents/MacOS/ghostty"
fi

if [[ -n "$_ghostty" ]]; then
  if ghostty_version_out="$("$_ghostty" --version 2>&1)"; then
    ghostty_version_line="$(printf '%s\n' "$ghostty_version_out" | grep '^Ghostty' | head -1 || true)"
    if [[ -n "$ghostty_version_line" ]]; then
      ok "ghostty ${ghostty_version_line}"
    else
      warn "ghostty CLI returned unexpected output"
      warn "  $(printf '%s\n' "$ghostty_version_out" | head -1)"
    fi
  else
    warn "ghostty CLI found but --version failed"
    warn "  $(printf '%s\n' "$ghostty_version_out" | head -1)"
  fi
else
  warn "ghostty not found in PATH or /Applications — install via Brewfile (cask \"ghostty\")"
fi
unset _ghostty


section "zellij (optional)"
if zellij --version &>/dev/null; then
  ok "$(zellij --version 2>&1 | head -1)"
else
  warn "zellij not found — install via Brewfile (brew 'zellij')"
fi

section "ghq (optional)"
if ghq --version &>/dev/null; then
  ok "$(ghq --version 2>&1 | head -1)"
else
  warn "ghq not found — install via Brewfile (brew \"ghq\")"
fi

section "navi (optional)"
if command -v navi &>/dev/null; then
  ok "$(navi --version 2>&1 | head -1)"
  _navi_cheats="${HOME}/.local/share/navi/cheats/dotfiles"
  if [[ -d "$_navi_cheats" ]]; then
    _navi_cheat_count="$(find "${_navi_cheats}" -maxdepth 1 -type f -name '*.cheat' | wc -l | tr -d ' ')"
  else
    _navi_cheat_count="0"
  fi
  if [[ "${_navi_cheat_count}" != "0" ]]; then
    ok "navi cheatsheets: present (${_navi_cheat_count} files)"
  else
    warn "navi cheatsheets not found — run: chezmoi apply"
  fi
  unset _navi_cheats _navi_cheat_count
else
  warn "navi not found — install via Brewfile (brew \"navi\")"
fi

section "Claude Code (optional)"
if command -v claude &>/dev/null; then
  ok "$(claude --version 2>&1 | head -1)"
  printf '  MCP servers registered (timeout: 8s):\n'
  claude_mcp_list_out="$(run_with_timeout 8 claude mcp list 2>&1 || true)"
  printf '%s\n' "$claude_mcp_list_out" | sed 's/^/    /'
  if printf '%s\n' "$claude_mcp_list_out" | grep -q '^serena:'; then
    ok "serena MCP: registered"
  elif printf '%s\n' "$claude_mcp_list_out" | grep -q '^Timed out after '; then
    warn "serena MCP: check timed out"
  else
    warn "serena MCP: not registered — run: ./scripts/post-setup.sh"
  fi
else
  warn "claude not found — install via Brewfile (cask \"claude-code\")"
fi

section "Gemini CLI (optional)"
if command -v gemini &>/dev/null; then
  gemini_version_out="$(run_with_timeout 5 gemini --version 2>&1 || true)"
  gemini_version_line="$(printf '%s\n' "$gemini_version_out" | head -1)"
  if printf '%s\n' "$gemini_version_out" | grep -q '^Timed out after '; then
    warn "gemini found but --version timed out"
  elif [[ -n "$gemini_version_line" ]]; then
    ok "$gemini_version_line"
  else
    warn "gemini found but --version returned no usable output"
  fi
else
  warn "gemini not found — install via Brewfile (brew \"gemini-cli\")"
fi

section "Codex (optional)"
if command -v codex &>/dev/null; then
  codex_version_line="$(codex --version 2>&1 | strip_codex_path_warning | head -1)"
  if [[ -n "$codex_version_line" ]]; then
    ok "$codex_version_line"
  else
    warn "codex found but --version returned no usable output"
  fi

  printf '  MCP servers registered (timeout: 8s):\n'
  codex_mcp_list_out="$(run_with_timeout 8 codex mcp list 2>&1 | strip_codex_path_warning || true)"
  printf '%s\n' "$codex_mcp_list_out" | sed 's/^/    /'
  if printf '%s\n' "$codex_mcp_list_out" | grep -q '^serena[[:space:]]'; then
    ok "serena MCP: registered"
  elif printf '%s\n' "$codex_mcp_list_out" | grep -q '^Timed out after '; then
    warn "serena MCP: check timed out"
  else
    warn "serena MCP: not registered for Codex — run: ./scripts/post-setup.sh"
  fi

  if rg -q '^[[:space:]]*codex_hooks[[:space:]]*=[[:space:]]*true' "${HOME}/.codex/config.toml" 2>/dev/null; then
    ok "codex hooks: enabled"
  else
    warn "codex hooks: disabled — set [features].codex_hooks = true"
  fi

  if [[ -f "${HOME}/.codex/hooks.json" ]]; then
    ok "codex hooks.json: present"
  else
    warn "codex hooks.json missing — run: chezmoi apply"
  fi

  if [[ -f "${HOME}/.codex/skills/codex-auto-save-memory/scripts/autosave_memory.py" ]]; then
    ok "codex auto-save memory skill: present"
  else
    warn "codex auto-save memory skill missing — run: chezmoi apply"
  fi
else
  warn "codex not found — install Codex CLI separately"
fi

# ===========================================================================
# Result
# ===========================================================================

echo
if [[ "$REQUIRED_FAILED" -eq 0 ]]; then
  printf '\033[1;32mAll required checks passed.\033[0m\n\n'
else
  printf '\033[1;31m%d required check(s) failed — see above.\033[0m\n\n' "$REQUIRED_FAILED"
  exit 1
fi
