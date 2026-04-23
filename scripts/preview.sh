#!/usr/bin/env bash
# preview.sh — show what dotfiles would change without applying anything
#
# Usage:
#   ./scripts/preview.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
ok() { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }

echo
printf '\033[1m=== dotfiles preview ===\033[0m\n'

section "chezmoi diff"
diff_out="$(chezmoi diff 2>&1 || true)"
if [[ -z "${diff_out}" ]]; then
  ok "No pending chezmoi diff."
else
  printf '%s\n' "${diff_out}" | sed 's/^/    /'
fi

section "chezmoi apply --dry-run --verbose"
dry_run_out="$(chezmoi apply --dry-run --verbose --no-tty 2>&1 || true)"
if [[ -z "${dry_run_out}" ]]; then
  ok "Dry-run produced no output."
else
  printf '%s\n' "${dry_run_out}" | sed 's/^/    /'
fi

section "Homebrew bundle"
if ! bash "${REPO_ROOT}/scripts/brew-bundle.sh" preview; then
  warn "Brew preview reported an error."
  exit 1
fi
