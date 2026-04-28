#!/usr/bin/env bash
# tests/bootstrap.sh — smoke test scripts/bootstrap.sh in an isolated env.
#
# bootstrap.sh is the new-machine entry point and was historically untested
# (drift would only surface when a user provisioned a fresh Mac). A full
# integration test would require real Homebrew + Xcode CLT, so this test
# stubs every external CLI to "already-installed / success" and asserts
# bootstrap takes the expected no-op convergence path:
#   - logs each numbered phase
#   - calls `brew bundle --file=<repo>/home/dot_Brewfile`
#   - creates the chezmoi symlink at $HOME/.local/share/chezmoi → REPO_ROOT
#   - calls `chezmoi apply` once
#   - exits 0

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bootstrap-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

export HOME="${tmpdir}/home"
mkdir -p "${HOME}"

stub_bin="${tmpdir}/bin"
mkdir -p "${stub_bin}"
invocations="${tmpdir}/invocations.log"
: > "${invocations}"

make_stub() {
  local name="$1"
  local body="$2"
  cat > "${stub_bin}/${name}" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "${name}" "\$*" >> "${invocations}"
${body}
EOF
  chmod +x "${stub_bin}/${name}"
}

# xcode-select -p succeeds (CLT installed) → skip the interactive `read` branch.
make_stub xcode-select 'case "${1:-}" in
  -p) echo "/Library/Developer/CommandLineTools" ;;
  *) exit 0 ;;
esac'

# Swift execution must succeed for bootstrap to proceed past the CLT check.
make_stub swift 'exit 0'

# Homebrew already installed; `brew install chezmoi` and `brew bundle` are no-ops.
make_stub brew 'case "${1:-}" in
  bundle) exit 0 ;;
  install) exit 0 ;;
  *) exit 0 ;;
esac'

# chezmoi present from the outset so the bootstrap install branch is skipped;
# `chezmoi apply` is a no-op.
make_stub chezmoi 'exit 0'

# Hermetic env for the `env -i … bash bootstrap.sh` callsites below.
# Base values (HOME / PATH / TMPDIR / TERM / locale) live in
# tests/lib/testlib.sh#hermetic_base_env_init — see that function for the
# rationale (parent-shell leak prevention). Stubs go first in PATH so
# bootstrap finds them before any system binary.
hermetic_base_env_init "${stub_bin}:/usr/bin:/bin:/usr/sbin:/sbin"

run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/bootstrap.sh"

assert_eq "0" "${RUN_STATUS}" "bootstrap should exit 0 in stubbed environment"
assert_contains "${RUN_OUTPUT}" "Installing packages from Brewfile" "bootstrap should log phase 4 (brew bundle)"
assert_contains "${RUN_OUTPUT}" "Applying dotfiles" "bootstrap should log phase 5 (chezmoi apply)"
assert_contains "${RUN_OUTPUT}" "Bootstrap complete" "bootstrap should log final completion"

# brew bundle must reference the Brewfile inside the repo, not a global one.
assert_contains "$(cat "${invocations}")" "brew bundle --file=${REPO_ROOT}/home/dot_Brewfile" \
  "bootstrap should pass --file=<repo>/home/dot_Brewfile to brew bundle"

assert_contains "$(cat "${invocations}")" "chezmoi apply" "bootstrap should call chezmoi apply"

# chezmoi symlink should be created and point back to the repo root.
chezmoi_link="${HOME}/.local/share/chezmoi"
if [[ ! -L "${chezmoi_link}" ]]; then
  fail_test "bootstrap should create symlink at ${chezmoi_link}"
fi
assert_eq "${REPO_ROOT}" "$(readlink "${chezmoi_link}")" \
  "chezmoi symlink should point to repo root"

# Python SSL compat sitecustomize must be deployed when source exists in repo.
ssl_compat_dst="${HOME}/.local/lib/python-ssl-compat/sitecustomize.py"
if [[ -f "${REPO_ROOT}/home/dot_local/lib/python-ssl-compat/sitecustomize.py" ]]; then
  if [[ ! -f "${ssl_compat_dst}" ]]; then
    fail_test "bootstrap should deploy SSL compat sitecustomize.py to ${ssl_compat_dst}"
  fi
fi

# ---- Re-pointing scenario: existing symlink to wrong target -----------------
rm -f "${chezmoi_link}"
mkdir -p "$(dirname "${chezmoi_link}")"
ln -s "${tmpdir}/wrong-target" "${chezmoi_link}"

run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/bootstrap.sh"
assert_eq "0" "${RUN_STATUS}" "bootstrap should re-point a stale symlink without error"
assert_eq "${REPO_ROOT}" "$(readlink "${chezmoi_link}")" \
  "bootstrap should repoint stale symlink to repo root"
assert_contains "${RUN_OUTPUT}" "Repointing existing chezmoi symlink" \
  "bootstrap should log when repointing"

pass_test "tests/bootstrap.sh"
