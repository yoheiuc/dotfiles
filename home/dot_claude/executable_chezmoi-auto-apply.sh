#!/usr/bin/env bash
# Claude Code Stop hook — auto-apply chezmoi when the source tree under
# ~/dotfiles has pending changes.
#
# Triggers only when the assistant's workspace is the dotfiles repo, so
# editing files elsewhere does not pay any cost. Exits silently when there
# is nothing to apply (the common case after a no-op turn).
set -euo pipefail

DOTFILES_REPO="${HOME}/dotfiles"

# Always drain stdin so Claude Code's hook pipe does not stall, but defer the
# `jq` parse until after the cheap PWD pre-check. Most assistant turns happen
# outside ~/dotfiles and this saves one subprocess per fired hook.
INPUT="$(cat || true)"

case "${PWD}" in
  "${DOTFILES_REPO}"|"${DOTFILES_REPO}"/*)
    WORKSPACE="${PWD}"
    ;;
  *)
    # PWD is outside the repo, but Claude Code may still be reporting a
    # dotfiles workspace via the hook payload — fall back to jq once.
    if ! command -v jq >/dev/null 2>&1; then
      exit 0
    fi
    WORKSPACE="$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null || true)"
    case "${WORKSPACE}" in
      "${DOTFILES_REPO}"|"${DOTFILES_REPO}"/*) ;;
      *) exit 0 ;;
    esac
    ;;
esac

command -v chezmoi >/dev/null 2>&1 || exit 0

# `chezmoi diff` prints nothing when source and dest are in sync. Skip the
# heavier `apply` call on the no-diff path so the hook stays cheap on the
# common turn where no chezmoi-managed file changed.
if ! chezmoi diff --no-pager 2>/dev/null | grep -q .; then
  exit 0
fi

if chezmoi apply 2>/dev/null; then
  printf 'chezmoi-auto-apply: synced source -> dest\n' >&2
else
  printf 'chezmoi-auto-apply: apply failed (run chezmoi apply -v to inspect)\n' >&2
fi
