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

# Sandbox the playwright-cli wrapper's log directory so tests don't write to
# the user's real ~/.cache/playwright-cli/actions.log.
export XDG_CACHE_HOME="${tmpdir}/cache"

# Hermetic base env for `env -i … zsh -c …` callsites below: discards
# parent env so PLAYWRIGHT_CLI_SESSION / REBROWSER_PATCHES_RUNTIME_FIX_MODE
# exported by an interactive shell cannot leak into negative assertions
# (tests 7 / 11) or mask the module's own export (test 16). LANG/LC_ALL are
# required for guard A's multibyte regex (削除 / 公開) under env -i's C locale.
HERMETIC_BASE_ENV=(
  HOME="${HOME}"
  PATH="${tmpdir}:${PATH}"
  XDG_CACHE_HOME="${XDG_CACHE_HOME}"
  TERM="${TERM:-xterm-256color}"
  LANG="${LANG:-en_US.UTF-8}"
  LC_ALL="${LC_ALL:-en_US.UTF-8}"
)
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

for fn in pwsession pwopen pwedge pwlogin pwlist pwshow pwkill pwkillall; do
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
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; pwlogin demo https://example.com >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-}\""
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
run_capture env -i "${HERMETIC_BASE_ENV[@]}" PW_STUB_EXIT=2 zsh -c "source '${MODULE}'; pwlogin bad https://example.com >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=2" "pwlogin should propagate stub exit 2"
assert_contains "${RUN_OUTPUT}" "session=<unset>" "pwlogin should NOT export PLAYWRIGHT_CLI_SESSION on failure"

# 8. pwkill <name> must invoke playwright-cli delete-data --session <name>.
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; pwkill demo >/dev/null 2>&1"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "delete-data" "pwkill should call delete-data"
assert_contains "${stub_invocation}" "--session" "pwkill should pass --session"
assert_contains "${stub_invocation}" "demo" "pwkill should pass the session name"

# 9. pwlist / pwshow / pwkillall must invoke the expected subcommands.
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; pwlist >/dev/null 2>&1; pwshow >/dev/null 2>&1; pwkillall >/dev/null 2>&1"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "list" "pwlist should call list"
assert_contains "${stub_invocation}" "show" "pwshow should call show"
assert_contains "${stub_invocation}" "kill-all" "pwkillall should call kill-all"

# 10. pwedge must invoke `playwright-cli --session=edge open --browser=msedge
#     --headed --persistent --profile=<profile> ...` and export
#     PLAYWRIGHT_CLI_SESSION=edge on success. PLAYWRIGHT_AI_EDGE_PROFILE
#     overrides the default profile path.
: > "${stub_log}"
edge_profile="${tmpdir}/edge-profile"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_AI_EDGE_PROFILE="${edge_profile}" zsh -c "source '${MODULE}'; pwedge https://example.com >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=0" "pwedge should propagate stub exit 0"
assert_contains "${RUN_OUTPUT}" "session=edge" "pwedge should export PLAYWRIGHT_CLI_SESSION=edge on success"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "--session=edge" "pwedge should use --session=edge form"
assert_contains "${stub_invocation}" "open" "pwedge should invoke the open subcommand"
assert_contains "${stub_invocation}" "--browser=msedge" "pwedge should target msedge"
assert_contains "${stub_invocation}" "--headed" "pwedge should pass --headed"
assert_contains "${stub_invocation}" "--persistent" "pwedge should pass --persistent"
assert_contains "${stub_invocation}" "--profile=${edge_profile}" "pwedge should honor PLAYWRIGHT_AI_EDGE_PROFILE override"
assert_contains "${stub_invocation}" "https://example.com" "pwedge should pass through positional URL"
[[ -d "${edge_profile}" ]] || fail_test "pwedge should create the profile directory"

# 11. pwedge must NOT export PLAYWRIGHT_CLI_SESSION if playwright-cli fails.
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_AI_EDGE_PROFILE="${edge_profile}" PW_STUB_EXIT=4 zsh -c "source '${MODULE}'; pwedge https://example.com >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=4" "pwedge should propagate stub exit 4"
assert_contains "${RUN_OUTPUT}" "session=<unset>" "pwedge should NOT export PLAYWRIGHT_CLI_SESSION on failure"

# 12. playwright-cli wrapper — state-changing commands write to actions.log,
#     read-only commands do not, and `command playwright-cli` bypasses logging.
log_file="${XDG_CACHE_HOME}/playwright-cli/actions.log"
rm -f "${log_file}"
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_CLI_SESSION=test zsh -c "source '${MODULE}'; playwright-cli click foo >/dev/null 2>&1; playwright-cli snapshot >/dev/null 2>&1; command playwright-cli click bar >/dev/null 2>&1"
[[ -f "${log_file}" ]] || fail_test "wrapper should create actions.log when state-changing command runs"
log_contents="$(cat "${log_file}")"
assert_contains "${log_contents}" "click foo" "wrapper should log click invocations"
log_lines="$(wc -l < "${log_file}" | tr -d ' ')"
assert_eq "1" "${log_lines}" "wrapper should log state-changing commands only (no snapshot, no command-bypass)"
# All three invocations must still reach the stub binary (function-only logging).
stub_lines="$(grep -c . "${stub_log}" || true)"
assert_eq "3" "${stub_lines}" "wrapper should still call the underlying playwright-cli stub"

# 13. Guard D — state-changing command without active session must exit 1
#     and never reach the stub. Explicit --session in args bypasses the guard.
rm -f "${log_file}"
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; playwright-cli click foo; echo \"rc=\$?\""
assert_contains "${RUN_OUTPUT}" "rc=1" "wrapper should exit 1 when state-changing without session"
assert_contains "${RUN_OUTPUT}" "no active session" "wrapper should explain why it blocked"
stub_lines="$(grep -c . "${stub_log}" 2>/dev/null || true)"
assert_eq "0" "${stub_lines}" "wrapper should not reach stub when blocked by session guard"

: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; playwright-cli --session=demo click foo >/dev/null 2>&1; echo \"rc=\$?\""
assert_contains "${RUN_OUTPUT}" "rc=0" "explicit --session in args should bypass session guard"

# 14. Guard A — forbidden destructive click pattern must exit 1.
rm -f "${log_file}"
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_CLI_SESSION=test zsh -c "source '${MODULE}'; playwright-cli click 'text=削除'; echo \"rc=\$?\""
assert_contains "${RUN_OUTPUT}" "rc=1" "forbidden click pattern should exit 1"
assert_contains "${RUN_OUTPUT}" "forbidden destructive pattern" "guard A should print explanation"
stub_lines="$(grep -c . "${stub_log}" 2>/dev/null || true)"
assert_eq "0" "${stub_lines}" "guard A should not reach stub"

# Various L1 forbidden words should all trigger.
for label in "Submit" "logout" "Cancel" "公開" "Unsubscribe"; do
  : > "${stub_log}"
  run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_CLI_SESSION=test zsh -c "source '${MODULE}'; playwright-cli click 'text=${label}' 2>/dev/null; echo rc=\$?"
  assert_contains "${RUN_OUTPUT}" "rc=1" "guard A should fire on label '${label}'"
done

# Benign click should still pass (no false-positive on neutral selectors).
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_CLI_SESSION=test zsh -c "source '${MODULE}'; playwright-cli click '#main-nav' >/dev/null 2>&1; echo \"rc=\$?\""
assert_contains "${RUN_OUTPUT}" "rc=0" "benign click should pass guard A"

# `command playwright-cli` must bypass guard A entirely.
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_CLI_SESSION=test zsh -c "source '${MODULE}'; command playwright-cli click 'text=削除' >/dev/null 2>&1; echo \"rc=\$?\""
assert_contains "${RUN_OUTPUT}" "rc=0" "command bypass should skip guard A"

# 15. Guard B — forbidden eval/run-code write patterns must exit 1.
for expr in "document.cookie = 'x=y'" "el.innerHTML = ''" "fetch('/x', {method: 'POST'})" "el.submit()" "el.click()" "localStorage.setItem('a','b')" "document.execCommand('copy')"; do
  : > "${stub_log}"
  run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_CLI_SESSION=test zsh -c "source '${MODULE}'; playwright-cli eval \"${expr}\" 2>/dev/null; echo rc=\$?"
  assert_contains "${RUN_OUTPUT}" "rc=1" "guard B should fire on write expr: ${expr}"
done

# Read-only eval expressions should pass.
for expr in "document.title" "el.textContent" "el.getAttribute('href')" "el.getBoundingClientRect()" "document.querySelectorAll('.btn').length"; do
  : > "${stub_log}"
  run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_CLI_SESSION=test zsh -c "source '${MODULE}'; playwright-cli eval \"${expr}\" >/dev/null 2>&1; echo rc=\$?"
  assert_contains "${RUN_OUTPUT}" "rc=0" "guard B should not fire on read-only expr: ${expr}"
done

# `command playwright-cli` must bypass guard B too.
: > "${stub_log}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_CLI_SESSION=test zsh -c "source '${MODULE}'; command playwright-cli eval \"document.cookie = 'x=y'\" >/dev/null 2>&1; echo rc=\$?"
assert_contains "${RUN_OUTPUT}" "rc=0" "command bypass should skip guard B"

# 17. pwopen <tag> [url] — must invoke `playwright-cli --session=<tag> open
#     --browser=msedge --headed --persistent --profile=$HOME/.ai-<tag> ...` and
#     export PLAYWRIGHT_CLI_SESSION=<tag>. Default profile path follows the
#     ~/.ai-<tag> sibling convention (no env override).
: > "${stub_log}"
fake_home="${tmpdir}/home17"
mkdir -p "${fake_home}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" HOME="${fake_home}" zsh -c "source '${MODULE}'; pwopen acme https://example.com >/dev/null 2>&1; echo \"rc=\$?\"; echo \"session=\${PLAYWRIGHT_CLI_SESSION:-<unset>}\""
assert_contains "${RUN_OUTPUT}" "rc=0" "pwopen should propagate stub exit 0"
assert_contains "${RUN_OUTPUT}" "session=acme" "pwopen should export PLAYWRIGHT_CLI_SESSION=<tag> on success"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "--session=acme" "pwopen should use --session=<tag> form"
assert_contains "${stub_invocation}" "--browser=msedge" "pwopen should target msedge"
assert_contains "${stub_invocation}" "--headed" "pwopen should pass --headed"
assert_contains "${stub_invocation}" "--persistent" "pwopen should pass --persistent"
assert_contains "${stub_invocation}" "--profile=${fake_home}/.ai-acme" "pwopen should default profile to \$HOME/.ai-<tag>"
assert_contains "${stub_invocation}" "https://example.com" "pwopen should pass through positional URL"
[[ -d "${fake_home}/.ai-acme" ]] || fail_test "pwopen should create the default profile directory"

# 18. pwopen with hyphenated tag must convert hyphens to underscores in the
#     env-var name lookup (saas-acme → PLAYWRIGHT_AI_SAAS_ACME_PROFILE).
: > "${stub_log}"
custom_profile="${tmpdir}/saas-acme-profile"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" PLAYWRIGHT_AI_SAAS_ACME_PROFILE="${custom_profile}" zsh -c "source '${MODULE}'; pwopen saas-acme >/dev/null 2>&1; echo \"rc=\$?\""
assert_contains "${RUN_OUTPUT}" "rc=0" "pwopen with hyphen tag should propagate stub exit 0"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "--session=saas-acme" "pwopen should pass hyphenated tag through to --session"
assert_contains "${stub_invocation}" "--profile=${custom_profile}" "pwopen should resolve PLAYWRIGHT_AI_SAAS_ACME_PROFILE for tag=saas-acme"
[[ -d "${custom_profile}" ]] || fail_test "pwopen should create the env-overridden profile directory"

# 19. pwopen with non-edge tag must NOT call `tab-list` (guard is edge-only,
#     to avoid false positives on SaaS tenant profiles where Stripe / Salesforce
#     are normal state). pwopen edge SHOULD call tab-list.
: > "${stub_log}"
fake_home="${tmpdir}/home19a"
mkdir -p "${fake_home}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" HOME="${fake_home}" zsh -c "source '${MODULE}'; pwopen acme >/dev/null 2>&1"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_not_contains "${stub_invocation}" "tab-list" "pwopen with non-edge tag should NOT call tab-list (guard is edge-only)"

: > "${stub_log}"
fake_home="${tmpdir}/home19b"
mkdir -p "${fake_home}"
run_capture env -i "${HERMETIC_BASE_ENV[@]}" HOME="${fake_home}" zsh -c "source '${MODULE}'; pwopen edge >/dev/null 2>&1"
stub_invocation="$(tr '\0' ' ' < "${stub_log}")"
assert_contains "${stub_invocation}" "tab-list" "pwopen with edge tag should call tab-list (contamination guard)"

# 20. pwopen with no args must print usage and exit 1.
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; pwopen"
assert_eq "1" "${RUN_STATUS}" "pwopen without args should fail"
assert_contains "${RUN_OUTPUT}" "usage: pwopen" "pwopen should print usage on misuse"

# 16. rebrowser-patches runtime fix — module must export
#     REBROWSER_PATCHES_RUNTIME_FIX_MODE=addBinding by default and respect
#     user-set values (so callers can override to "alwaysIsolated" etc.).
run_capture env -i "${HERMETIC_BASE_ENV[@]}" zsh -c "source '${MODULE}'; echo \"mode=\${REBROWSER_PATCHES_RUNTIME_FIX_MODE}\""
assert_contains "${RUN_OUTPUT}" "mode=addBinding" "module should default REBROWSER_PATCHES_RUNTIME_FIX_MODE to addBinding"

run_capture env -i "${HERMETIC_BASE_ENV[@]}" REBROWSER_PATCHES_RUNTIME_FIX_MODE=alwaysIsolated zsh -c "source '${MODULE}'; echo \"mode=\${REBROWSER_PATCHES_RUNTIME_FIX_MODE}\""
assert_contains "${RUN_OUTPUT}" "mode=alwaysIsolated" "module should not clobber user-set REBROWSER_PATCHES_RUNTIME_FIX_MODE"

pass_test "tests/playwright-zsh.sh"
