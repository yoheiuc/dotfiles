#!/usr/bin/env bash
# tests/bitwarden-zsh.sh — regression suite for the Bitwarden CLI zsh wrapper.
# Mirrors tests/playwright-zsh.sh: hermetic env, PATH-stubbed `bw`, full
# allowlist / denylist / bypass / env-leak coverage.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

MODULE="${REPO_ROOT}/home/dot_config/zsh/bitwarden.zsh"

if [[ ! -f "${MODULE}" ]]; then
  fail_test "bitwarden.zsh module missing at ${MODULE}"
fi

if ! command -v zsh >/dev/null 2>&1; then
  printf 'SKIP: zsh not available, skipping syntax checks\n'
  pass_test "tests/bitwarden-zsh.sh (skipped)"
  exit 0
fi

# 1. Syntax check — module should parse cleanly.
run_capture zsh -n "${MODULE}"
assert_eq "0" "${RUN_STATUS}" "bitwarden.zsh should parse without syntax errors"

# 2. With `bw` absent, module should early-return and define no helpers.
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bwzsh-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

# Sandbox the wrapper's log directory so the test never touches the user's
# real ~/.cache/bitwarden-cli/actions.log.
export XDG_CACHE_HOME="${tmpdir}/cache"

# Hermetic base env — drops parent shell exports (BW_SESSION in particular)
# so they cannot leak into the subprocess. LANG/LC_ALL kept ASCII; the wrapper
# only emits ASCII diagnostics.
HERMETIC_BASE_ENV=(
  HOME="${HOME}"
  PATH="${tmpdir}:${PATH}"
  XDG_CACHE_HOME="${XDG_CACHE_HOME}"
  TERM="${TERM:-xterm-256color}"
  LANG=C
  LC_ALL=C
)

empty_dir="${tmpdir}/empty"
mkdir -p "${empty_dir}"
run_capture zsh -c "PATH='${empty_dir}' source '${MODULE}'; typeset -f bwunlock >/dev/null && echo defined || echo absent"
assert_eq "0" "${RUN_STATUS}" "sourcing module with no bw should not error"
assert_contains "${RUN_OUTPUT}" "absent" "module should not define bwunlock when bw is missing"

# 3. With a stub `bw` on PATH, every helper / wrapper should be defined.
# The stub records its argv to $stub_log so tests can assert on the exact
# invocation. Behaviour:
#   - `bw unlock --raw` prints a 64-char fake session token to stdout
#   - everything else just exits ${BW_STUB_EXIT:-0}
stub_log="${tmpdir}/bw.log"
cat > "${tmpdir}/bw" <<EOF
#!/usr/bin/env bash
printf '%s\0' "\$@" >> "${stub_log}"
printf '\n' >> "${stub_log}"
if [[ "\$1" == "unlock" && "\$2" == "--raw" ]]; then
  printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
fi
exit "\${BW_STUB_EXIT:-0}"
EOF
chmod +x "${tmpdir}/bw"

for fn in bwunlock bwlock bwstatus bw; do
  run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; typeset -f ${fn} >/dev/null && echo ok"
  assert_eq "0" "${RUN_STATUS}" "${fn} lookup should not error"
  assert_contains "${RUN_OUTPUT}" "ok" "${fn} should be defined when bw is present"
done

# 4. bwunlock — exports BW_SESSION on success, leaves it unset on failure.
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; bwunlock >/dev/null 2>&1; echo \"rc=\$?\"; echo \"len=\${#BW_SESSION}\""
assert_contains "${RUN_OUTPUT}" "rc=0" "bwunlock should succeed when stub returns a token"
assert_contains "${RUN_OUTPUT}" "len=64" "bwunlock should export BW_SESSION with the token"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "unlock --raw" "bwunlock should call bw unlock --raw"

: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" BW_STUB_EXIT=2 zsh -c "source '${MODULE}'; bwunlock >/dev/null 2>&1; echo \"rc=\$?\"; echo \"set=\${BW_SESSION+yes}\""
assert_contains "${RUN_OUTPUT}" "rc=2" "bwunlock should propagate stub exit on failure"
assert_contains "${RUN_OUTPUT}" "set=" "bwunlock should NOT export BW_SESSION on failure"

# 5. bwlock — invokes `bw lock` and unsets BW_SESSION even when lock fails.
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" BW_SESSION=preexisting BW_STUB_EXIT=3 zsh -c "source '${MODULE}'; bwlock >/dev/null 2>&1; echo \"set=\${BW_SESSION+yes}\""
assert_contains "${RUN_OUTPUT}" "set=" "bwlock should unset BW_SESSION even if bw lock errored"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "lock" "bwlock should call bw lock"

# 6. Allowlist — all read-only subcommands reach the stub with rc=0.
allowed_cases=(
  "list items"
  "list items --search github"
  "get password github.com"
  "get item 99ee88d2-6046-4ea7-92c2-acac464b1412"
  "get totp google.com"
  "get username github"
  "generate -ulns --length 32"
  "status"
  "sync"
  "config server https://vault.bitwarden.com"
  "completion --shell zsh"
  "--help"
  "--version"
)
for cmd in "${allowed_cases[@]}"; do
  : > "${stub_log}"
  run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; bw ${cmd} >/dev/null 2>&1; echo \"rc=\$?\""
  assert_contains "${RUN_OUTPUT}" "rc=0" "allowlist '${cmd}' should reach stub with rc=0"
  stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
  first_token="${cmd%% *}"
  assert_contains "${stub_invocation}" "${first_token}" "allowlist '${cmd}' should pass first token to stub"
done

# 7. Denylist — state-changing subcommands must exit 1 WITHOUT touching the stub.
denied_cases=(
  "create item -"
  "edit item abc-123"
  "delete item abc-123"
  "delete attachment abc-123"
  "restore item abc-123"
  "share item abc-123 org-id"
  "send create -"
  "import bitwardencsv ./vault.csv"
  "export --output ./vault.json"
  "move item abc-123 collection-id"
  "confirm member abc-123 org-id"
  "encode"
  "serve"
  "pending"
)
for cmd in "${denied_cases[@]}"; do
  : > "${stub_log}"
  run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; bw ${cmd} 2>/dev/null; echo \"rc=\$?\""
  assert_contains "${RUN_OUTPUT}" "rc=1" "denylist '${cmd}' should exit 1"
  if [[ -s "${stub_log}" ]]; then
    fail_test "denylist '${cmd}' must not invoke the stub bw (log non-empty)"
  fi
done

# 8. Denials must be appended to ~/.cache/bitwarden-cli/actions.log (DENY rows).
logfile="${XDG_CACHE_HOME}/bitwarden-cli/actions.log"
rm -f "${logfile}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; bw delete item abc-123 2>/dev/null; bw export --output ./v.json 2>/dev/null"
[[ -f "${logfile}" ]] || fail_test "denials must produce ${logfile}"
log_content="$(cat "${logfile}")"
assert_contains "${log_content}" "DENY" "log entries should be tagged DENY"
assert_contains "${log_content}" "delete item abc-123" "log should contain denied argv"
assert_contains "${log_content}" "export --output" "log should contain second denied argv"

# 9. Allowed commands must NOT write to the deny log.
rm -f "${logfile}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; bw list items >/dev/null 2>&1; bw get password github >/dev/null 2>&1"
if [[ -s "${logfile}" ]]; then
  fail_test "allowed commands must not write to the deny log (file non-empty)"
fi

# 10. Bypass — `command bw <denied> …` must skip the wrapper and reach the stub.
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; command bw delete item abc-123 >/dev/null 2>&1; echo \"rc=\$?\""
assert_contains "${RUN_OUTPUT}" "rc=0" "command bw bypass should reach stub with rc=0"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "delete item abc-123" "command bw bypass should pass denied argv to stub"

# 11. Hermetic env — BW_SESSION exported by the parent shell must not leak in.
# Sanity: even if we set BW_SESSION on the *outer* test shell, the env -i call
# should not propagate it. (Inner BW_SESSION is set by bwunlock above.)
export BW_SESSION="this-must-not-leak"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; echo \"leak=\${BW_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "leak=<unset>" "BW_SESSION must not leak through hermetic base env"
unset BW_SESSION

pass_test "tests/bitwarden-zsh.sh"
