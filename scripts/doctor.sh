#!/usr/bin/env bash
# doctor.sh — verify dotfiles setup health
#
# Exit code: 0 = all required checks passed, 1 = at least one required check failed
# Optional (warn-only) items never affect the exit code.
#
# Usage: ./scripts/doctor.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ok()      { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn()    { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
fail()    { printf '  \033[1;31m✗\033[0m  %s\n' "$*"; REQUIRED_FAILED=1; }
section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
strip_codex_path_warning() { sed '/^WARNING: proceeding, even though we could not update PATH:/d'; }

REQUIRED_FAILED=0

echo
printf '\033[1m=== dotfiles doctor ===\033[0m\n'

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
  if printf '%s\n' "$chezmoi_doctor_out" | grep -Eq '^[[:space:]]*failed[[:space:]]'; then
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

section "Core Brew profile (required)"
if bash "${REPO_ROOT}/scripts/brew-bundle.sh" check core &>/dev/null; then
  ok "core Brew profile: all packages present"
else
  fail "core Brew profile: missing packages — run: ./scripts/brew-bundle.sh sync core"
  bash "${REPO_ROOT}/scripts/brew-bundle.sh" check core 2>&1 | grep -v '^Using ' | sed 's/^/    /' || true
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
    ghostty_version_line="$(printf '%s\n' "$ghostty_version_out" | head -1)"
    if [[ "$ghostty_version_line" == Ghostty* ]]; then
      ok "ghostty ${ghostty_version_line}"
    else
      warn "ghostty CLI returned unexpected output"
      warn "  ${ghostty_version_line}"
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
  if [[ -d "$_navi_cheats" ]] && ls "${_navi_cheats}"/*.cheat &>/dev/null 2>&1; then
    ok "navi cheatsheets: present ($(ls "${_navi_cheats}"/*.cheat | wc -l | tr -d ' ') files)"
  else
    warn "navi cheatsheets not found — run: chezmoi apply"
  fi
  unset _navi_cheats
else
  warn "navi not found — install via Brewfile (brew \"navi\")"
fi

section "Claude Code (optional)"
if command -v claude &>/dev/null; then
  ok "$(claude --version 2>&1 | head -1)"
  printf '  MCP servers registered:\n'
  claude mcp list 2>&1 | sed 's/^/    /'
  # Check Serena specifically
  if claude mcp list 2>/dev/null | grep -q '^serena'; then
    ok "serena MCP: registered"
  else
    warn "serena MCP: not registered — run: ./scripts/post-setup.sh"
  fi
else
  warn "claude not found — install via Brewfile (cask \"claude\")"
fi

section "Codex (optional)"
if command -v codex &>/dev/null; then
  codex_version_line="$(codex --version 2>&1 | strip_codex_path_warning | head -1)"
  if [[ -n "$codex_version_line" ]]; then
    ok "$codex_version_line"
  else
    warn "codex found but --version returned no usable output"
  fi

  printf '  MCP servers registered:\n'
  codex_mcp_list_out="$(codex mcp list 2>&1 | strip_codex_path_warning || true)"
  printf '%s\n' "$codex_mcp_list_out" | sed 's/^/    /'
  if codex mcp get serena --json >/dev/null 2>&1; then
    ok "serena MCP: registered"
  else
    warn "serena MCP: not registered for Codex — run: ./scripts/post-setup.sh"
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
