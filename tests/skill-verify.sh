#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-skill-verify-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

export HOME="${tmpdir}/home"
mkdir -p "${HOME}/.claude/skills/docfake" "${HOME}/.claude/commands"
: > "${HOME}/.claude/skills/docfake/SKILL.md"
: > "${HOME}/.claude/commands/refactorfake.md"

HELPER="bash ${REPO_ROOT}/scripts/skill-verify.sh"

# ---- start (skill) ----
run_capture ${HELPER} start skill docfake
assert_eq "0" "${RUN_STATUS}" "start should succeed for an existing skill"
assert_contains "${RUN_OUTPUT}" "renamed" "start should mention the rename"
# Original should be gone
[[ ! -e "${HOME}/.claude/skills/docfake" ]] || fail_test "start should move the skill dir away"
# Backup should exist
compgen -G "${HOME}/.claude/skills/docfake.verify-bak.*" >/dev/null || fail_test "start should create a backup dir"

# ---- list ----
run_capture ${HELPER} list
assert_eq "0" "${RUN_STATUS}" "list should succeed"
assert_contains "${RUN_OUTPUT}" "docfake" "list should show the pending rename"

# ---- confirm (skill) ----
run_capture ${HELPER} confirm skill docfake
assert_eq "0" "${RUN_STATUS}" "confirm should succeed"
assert_contains "${RUN_OUTPUT}" "deleted" "confirm should report deletion"
compgen -G "${HOME}/.claude/skills/docfake.verify-bak.*" >/dev/null && fail_test "confirm should delete the backup dir"
run_capture ${HELPER} list
assert_not_contains "${RUN_OUTPUT}" "docfake" "list should no longer show the confirmed entry"

# ---- restore (command) ----
run_capture ${HELPER} start command refactorfake
assert_eq "0" "${RUN_STATUS}" "start should succeed for an existing command"
[[ ! -e "${HOME}/.claude/commands/refactorfake.md" ]] || fail_test "start should move the command file away"

run_capture ${HELPER} restore command refactorfake
assert_eq "0" "${RUN_STATUS}" "restore should succeed"
assert_contains "${RUN_OUTPUT}" "restored" "restore should report the restore"
[[ -f "${HOME}/.claude/commands/refactorfake.md" ]] || fail_test "restore should put the command file back"
compgen -G "${HOME}/.claude/commands/refactorfake.md.verify-bak.*" >/dev/null && fail_test "restore should consume the backup"

# ---- error: start on missing path ----
run_capture ${HELPER} start skill nonexistent
[[ "${RUN_STATUS}" != "0" ]] || fail_test "start should fail when skill is absent"
assert_contains "${RUN_OUTPUT}" "not found" "start should explain the missing path"

# ---- error: confirm without prior start ----
run_capture ${HELPER} confirm skill nonexistent
[[ "${RUN_STATUS}" != "0" ]] || fail_test "confirm should fail without a pending backup"
assert_contains "${RUN_OUTPUT}" "no pending backup" "confirm should explain why"

# ---- error: bad kind ----
run_capture ${HELPER} start badtype somename
[[ "${RUN_STATUS}" != "0" ]] || fail_test "start should reject unknown kind"
assert_contains "${RUN_OUTPUT}" "unknown kind" "error message should name the bad kind"

pass_test "tests/skill-verify.sh"
