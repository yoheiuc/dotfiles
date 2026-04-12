#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-brew-tools-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

fake_repo="${tmpdir}/repo"
stub_bin="${tmpdir}/bin"
mkdir -p "${fake_repo}/home" "${fake_repo}/scripts" "${stub_bin}" "${tmpdir}/home/.config/dotfiles"

cat > "${fake_repo}/home/dot_Brewfile.core" <<'EOF'
brew "git"
cask "ghostty"
EOF

cat > "${fake_repo}/home/dot_Brewfile.home" <<'EOF'
cask "bitwarden"
EOF

cat > "${fake_repo}/scripts/profile.sh" <<'EOF'
#!/usr/bin/env bash
printf 'home\n'
EOF

cat > "${stub_bin}/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list)
    case "${2:-}" in
      --formula)
        [[ "${3:-}" == "jq" ]] && exit 0
        printf '%b' "${BREW_LIST_FORMULA:-}"
        ;;
      --cask)
        if [[ -n "${3:-}" ]]; then
          [[ "${3:-}" == "google-chrome" ]] && exit 0
          exit 1
        fi
        printf '%b' "${BREW_LIST_CASK:-}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  leaves)
    printf '%b' "${BREW_LEAVES:-}"
    ;;
  tap)
    printf '%b' "${BREW_TAPS:-}"
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "${fake_repo}/scripts/profile.sh" "${stub_bin}/brew"

export PATH="${stub_bin}:${PATH}"
export DOTFILES_REPO_ROOT="${fake_repo}"
export HOME="${tmpdir}/home"

run_capture bash "${REPO_ROOT}/scripts/brew-add.sh" core brew jq
assert_eq "0" "${RUN_STATUS}" "brew-add should succeed for a locally installed formula"
assert_contains "$(cat "${fake_repo}/home/dot_Brewfile.core")" 'brew "jq"' "brew-add should append the formula to the target Brewfile"

run_capture bash "${REPO_ROOT}/scripts/brew-add.sh" core brew jq
assert_eq "1" "${RUN_STATUS}" "brew-add should fail on duplicate entries"
assert_contains "${RUN_OUTPUT}" "already declared" "brew-add should explain duplicate entries"

run_capture env \
  BREW_LEAVES=$'git\njq\n' \
  BREW_LIST_CASK=$'ghostty\ngoogle-chrome\n' \
  bash "${REPO_ROOT}/scripts/brew-diff.sh" home
assert_eq "1" "${RUN_STATUS}" "brew-diff should return non-zero when tracking drift exists"
assert_contains "${RUN_OUTPUT}" "google-chrome" "brew-diff should report untracked local casks"
assert_contains "${RUN_OUTPUT}" "bitwarden" "brew-diff should report declared but missing casks"

run_capture env \
  BREW_LEAVES=$'git\njq\n' \
  BREW_LIST_CASK=$'ghostty\nbitwarden\n' \
  bash "${REPO_ROOT}/scripts/brew-diff.sh" home
assert_eq "0" "${RUN_STATUS}" "brew-diff should return zero when no tracking diff exists"
assert_contains "${RUN_OUTPUT}" "No Brew tracking diff." "brew-diff should report clean state"

pass_test "tests/brew-tools.sh"
