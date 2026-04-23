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

for fn in pwsession pwattach pwdetach pwlogin pwlist pwshow pwkill pwkillall; do
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

# Helpers 6–9 call `playwright-cli` from inside the zsh functions, so the
# stub must stay reachable for the entire `zsh -c` subshell. Inlining the
# assignment as `PATH='…' source '…'; pwfn` only scopes PATH to `source`
# in zsh, so the function call after it would revert to the outer PATH and
# miss the stub. Passing PATH via `env` propagates it to the whole zsh
# process instead.

# 6. pwlogin must invoke playwright-cli with canonical argv and only export
#    PLAYWRIGHT_CLI_SESSION on success.
: > "${stub_log}"
run_capture env PATH="${tmpdir}:${PATH}" zsh -c "source '${MODULE}'; pwlogin demo https://example.com >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-}\""
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
run_capture env PATH="${tmpdir}:${PATH}" PW_STUB_EXIT=2 zsh -c "source '${MODULE}'; pwlogin bad https://example.com >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=2" "pwlogin should propagate stub exit 2"
assert_contains "${RUN_OUTPUT}" "session=<unset>" "pwlogin should NOT export PLAYWRIGHT_CLI_SESSION on failure"

# 8. pwkill <name> must invoke playwright-cli delete-data --session <name>.
: > "${stub_log}"
run_capture env PATH="${tmpdir}:${PATH}" zsh -c "source '${MODULE}'; pwkill demo >/dev/null 2>&1"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "delete-data" "pwkill should call delete-data"
assert_contains "${stub_invocation}" "--session" "pwkill should pass --session"
assert_contains "${stub_invocation}" "demo" "pwkill should pass the session name"

# 9. pwlist / pwshow / pwkillall must invoke the expected subcommands.
: > "${stub_log}"
run_capture env PATH="${tmpdir}:${PATH}" zsh -c "source '${MODULE}'; pwlist >/dev/null 2>&1; pwshow >/dev/null 2>&1; pwkillall >/dev/null 2>&1"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "list" "pwlist should call list"
assert_contains "${stub_invocation}" "show" "pwshow should call show"
assert_contains "${stub_invocation}" "kill-all" "pwkillall should call kill-all"

# 10a. pwattach must REFUSE when PLAYWRIGHT_AI_CHROME_READY is unset (policy:
#      force the user through the AI-dedicated Chrome profile setup so the
#      attach can't accidentally land on an everyday profile).
: > "${stub_log}"
run_capture env PATH="${tmpdir}:${PATH}" zsh -c "unset PLAYWRIGHT_AI_CHROME_READY; source '${MODULE}'; pwattach 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=2" "pwattach should exit 2 when PLAYWRIGHT_AI_CHROME_READY is unset"
assert_contains "${RUN_OUTPUT}" "session=<unset>" "pwattach should NOT export PLAYWRIGHT_CLI_SESSION when refusing"
assert_contains "${RUN_OUTPUT}" "PLAYWRIGHT_AI_CHROME_READY" "pwattach should surface the env var name in its refusal message"
assert_contains "${RUN_OUTPUT}" "AI-dedicated Chrome profile" "pwattach refusal should mention the AI-dedicated profile policy"
# And the stub must not have been invoked.
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_eq "" "${stub_invocation}" "pwattach should not invoke playwright-cli when refusing"

# 10b. pwattach must call `playwright-cli --session=chrome attach --cdp=chrome`
#      and export PLAYWRIGHT_CLI_SESSION=chrome on success when the env var is set.
: > "${stub_log}"
run_capture env PATH="${tmpdir}:${PATH}" PLAYWRIGHT_AI_CHROME_READY=1 zsh -c "source '${MODULE}'; pwattach >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=0" "pwattach should propagate stub exit 0 when env var is set"
assert_contains "${RUN_OUTPUT}" "session=chrome" "pwattach should export PLAYWRIGHT_CLI_SESSION=chrome on success"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "--session=chrome" "pwattach should use --session=chrome form"
assert_contains "${stub_invocation}" "attach" "pwattach should invoke the attach subcommand"
assert_contains "${stub_invocation}" "--cdp=chrome" "pwattach should pass --cdp=chrome"

# 11. pwattach must NOT export PLAYWRIGHT_CLI_SESSION if playwright-cli fails.
: > "${stub_log}"
run_capture env PATH="${tmpdir}:${PATH}" PLAYWRIGHT_AI_CHROME_READY=1 PW_STUB_EXIT=3 zsh -c "source '${MODULE}'; pwattach >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=3" "pwattach should propagate stub exit 3"
assert_contains "${RUN_OUTPUT}" "session=<unset>" "pwattach should NOT export PLAYWRIGHT_CLI_SESSION on failure"

# 12. pwdetach must call `playwright-cli --session=chrome close` and unset
#     PLAYWRIGHT_CLI_SESSION. It should succeed even if close reports an error
#     (e.g. nothing was attached).
: > "${stub_log}"
run_capture env PATH="${tmpdir}:${PATH}" zsh -c "source '${MODULE}'; export PLAYWRIGHT_CLI_SESSION=chrome; pwdetach >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=0" "pwdetach should exit 0"
assert_contains "${RUN_OUTPUT}" "session=<unset>" "pwdetach should unset PLAYWRIGHT_CLI_SESSION"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "--session=chrome" "pwdetach should target --session=chrome"
assert_contains "${stub_invocation}" "close" "pwdetach should call close"

# 13. pwdetach should still unset PLAYWRIGHT_CLI_SESSION even if close fails.
: > "${stub_log}"
run_capture env PATH="${tmpdir}:${PATH}" PW_STUB_EXIT=1 zsh -c "source '${MODULE}'; export PLAYWRIGHT_CLI_SESSION=chrome; pwdetach >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=0" "pwdetach should swallow close errors"
assert_contains "${RUN_OUTPUT}" "session=<unset>" "pwdetach should unset PLAYWRIGHT_CLI_SESSION even on close error"

pass_test "tests/playwright-zsh.sh"
