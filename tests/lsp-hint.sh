#!/usr/bin/env bash
# tests/lsp-hint.sh — regression test for the PreToolUse Grep advisory hook.
#
# The hook (home/dot_claude/executable_lsp-hint.sh) reads JSON on stdin,
# extracts tool_input.pattern, and emits a Serena advisory to stderr ONLY
# when the pattern looks like an explicit code-symbol search (leading space
# + definition keyword). It never blocks — all paths must exit 0.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

HOOK="${REPO_ROOT}/home/dot_claude/executable_lsp-hint.sh"
[[ -x "${HOOK}" ]] || fail_test "hook missing or not executable: ${HOOK}"

# 1. Trigger case: ` def ` pattern.
run_capture bash -c "echo '{\"tool_input\":{\"pattern\":\"def main\"}}' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 on trigger case"
assert_contains "${RUN_OUTPUT}" "lsp-hint" "hook should emit advisory on def pattern"
assert_contains "${RUN_OUTPUT}" "Serena" "hook advisory should mention Serena"

# 2. Trigger case: ` class ` pattern.
run_capture bash -c "echo '{\"tool_input\":{\"pattern\":\"class MyClass\"}}' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 on class pattern"
assert_contains "${RUN_OUTPUT}" "lsp-hint" "hook should emit advisory on class pattern"

# 3. Trigger case: ` function ` pattern.
run_capture bash -c "echo '{\"tool_input\":{\"pattern\":\"function foo\"}}' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 on function pattern"
assert_contains "${RUN_OUTPUT}" "lsp-hint" "hook should emit advisory on function pattern"

# 4. Non-trigger: "definitely" is not " def " (no leading-space match).
run_capture bash -c "echo '{\"tool_input\":{\"pattern\":\"definitely broken\"}}' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 on non-trigger"
assert_not_contains "${RUN_OUTPUT}" "lsp-hint" "hook should stay silent on 'definitely'"

# 5. Non-trigger: "classifier" is not " class ".
run_capture bash -c "echo '{\"tool_input\":{\"pattern\":\"classifier bug\"}}' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 on classifier pattern"
assert_not_contains "${RUN_OUTPUT}" "lsp-hint" "hook should stay silent on 'classifier'"

# 6. Non-trigger: ordinary text search.
run_capture bash -c "echo '{\"tool_input\":{\"pattern\":\"TODO: fix\"}}' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 on TODO pattern"
assert_not_contains "${RUN_OUTPUT}" "lsp-hint" "hook should stay silent on plain text"

# 7. Edge case: empty pattern.
run_capture bash -c "echo '{\"tool_input\":{\"pattern\":\"\"}}' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 on empty pattern"
assert_not_contains "${RUN_OUTPUT}" "lsp-hint" "hook should stay silent on empty pattern"

# 8. Edge case: malformed JSON on stdin.
run_capture bash -c "echo 'not-json-at-all' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 on malformed JSON (must never block)"

# 9. Edge case: missing tool_input.pattern field.
run_capture bash -c "echo '{\"tool_input\":{}}' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 when pattern field is absent"
assert_not_contains "${RUN_OUTPUT}" "lsp-hint" "hook should stay silent when pattern absent"

# 10. Leading-space-prefixed trigger to confirm the regex anchor at start-of-string.
run_capture bash -c "echo '{\"tool_input\":{\"pattern\":\" interface Foo\"}}' | '${HOOK}'"
assert_eq "0" "${RUN_STATUS}" "hook should exit 0 on ' interface ' pattern"
assert_contains "${RUN_OUTPUT}" "lsp-hint" "hook should trigger on leading-space interface"

pass_test "tests/lsp-hint.sh"
