#!/usr/bin/env bash
# tests/uninstall.sh — verify scripts/uninstall.sh happy path + idempotency.
#
# Strategy: stub chezmoi, brew, read (via here-string) and verify that running
# uninstall.sh twice in a row does not error. The second run takes the "already
# gone" paths (chezmoi absent, symlink absent, brew list fails).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-uninstall-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

export HOME="${tmpdir}/home"
mkdir -p "${HOME}/.local/share"
ln -s "${REPO_ROOT}" "${HOME}/.local/share/chezmoi"

stub_bin="${tmpdir}/bin"
mkdir -p "${stub_bin}"

# State flags for stubs.
export STUB_STATE_DIR="${tmpdir}/state"
mkdir -p "${STUB_STATE_DIR}"
: > "${STUB_STATE_DIR}/chezmoi-present"
: > "${STUB_STATE_DIR}/brew-has-chezmoi"

cat > "${stub_bin}/chezmoi" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  purge)
    # Simulate interactive --binary form first, then plain form.
    if [[ "${2:-}" == "--binary" ]]; then
      exit 1
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${stub_bin}/chezmoi"

cat > "${stub_bin}/brew" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  list)
    # First call succeeds (chezmoi installed); after uninstall, fail.
    if [[ "${2:-}" == "chezmoi" && -f "${STUB_STATE_DIR}/brew-has-chezmoi" ]]; then
      exit 0
    fi
    exit 1
    ;;
  uninstall)
    rm -f "${STUB_STATE_DIR}/brew-has-chezmoi"
    exit 0
    ;;
  bundle)
    # `brew bundle cleanup --file=... --force` during Homebrew-cleanup path.
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${stub_bin}/brew"

# Pin PATH so the real chezmoi / brew on the developer machine cannot shadow
# the stubs. `command -v` only walks PATH, so starving the real binaries is
# enough.
export PATH="${stub_bin}:/usr/bin:/bin:/usr/sbin:/sbin"

# ---- Run 1: fresh uninstall (user accepts both prompts) --------------------
# Two `read -r` calls in the script: (1) press-enter confirmation, (2) remove brew packages y/N.
# Feed \n\nN to decline brew package removal (simpler — avoids brew bundle cleanup assertions).
run_capture bash -c 'printf "\nN\n" | env PATH="'"${PATH}"'" STUB_STATE_DIR="'"${STUB_STATE_DIR}"'" bash "$1"' _ "${REPO_ROOT}/scripts/uninstall.sh"
assert_eq "0" "${RUN_STATUS}" "uninstall should succeed on first run"
assert_contains "${RUN_OUTPUT}" "Uninstall complete." "first run should print completion banner"
assert_contains "${RUN_OUTPUT}" "Removing chezmoi-managed dotfiles" "first run should purge chezmoi"
assert_contains "${RUN_OUTPUT}" "Uninstalling chezmoi" "first run should uninstall brew chezmoi"
assert_contains "${RUN_OUTPUT}" "Skipping Homebrew package removal." "first run should respect N response"

# After run 1, state should be: no chezmoi symlink, brew no longer knows chezmoi.
if [[ -L "${HOME}/.local/share/chezmoi" ]]; then
  fail_test "chezmoi symlink should be removed after first run"
fi

# ---- Run 2: idempotency (everything already gone) --------------------------
# Remove the chezmoi stub so that `command -v chezmoi` fails (simulates brew
# uninstall having removed it). The script must still finish cleanly.
rm -f "${stub_bin}/chezmoi"

run_capture bash -c 'printf "\nN\n" | env PATH="'"${PATH}"'" STUB_STATE_DIR="'"${STUB_STATE_DIR}"'" bash "$1"' _ "${REPO_ROOT}/scripts/uninstall.sh"
assert_eq "0" "${RUN_STATUS}" "uninstall should be idempotent (second run succeeds)"
assert_contains "${RUN_OUTPUT}" "Uninstall complete." "second run should still complete"
assert_contains "${RUN_OUTPUT}" "chezmoi not found" "second run should warn chezmoi missing rather than error"

pass_test "tests/uninstall.sh"
