#!/usr/bin/env bash
# doctor.sh — verify dotfiles setup health
#
# Exit code: 0 = all required checks passed, 1 = at least one required check failed
# Optional (warn-only) items never affect the exit code.
#
# Usage: bash scripts/doctor.sh
set -euo pipefail

ok()      { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn()    { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
fail()    { printf '  \033[1;31m✗\033[0m  %s\n' "$*"; REQUIRED_FAILED=1; }
section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }

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
  chezmoi doctor 2>&1 | sed 's/^/    /'

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

section "Brewfile packages (required)"
if brew bundle check --global &>/dev/null; then
  ok "brew bundle --global: all packages present"
else
  fail "brew bundle: missing packages — run: brew bundle --global"
  brew bundle check --global 2>&1 | grep -v '^Using ' | sed 's/^/    /' || true
fi

# ===========================================================================
# OPTIONAL checks — warn only, never fail the script
# ===========================================================================

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
  ok "ghostty $("$_ghostty" --version 2>&1 | head -1)"
else
  warn "ghostty not found in PATH or /Applications — install via Brewfile (cask \"ghostty\")"
fi
unset _ghostty

section "Claude Code (optional)"
if command -v claude &>/dev/null; then
  ok "$(claude --version 2>&1 | head -1)"
  printf '  MCP servers registered:\n'
  claude mcp list 2>&1 | sed 's/^/    /'
  # Check Serena specifically
  if claude mcp list 2>/dev/null | grep -q '^serena'; then
    ok "serena MCP: registered"
  else
    warn "serena MCP: not registered — run: bash scripts/post-setup.sh"
  fi
else
  warn "claude not found — install via Brewfile (cask \"claude\")"
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
