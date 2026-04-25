#!/usr/bin/env bash
# Test: home/dot_claude/executable_chezmoi-auto-apply.sh
#
# Stubs chezmoi via PATH and toggles its behavior per scenario through env
# vars. The hook itself is dotfiles-managed but we copy it into tmpdir to
# avoid coupling the test to whatever ~/.claude/chezmoi-auto-apply.sh
# happens to be.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-chezmoi-auto-apply-test.XXXXXX")"
# macOS $TMPDIR usually ends with '/', so mktemp can produce paths with '//'
# embedded. cd normalizes those, but our hook does plain string-prefix matches
# against $HOME — keep both sides normalized so the test exercises the same
# code path real Claude Code does.
tmpdir="$(cd "${tmpdir}" && pwd -P)"
trap 'rm -rf "${tmpdir}"' EXIT

# HOME points at a fake home so the hook's cwd guard ("${HOME}/dotfiles")
# resolves to a path under our tmpdir. We do not actually populate the fake
# dotfiles repo — the hook only checks the path prefix, never reads files.
export HOME="${tmpdir}/home"
mkdir -p "${HOME}/dotfiles"

# Copy the hook out of the dotfiles source so the test exercises whatever
# the repo currently ships, not the deployed ~/.claude/ copy.
hook="${tmpdir}/chezmoi-auto-apply.sh"
cp "${REPO_ROOT}/home/dot_claude/executable_chezmoi-auto-apply.sh" "${hook}"
chmod +x "${hook}"

# Stub chezmoi. CHEZMOI_LOG records every call, CHEZMOI_HAS_DIFF makes
# `chezmoi diff` print non-empty output, CHEZMOI_APPLY_FAILS forces apply
# to exit non-zero. Other subcommands no-op.
mkdir -p "${tmpdir}/bin"
cat > "${tmpdir}/bin/chezmoi" <<'STUB'
#!/usr/bin/env bash
printf 'chezmoi %s\n' "$*" >> "${CHEZMOI_LOG:-/dev/null}"
case "${1:-}" in
  diff)
    [[ "${CHEZMOI_HAS_DIFF:-0}" == "1" ]] && printf '+ stub diff line\n'
    ;;
  apply)
    [[ "${CHEZMOI_APPLY_FAILS:-0}" == "1" ]] && exit 1
    ;;
esac
exit 0
STUB
chmod +x "${tmpdir}/bin/chezmoi"
export PATH="${tmpdir}/bin:${PATH}"

# ---- Scenario 1: workspace outside ~/dotfiles → fully silent, no chezmoi calls ----
export CHEZMOI_LOG="${tmpdir}/log-1"
: > "${CHEZMOI_LOG}"
unset CHEZMOI_HAS_DIFF CHEZMOI_APPLY_FAILS
RUN_OUTPUT="$(printf '%s' '{"workspace":{"current_dir":"/tmp/somewhere-else"}}' | bash "${hook}" 2>&1)"
RUN_STATUS=$?
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 outside the dotfiles repo"
assert_eq "" "${RUN_OUTPUT}" "hook should print nothing outside the dotfiles repo"
assert_eq "" "$(cat "${CHEZMOI_LOG}")" "hook should not call chezmoi outside the dotfiles repo"

# ---- Scenario 2: workspace = dotfiles, but no pending diff → diff called, apply skipped ----
export CHEZMOI_LOG="${tmpdir}/log-2"
: > "${CHEZMOI_LOG}"
RUN_OUTPUT="$(printf '%s' "{\"workspace\":{\"current_dir\":\"${HOME}/dotfiles\"}}" | bash "${hook}" 2>&1)"
RUN_STATUS=$?
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 when there is no diff"
assert_eq "" "${RUN_OUTPUT}" "hook should stay silent when there is no diff"
assert_contains "$(cat "${CHEZMOI_LOG}")" "chezmoi diff --no-pager" "hook should always probe via chezmoi diff"
assert_not_contains "$(cat "${CHEZMOI_LOG}")" "chezmoi apply" "hook should not apply when diff is empty"

# ---- Scenario 3: workspace = dotfiles, diff present → apply runs and logs success ----
export CHEZMOI_LOG="${tmpdir}/log-3"
: > "${CHEZMOI_LOG}"
export CHEZMOI_HAS_DIFF=1
RUN_OUTPUT="$(printf '%s' "{\"workspace\":{\"current_dir\":\"${HOME}/dotfiles/scripts\"}}" | bash "${hook}" 2>&1)"
RUN_STATUS=$?
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 after a successful apply"
assert_contains "${RUN_OUTPUT}" "chezmoi-auto-apply: synced source -> dest" "hook should log success"
assert_contains "$(cat "${CHEZMOI_LOG}")" "chezmoi apply" "hook should call chezmoi apply when diff is non-empty"
unset CHEZMOI_HAS_DIFF

# ---- Scenario 4: workspace = dotfiles, diff present, apply fails → failure logged, exit 0 ----
# The hook intentionally swallows the apply failure so a transient issue does
# not abort the assistant turn — it just nudges the user via stderr.
export CHEZMOI_LOG="${tmpdir}/log-4"
: > "${CHEZMOI_LOG}"
export CHEZMOI_HAS_DIFF=1
export CHEZMOI_APPLY_FAILS=1
RUN_OUTPUT="$(printf '%s' "{\"workspace\":{\"current_dir\":\"${HOME}/dotfiles\"}}" | bash "${hook}" 2>&1)"
RUN_STATUS=$?
assert_eq "0" "${RUN_STATUS}" "hook should still exit 0 when apply fails (non-fatal)"
assert_contains "${RUN_OUTPUT}" "chezmoi-auto-apply: apply failed" "hook should log apply failure"
unset CHEZMOI_HAS_DIFF CHEZMOI_APPLY_FAILS

# ---- Scenario 5: chezmoi missing from PATH → silent no-op ----
export CHEZMOI_LOG="${tmpdir}/log-5"
: > "${CHEZMOI_LOG}"
RUN_OUTPUT="$(PATH="/usr/bin:/bin" printf '%s' "{\"workspace\":{\"current_dir\":\"${HOME}/dotfiles\"}}" | PATH="/usr/bin:/bin" bash "${hook}" 2>&1)"
RUN_STATUS=$?
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 when chezmoi is not installed"
assert_eq "" "${RUN_OUTPUT}" "hook should stay silent when chezmoi is not installed"

# ---- Scenario 6: empty/missing workspace JSON falls back to PWD ----
# When PWD is outside ~/dotfiles, the hook should treat it like scenario 1.
export CHEZMOI_LOG="${tmpdir}/log-6"
: > "${CHEZMOI_LOG}"
RUN_OUTPUT="$(cd "${tmpdir}" && printf '' | bash "${hook}" 2>&1)"
RUN_STATUS=$?
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 with empty stdin and PWD outside dotfiles"
assert_eq "" "$(cat "${CHEZMOI_LOG}")" "hook should not call chezmoi when PWD is outside dotfiles"

# ---- Scenario 7: PWD inside ~/dotfiles takes the fast path (no jq spawn) ----
# Stub jq so we can detect whether the hot-path actually skipped it.
mkdir -p "${tmpdir}/bin-with-jq-trap"
cp "${tmpdir}/bin/chezmoi" "${tmpdir}/bin-with-jq-trap/chezmoi"
cat > "${tmpdir}/bin-with-jq-trap/jq" <<'STUB'
#!/usr/bin/env bash
printf 'jq %s\n' "$*" >> "${JQ_LOG:?JQ_LOG must be set}"
exit 0
STUB
chmod +x "${tmpdir}/bin-with-jq-trap/jq"
export JQ_LOG="${tmpdir}/jq-log-7"
: > "${JQ_LOG}"
export CHEZMOI_LOG="${tmpdir}/log-7"
: > "${CHEZMOI_LOG}"
# `cd && bash <<< json` keeps the bash invocation inside ~/dotfiles. A pipe
# would put bash in its own subshell that did NOT inherit the cd, defeating
# the whole point of the fast-path test.
RUN_OUTPUT="$(cd "${HOME}/dotfiles" && PATH="${tmpdir}/bin-with-jq-trap:/usr/bin:/bin" bash "${hook}" <<< '{"workspace":{"current_dir":"/somewhere/else"}}' 2>&1)"
RUN_STATUS=$?
assert_eq "0" "${RUN_STATUS}" "hook fast path should exit 0"
assert_eq "" "$(cat "${JQ_LOG}")" "fast path should not call jq when PWD is inside dotfiles"
assert_contains "$(cat "${CHEZMOI_LOG}")" "chezmoi diff" "fast path should still probe chezmoi diff"

pass_test "tests/chezmoi-auto-apply.sh"
