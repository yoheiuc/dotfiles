#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-profile-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

export HOME="${tmpdir}/home"
mkdir -p "${HOME}"

profile_file="${HOME}/.config/dotfiles/profile"

run_capture bash "${REPO_ROOT}/scripts/profile.sh" get
assert_eq "0" "${RUN_STATUS}" "profile get should succeed when file is missing"
assert_eq "core" "${RUN_OUTPUT}" "profile get should default to core"

if bash "${REPO_ROOT}/scripts/profile.sh" exists; then
  fail_test "profile exists should fail when no profile file is present"
fi

run_capture bash "${REPO_ROOT}/scripts/profile.sh" set home
assert_eq "0" "${RUN_STATUS}" "profile set home should succeed"
assert_eq "home" "${RUN_OUTPUT}" "profile set home should print canonical value"
assert_eq "home" "$(tr -d '[:space:]' < "${profile_file}")" "profile file should persist home"

mkdir -p "$(dirname "${profile_file}")"
printf 'personal\n' > "${profile_file}"
run_capture bash "${REPO_ROOT}/scripts/profile.sh" get
assert_eq "0" "${RUN_STATUS}" "profile get should migrate legacy personal profile"
assert_eq "home" "${RUN_OUTPUT}" "legacy personal profile should be canonicalized to home"
assert_eq "home" "$(tr -d '[:space:]' < "${profile_file}")" "legacy personal profile should be rewritten in place"

printf 'work\n' > "${profile_file}"
run_capture bash "${REPO_ROOT}/scripts/profile.sh" get
assert_eq "0" "${RUN_STATUS}" "profile get should migrate legacy work profile"
assert_eq "core" "${RUN_OUTPUT}" "legacy work profile should be canonicalized to core"
assert_eq "core" "$(tr -d '[:space:]' < "${profile_file}")" "legacy work profile should be rewritten in place"

run_capture bash "${REPO_ROOT}/scripts/profile.sh" set all
assert_eq "1" "${RUN_STATUS}" "legacy all profile should fail"
assert_contains "${RUN_OUTPUT}" "Legacy profile 'all' is no longer supported" "legacy all profile should explain migration"

pass_test "tests/profile.sh"
