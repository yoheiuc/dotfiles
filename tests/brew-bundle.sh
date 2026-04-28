#!/usr/bin/env bash
# tests/brew-bundle.sh — verify scripts/brew-bundle.sh dispatches to brew bundle
# correctly across modes (sync / install / check / preview), errors out on
# unknown modes, and guards on missing Brewfile / missing brew binary.
#
# brew-bundle.sh is the single entry point used by `make sync`, `make install`,
# `make doctor`, and `make preview`. Stubbing brew lets us assert the exact
# subcommand + flags brew-bundle.sh emits for each mode without touching the
# user's real Homebrew install.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-brew-bundle-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

stub_bin="${tmpdir}/bin"
mkdir -p "${stub_bin}"
invocations="${tmpdir}/invocations.log"
: > "${invocations}"

# brew stub: records every invocation, exits with $BREW_*_STATUS env vars,
# prints $BREW_*_OUTPUT when set. Each subcommand gets its own pair of env
# vars so a single test scenario can drive different exit codes for
# `bundle check` vs `bundle cleanup` (preview mode exercises both).
cat > "${stub_bin}/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >> "${BREW_INVOCATIONS}"

case "${1:-}" in
  bundle)
    shift
    case "${1:-}" in
      check)
        if [[ -n "${BREW_CHECK_OUTPUT:-}" ]]; then
          printf '%s\n' "${BREW_CHECK_OUTPUT}"
        fi
        exit "${BREW_CHECK_STATUS:-0}"
        ;;
      cleanup)
        if [[ -n "${BREW_CLEANUP_OUTPUT:-}" ]]; then
          printf '%s\n' "${BREW_CLEANUP_OUTPUT}"
        fi
        exit "${BREW_CLEANUP_STATUS:-0}"
        ;;
      *)
        # plain `brew bundle --file=...` (install path)
        exit "${BREW_BUNDLE_STATUS:-0}"
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${stub_bin}/brew"

# Hermetic env. Stubs go first in PATH so brew-bundle.sh finds the stub
# instead of any real brew on the developer's machine. BREW_INVOCATIONS
# tells the stub where to log calls — appended to the base array because
# every scenario uses the same log path.
hermetic_base_env_init "${stub_bin}:/usr/bin:/bin:/usr/sbin:/sbin"
HERMETIC_BASE_ENV+=(BREW_INVOCATIONS="${invocations}")

reset_invocations() { : > "${invocations}"; }

# ---- Scenario 1: check mode (read-only) ----
# brew-bundle.sh requires the Brewfile at REPO_ROOT/home/dot_Brewfile to exist;
# the real one already does, so we don't plant a fixture (we only assert on
# brew invocations, not on the Brewfile contents).
reset_invocations
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/brew-bundle.sh" check
assert_eq "0" "${RUN_STATUS}" "brew-bundle check should succeed when brew stub returns 0"
assert_contains "$(cat "${invocations}")" \
  "brew bundle check --file=${REPO_ROOT}/home/dot_Brewfile --verbose --no-upgrade" \
  "check mode should call brew bundle check with --verbose --no-upgrade"
assert_not_contains "$(cat "${invocations}")" \
  "cleanup" \
  "check mode must not call cleanup"

# ---- Scenario 2: install mode (no cleanup) ----
reset_invocations
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/brew-bundle.sh" install
assert_eq "0" "${RUN_STATUS}" "brew-bundle install should succeed"
assert_contains "${RUN_OUTPUT}" "Installing packages from Brewfile (no cleanup)" \
  "install mode should announce its no-cleanup intent"
assert_contains "$(cat "${invocations}")" \
  "brew bundle --file=${REPO_ROOT}/home/dot_Brewfile" \
  "install mode should call brew bundle --file=…"
assert_not_contains "$(cat "${invocations}")" \
  "cleanup" \
  "install mode must not call cleanup"

# ---- Scenario 3: sync mode (install + cleanup --force) ----
reset_invocations
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/brew-bundle.sh" sync
assert_eq "0" "${RUN_STATUS}" "brew-bundle sync should succeed"
assert_contains "${RUN_OUTPUT}" "Removing packages not declared in Brewfile" \
  "sync mode should announce cleanup phase"
assert_contains "$(cat "${invocations}")" \
  "brew bundle --file=${REPO_ROOT}/home/dot_Brewfile" \
  "sync mode should call brew bundle --file=…"
assert_contains "$(cat "${invocations}")" \
  "brew bundle cleanup --file=${REPO_ROOT}/home/dot_Brewfile --force" \
  "sync mode should call brew bundle cleanup --force"

# ---- Scenario 4: default mode is sync (no arg) ----
reset_invocations
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/brew-bundle.sh"
assert_eq "0" "${RUN_STATUS}" "brew-bundle should default to sync when no mode arg given"
assert_contains "$(cat "${invocations}")" \
  "brew bundle cleanup --file=${REPO_ROOT}/home/dot_Brewfile --force" \
  "default (no-arg) mode should run cleanup --force (i.e. behave as sync)"

# ---- Scenario 5: preview mode, all clean ----
reset_invocations
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/brew-bundle.sh" preview
assert_eq "0" "${RUN_STATUS}" "brew-bundle preview should succeed when both checks pass"
assert_contains "${RUN_OUTPUT}" "Previewing Brewfile state" "preview should announce mode"
assert_contains "${RUN_OUTPUT}" "All declared dependencies are already installed" \
  "preview should report happy path for check"
assert_contains "${RUN_OUTPUT}" "No packages would be removed" \
  "preview should report happy path for cleanup"
# Preview must NOT call cleanup with --force (that would actually remove
# packages — the whole point of preview is non-destructive observation).
assert_not_contains "$(cat "${invocations}")" \
  "brew bundle cleanup --file=${REPO_ROOT}/home/dot_Brewfile --force" \
  "preview must not invoke cleanup with --force"

# ---- Scenario 6: preview with missing dependencies (check returns 1) ----
reset_invocations
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  BREW_CHECK_STATUS=1 BREW_CHECK_OUTPUT="Some package missing: ghostty" \
  bash "${REPO_ROOT}/scripts/brew-bundle.sh" preview
assert_eq "0" "${RUN_STATUS}" "brew-bundle preview should not fail when packages are missing (informational)"
assert_contains "${RUN_OUTPUT}" "Some package missing: ghostty" \
  "preview should surface check stdout/stderr when missing"
assert_contains "${RUN_OUTPUT}" "Missing dependencies are listed above" \
  "preview should announce missing-deps path"

# ---- Scenario 7: preview with packages to remove (cleanup returns 1) ----
reset_invocations
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  BREW_CLEANUP_STATUS=1 BREW_CLEANUP_OUTPUT="Would uninstall: stale-formula" \
  bash "${REPO_ROOT}/scripts/brew-bundle.sh" preview
assert_eq "0" "${RUN_STATUS}" "brew-bundle preview should not fail when cleanup would remove packages"
assert_contains "${RUN_OUTPUT}" "Would uninstall: stale-formula" \
  "preview should surface cleanup output when removals would happen"

# ---- Scenario 8: unknown mode → die ----
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/brew-bundle.sh" frobnicate
[[ "${RUN_STATUS}" -ne 0 ]] || fail_test "brew-bundle should exit non-zero on unknown mode"
assert_contains "${RUN_OUTPUT}" "Unsupported mode 'frobnicate'" \
  "unknown mode should surface in the error message"

# ---- Scenario 9: missing Brewfile ----
# Build a tmpdir copy of the script with no Brewfile alongside it, run from
# there. The script derives REPO_ROOT from BASH_SOURCE, so when invoked at
# ${copy}/scripts/brew-bundle.sh it expects ${copy}/home/dot_Brewfile.
copy="${tmpdir}/repo"
mkdir -p "${copy}/scripts"
cp "${REPO_ROOT}/scripts/brew-bundle.sh" "${copy}/scripts/brew-bundle.sh"
chmod +x "${copy}/scripts/brew-bundle.sh"
# Note: no Brewfile placed under ${copy}/home/ → guard should trigger.
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${copy}/scripts/brew-bundle.sh" check
[[ "${RUN_STATUS}" -ne 0 ]] || fail_test "brew-bundle should exit non-zero when Brewfile is missing"
assert_contains "${RUN_OUTPUT}" "Missing Brewfile" \
  "missing Brewfile should surface in the error message"

# ---- Scenario 10: missing brew binary ----
# Reset HERMETIC_BASE_ENV with a PATH that has no stub and no real brew.
# /usr/bin and /bin contain bash and friends but never brew on macOS
# (brew lives in /opt/homebrew/bin or /usr/local/bin). With env -i this
# is a fresh subprocess env, so the parent shell's $PATH cannot leak
# brew's real location through.
hermetic_base_env_init "/usr/bin:/bin"
HERMETIC_BASE_ENV+=(BREW_INVOCATIONS="${invocations}")
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/brew-bundle.sh" check
[[ "${RUN_STATUS}" -ne 0 ]] || fail_test "brew-bundle should exit non-zero when brew is missing"
assert_contains "${RUN_OUTPUT}" "brew not found in PATH" \
  "missing brew should surface in the error message"

pass_test "tests/brew-bundle.sh"
