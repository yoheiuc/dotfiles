#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-status-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

fake_repo="${tmpdir}/repo"
stub_bin="${tmpdir}/bin"
mkdir -p \
  "${fake_repo}/home" \
  "${fake_repo}/scripts" \
  "${stub_bin}" \
  "${tmpdir}/home/.config/dotfiles" \
  "${tmpdir}/home/.codex" \
  "${tmpdir}/home/.claude" \
  "${tmpdir}/home/.gemini"

cat > "${fake_repo}/home/dot_Brewfile.core" <<'EOF'
brew "git"
cask "ghostty"
EOF

cat > "${fake_repo}/home/dot_Brewfile.home" <<'EOF'
cask "bitwarden"
EOF

cp "${REPO_ROOT}/scripts/status.sh" "${fake_repo}/scripts/status.sh"
cp "${REPO_ROOT}/scripts/profile.sh" "${fake_repo}/scripts/profile.sh"

cat > "${fake_repo}/scripts/brew-bundle.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "check" ]]; then
  if [[ "${BREW_CHECK_MODE:-ok}" == "ok" ]]; then
    printf "The Brewfile's dependencies are satisfied.\n"
    exit 0
  fi

  printf "brew bundle check failed\n"
  exit 1
fi

printf "unsupported\n" >&2
exit 1
EOF

cat > "${stub_bin}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

if [[ "${1:-}" == "status" ]]; then
  printf '%b' "${GIT_STATUS_OUT:-## main...origin/main\n}"
  exit 0
fi

exit 1
EOF

cat > "${stub_bin}/chezmoi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  printf '%b' "${CHEZMOI_STATUS_OUT:-}"
  exit "${CHEZMOI_STATUS_CODE:-0}"
fi

exit 1
EOF

cat > "${stub_bin}/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list)
    case "${2:-}" in
      --formula)
        printf '%b' "${BREW_LIST_FORMULA:-}"
        ;;
      --cask)
        printf '%b' "${BREW_LIST_CASK:-}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x \
  "${fake_repo}/scripts/status.sh" \
  "${fake_repo}/scripts/profile.sh" \
  "${fake_repo}/scripts/brew-bundle.sh" \
  "${stub_bin}/git" \
  "${stub_bin}/chezmoi" \
  "${stub_bin}/brew"

export PATH="${stub_bin}:${PATH}"
export DOTFILES_REPO_ROOT="${fake_repo}"
export HOME="${tmpdir}/home"

printf 'home\n' > "${HOME}/.config/dotfiles/profile"
cat > "${HOME}/.codex/config.toml" <<'EOF'
model = "gpt-5.4"
EOF
: > "${HOME}/.claude/settings.json"
: > "${HOME}/.gemini/settings.json"
: > "${HOME}/.codex/hooks.json"
: > "${HOME}/.claude/CLAUDE.md"
: > "${HOME}/AGENTS.md"

run_capture env \
  GIT_STATUS_OUT=$'## main...origin/main\n' \
  CHEZMOI_STATUS_OUT='' \
  BREW_CHECK_MODE=ok \
  BREW_LIST_FORMULA=$'git\n' \
  BREW_LIST_CASK=$'ghostty\nbitwarden\n' \
  bash "${fake_repo}/scripts/status.sh"
assert_eq "0" "${RUN_STATUS}" "status should succeed in the clean case"
assert_contains "${RUN_OUTPUT}" "Active profile: home" "status should print the active profile"
assert_contains "${RUN_OUTPUT}" "working tree: clean" "status should report a clean worktree"
assert_contains "${RUN_OUTPUT}" "chezmoi managed files: clean" "status should report a clean chezmoi state"
assert_contains "${RUN_OUTPUT}" "home Brew profile: all declared packages present" "status should report Brew health"
assert_contains "${RUN_OUTPUT}" "Codex config: no legacy bridge settings detected" "status should audit Codex config"
assert_contains "${RUN_OUTPUT}" "Status looks good." "status should summarize a clean state"

cat > "${HOME}/.codex/config.toml" <<'EOF'
# --- BEGIN CCB ---
approval_policy = "never"
sandbox_mode = "danger-full-access"
EOF
rm -f "${HOME}/.gemini/settings.json"

run_capture env \
  GIT_STATUS_OUT=$'## main...origin/main\n M README.md\n' \
  CHEZMOI_STATUS_OUT=$'M ~/.zshrc\n' \
  BREW_CHECK_MODE=bad \
  BREW_LIST_FORMULA=$'git\n' \
  BREW_LIST_CASK=$'ghostty\n' \
  bash "${fake_repo}/scripts/status.sh"
assert_eq "0" "${RUN_STATUS}" "status should stay informational even with warnings"
assert_contains "${RUN_OUTPUT}" "working tree: local changes detected" "status should warn on dirty worktree"
assert_contains "${RUN_OUTPUT}" "chezmoi managed files: pending changes detected" "status should warn on chezmoi drift"
assert_contains "${RUN_OUTPUT}" "home Brew profile: missing packages or check failed" "status should warn on Brew failures"
assert_contains "${RUN_OUTPUT}" "Gemini settings: missing" "status should report missing local settings"
assert_contains "${RUN_OUTPUT}" "Codex config: legacy bridge/auto-approval settings detected" "status should detect legacy Codex settings"
assert_contains "${RUN_OUTPUT}" "Attention needed:" "status should summarize warnings"

pass_test "tests/status.sh"
