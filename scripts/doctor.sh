#!/usr/bin/env bash
# doctor.sh — verify dotfiles setup health
# Usage: bash scripts/doctor.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ok()   { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
fail() { printf '  \033[1;31m✗\033[0m  %s\n' "$*"; FAILED=1; }

FAILED=0

echo
printf '\033[1m=== dotfiles doctor ===\033[0m\n\n'

# ---- Homebrew bundle ------------------------------------------------------
printf '[Homebrew]\n'
if command -v brew &>/dev/null; then
  if brew bundle check --file="${REPO_ROOT}/Brewfile" &>/dev/null; then
    ok "brew bundle: all packages present"
  else
    fail "brew bundle: missing packages — run: brew bundle --file=${REPO_ROOT}/Brewfile"
  fi
else
  fail "brew not found"
fi

# ---- chezmoi --------------------------------------------------------------
printf '\n[chezmoi]\n'
if command -v chezmoi &>/dev/null; then
  diff_out=$(chezmoi diff --source="${REPO_ROOT}/home" 2>&1 || true)
  if [[ -z "$diff_out" ]]; then
    ok "chezmoi diff: no pending changes"
  else
    warn "chezmoi diff: unapplied changes — preview below"
    chezmoi apply -n -v --source="${REPO_ROOT}/home" 2>&1 | head -40
  fi
else
  fail "chezmoi not found"
fi

# ---- Ghostty ---------------------------------------------------------------
printf '\n[Ghostty]\n'
if command -v ghostty &>/dev/null; then
  ghostty +show-config --default --docs 2>/dev/null | head -5 && ok "ghostty: config readable"
else
  warn "ghostty not in PATH (may be a .app install — that's fine)"
fi

# ---- Claude / Serena -------------------------------------------------------
printf '\n[Claude Code]\n'
if command -v claude &>/dev/null; then
  claude_ver=$(claude --version 2>&1 | head -1)
  ok "claude: ${claude_ver}"
  printf '  MCP servers:\n'
  claude mcp list 2>&1 | sed 's/^/    /'
else
  warn "claude not found — install via Brewfile (cask \"claude\")"
fi

# ---- Result ----------------------------------------------------------------
echo
if [[ "$FAILED" -eq 0 ]]; then
  printf '\033[1;32mAll checks passed.\033[0m\n\n'
else
  printf '\033[1;31mSome checks failed — see above.\033[0m\n\n'
  exit 1
fi
