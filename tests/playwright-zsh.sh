#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

MODULE="${REPO_ROOT}/home/dot_config/zsh/playwright.zsh"

if [[ ! -f "${MODULE}" ]]; then
  fail_test "playwright.zsh module missing at ${MODULE}"
fi

if ! command -v zsh >/dev/null 2>&1; then
  printf 'SKIP: zsh not available, skipping syntax checks\n'
  pass_test "tests/playwright-zsh.sh (skipped)"
  exit 0
fi

# 1. Syntax check — module should parse cleanly.
run_capture zsh -n "${MODULE}"
assert_eq "0" "${RUN_STATUS}" "playwright.zsh should parse without syntax errors"

# 2. With playwright-cli absent, module should early-return and define no functions.
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-pwzsh-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT
run_capture zsh -c "PATH='${tmpdir}' source '${MODULE}'; typeset -f pwsession >/dev/null && echo defined || echo absent"
assert_eq "0" "${RUN_STATUS}" "sourcing module with no playwright-cli should not error"
assert_contains "${RUN_OUTPUT}" "absent" "module should not define pwsession when playwright-cli is missing"

# 3. With a stub playwright-cli on PATH, every helper should be defined.
# The stub logs its argv to $PW_STUB_LOG so tests can assert on the exact
# invocation (prevents silent refactor regressions like dropping --persistent).
stub_log="${tmpdir}/pwcli.log"
cat > "${tmpdir}/playwright-cli" <<EOF
#!/usr/bin/env bash
printf '%s\0' "\$@" >> "${stub_log}"
printf '\n' >> "${stub_log}"
exit "\${PW_STUB_EXIT:-0}"
EOF
chmod +x "${tmpdir}/playwright-cli"

for fn in pwsession pwlogin pwlist pwshow pwkill pwkillall; do
  run_capture zsh -c "PATH='${tmpdir}:${PATH}' source '${MODULE}'; typeset -f ${fn} >/dev/null && echo ok"
  assert_eq "0" "${RUN_STATUS}" "${fn} lookup should not error"
  assert_contains "${RUN_OUTPUT}" "ok" "${fn} should be defined when playwright-cli is present"
done

# 4. pwsession must export PLAYWRIGHT_CLI_SESSION.
run_capture zsh -c "PATH='${tmpdir}:${PATH}' source '${MODULE}'; pwsession demo >/dev/null; echo \"session=\${PLAYWRIGHT_CLI_SESSION}\""
assert_eq "0" "${RUN_STATUS}" "pwsession should succeed with a valid argument"
assert_contains "${RUN_OUTPUT}" "session=demo" "pwsession should export PLAYWRIGHT_CLI_SESSION"

# 5. pwsession with wrong argc should fail.
run_capture zsh -c "PATH='${tmpdir}:${PATH}' source '${MODULE}'; pwsession"
assert_eq "1" "${RUN_STATUS}" "pwsession without args should fail"
assert_contains "${RUN_OUTPUT}" "usage: pwsession" "pwsession should print usage on misuse"

# 6. pwlogin must invoke playwright-cli with canonical argv and only export
#    PLAYWRIGHT_CLI_SESSION on success.
: > "${stub_log}"
run_capture zsh -c "PATH='${tmpdir}:${PATH}' source '${MODULE}'; pwlogin demo https://example.com >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-}\""
assert_contains "${RUN_OUTPUT}" "rc=0" "pwlogin should propagate stub exit 0"
assert_contains "${RUN_OUTPUT}" "session=demo" "pwlogin should export PLAYWRIGHT_CLI_SESSION on success"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "--session=demo" "pwlogin should use --session=<name> form"
assert_contains "${stub_invocation}" "open" "pwlogin should invoke the open subcommand"
assert_contains "${stub_invocation}" "--headed" "pwlogin should pass --headed"
assert_contains "${stub_invocation}" "--persistent" "pwlogin should pass --persistent"
assert_contains "${stub_invocation}" "https://example.com" "pwlogin should pass the URL"

# 7. pwlogin must NOT export PLAYWRIGHT_CLI_SESSION if playwright-cli fails.
: > "${stub_log}"
run_capture zsh -c "PATH='${tmpdir}:${PATH}' PW_STUB_EXIT=2 source '${MODULE}'; pwlogin bad https://example.com >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=2" "pwlogin should propagate stub exit 2"
assert_contains "${RUN_OUTPUT}" "session=<unset>" "pwlogin should NOT export PLAYWRIGHT_CLI_SESSION on failure"

# 8. pwkill <name> must invoke playwright-cli delete-data --session <name>.
: > "${stub_log}"
run_capture zsh -c "PATH='${tmpdir}:${PATH}' source '${MODULE}'; pwkill demo >/dev/null 2>&1"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "delete-data" "pwkill should call delete-data"
assert_contains "${stub_invocation}" "--session" "pwkill should pass --session"
assert_contains "${stub_invocation}" "demo" "pwkill should pass the session name"

# 9. pwlist / pwshow / pwkillall must invoke the expected subcommands.
: > "${stub_log}"
run_capture zsh -c "PATH='${tmpdir}:${PATH}' source '${MODULE}'; pwlist >/dev/null 2>&1; pwshow >/dev/null 2>&1; pwkillall >/dev/null 2>&1"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "list" "pwlist should call list"
assert_contains "${stub_invocation}" "show" "pwshow should call show"
assert_contains "${stub_invocation}" "kill-all" "pwkillall should call kill-all"

pass_test "tests/playwright-zsh.sh"
