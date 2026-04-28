#!/usr/bin/env bash
# tests/preview.sh — smoke test for scripts/preview.sh.
#
# preview.sh is a read-only summary of pending dotfiles changes (chezmoi diff
# + dry-run + brew bundle preview). The smoke test stubs chezmoi and brew so
# the script's structure is exercised end-to-end without touching the real
# environment, and asserts on:
#   - exit code 0 when all sub-commands are happy
#   - all four section headers are emitted ("=== dotfiles preview ===",
#     "[chezmoi diff]", "[chezmoi apply --dry-run --verbose]", "[Homebrew bundle]")
#   - exit code non-zero (1) when brew-bundle preview fails (the only branch
#     that escalates failure)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-preview-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

stub_bin="${tmpdir}/bin"
mkdir -p "${stub_bin}"

# chezmoi stub: handles diff (no-op output) and apply --dry-run (no-op).
cat > "${stub_bin}/chezmoi" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  diff) exit 0 ;;
  apply) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${stub_bin}/chezmoi"

# brew stub: brew-bundle.sh's preview mode runs `brew bundle check` and
# `brew bundle cleanup`. Both succeed by default; BREW_PREVIEW_FAIL=1 flips
# `brew bundle check` to a non-recoverable error (status 2) so brew-bundle's
# `exit "${check_status}"` fires and propagates back to preview.sh.
cat > "${stub_bin}/brew" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  bundle)
    shift
    case "${1:-}" in
      check)
        if [[ "${BREW_PREVIEW_FAIL:-0}" == "1" ]]; then
          exit 2
        fi
        exit 0
        ;;
      cleanup) exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${stub_bin}/brew"

# Hermetic env. Stubs first in PATH so preview.sh finds them before any
# real chezmoi / brew on the developer's machine.
hermetic_base_env_init "${stub_bin}:/usr/bin:/bin:/usr/sbin:/sbin"

# ---- Scenario 1: happy path (everything green) ----
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/preview.sh"
assert_eq "0" "${RUN_STATUS}" "preview should exit 0 when chezmoi and brew stubs return success"
assert_contains "${RUN_OUTPUT}" "=== dotfiles preview ===" "preview should print main banner"
assert_contains "${RUN_OUTPUT}" "[chezmoi diff]" "preview should print chezmoi diff section header"
assert_contains "${RUN_OUTPUT}" "[chezmoi apply --dry-run --verbose]" \
  "preview should print chezmoi apply dry-run section header"
assert_contains "${RUN_OUTPUT}" "[Homebrew bundle]" "preview should print homebrew section header"

# ---- Scenario 2: brew preview fails → preview.sh propagates exit 1 ----
run_capture env -i "${HERMETIC_BASE_ENV[@]}" BREW_PREVIEW_FAIL=1 \
  bash "${REPO_ROOT}/scripts/preview.sh"
assert_eq "1" "${RUN_STATUS}" "preview should exit 1 when brew-bundle preview reports an error"
assert_contains "${RUN_OUTPUT}" "Brew preview reported an error" \
  "preview should surface the warn message before exit 1"

pass_test "tests/preview.sh"
