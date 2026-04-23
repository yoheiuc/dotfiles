#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-help-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

fake_repo="${tmpdir}/repo"
mkdir -p "${fake_repo}/scripts" "${tmpdir}/home"
cp "${REPO_ROOT}/scripts/dotfiles-help.sh" "${fake_repo}/scripts/dotfiles-help.sh"
chmod +x "${fake_repo}/scripts/dotfiles-help.sh"

export DOTFILES_REPO_ROOT="${fake_repo}"
export HOME="${tmpdir}/home"

run_capture bash "${fake_repo}/scripts/dotfiles-help.sh"
assert_eq "0" "${RUN_STATUS}" "dotfiles-help should succeed"
assert_contains "${RUN_OUTPUT}" "make status" "dotfiles-help should show daily commands"
assert_contains "${RUN_OUTPUT}" "make sync" "dotfiles-help should show sync"
assert_contains "${RUN_OUTPUT}" "dothelp" "dotfiles-help should mention the shell helper"

# Behavior check: the help output must be substantive, not an empty file or a
# no-op stub. If someone accidentally truncates dotfiles-help.sh to `exit 0`,
# the grep assertions above would still pass against the ANSI escape prefix —
# this line catches that by requiring a minimum number of non-empty lines.
line_count=$(printf '%s' "${RUN_OUTPUT}" | grep -c .)
if (( line_count < 8 )); then
  printf -- '--- output ---\n%s\n--------------\n' "${RUN_OUTPUT}" >&2
  fail_test "dotfiles-help output should have >=8 non-empty lines (got ${line_count})"
fi

pass_test "tests/dothelp.sh"
