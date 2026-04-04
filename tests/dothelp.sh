#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-help-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

fake_repo="${tmpdir}/repo"
mkdir -p "${fake_repo}/scripts" "${tmpdir}/home/.config/dotfiles"
cp "${REPO_ROOT}/scripts/dotfiles-help.sh" "${fake_repo}/scripts/dotfiles-help.sh"
cp "${REPO_ROOT}/scripts/profile.sh" "${fake_repo}/scripts/profile.sh"
chmod +x "${fake_repo}/scripts/dotfiles-help.sh" "${fake_repo}/scripts/profile.sh"

export DOTFILES_REPO_ROOT="${fake_repo}"
export HOME="${tmpdir}/home"
printf 'home\n' > "${HOME}/.config/dotfiles/profile"

run_capture bash "${fake_repo}/scripts/dotfiles-help.sh"
assert_eq "0" "${RUN_STATUS}" "dotfiles-help should succeed"
assert_contains "${RUN_OUTPUT}" "Active profile: home" "dotfiles-help should print the active profile"
assert_contains "${RUN_OUTPUT}" "make sync-home" "dotfiles-help should show sync-home"
assert_contains "${RUN_OUTPUT}" "make brew-add-core KIND=brew NAME=jq" "dotfiles-help should show brew add examples"
assert_contains "${RUN_OUTPUT}" "dothelp" "dotfiles-help should mention the shell helper"

pass_test "tests/dothelp.sh"
