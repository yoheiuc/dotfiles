#!/usr/bin/env bash

set -euo pipefail

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass_test() {
  printf 'PASS: %s\n' "$*"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-expected ${expected}, got ${actual}}"

  if [[ "${expected}" != "${actual}" ]]; then
    fail_test "${message}"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-expected output to contain ${needle}}"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    printf -- '--- output ---\n%s\n--------------\n' "${haystack}" >&2
    fail_test "${message}"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-expected output not to contain ${needle}}"

  if [[ "${haystack}" == *"${needle}"* ]]; then
    printf -- '--- output ---\n%s\n--------------\n' "${haystack}" >&2
    fail_test "${message}"
  fi
}

run_capture() {
  set +e
  # shellcheck disable=SC2034
  RUN_OUTPUT="$("$@" 2>&1)"
  # shellcheck disable=SC2034
  RUN_STATUS=$?
  set -e
}

# Write a fixture ~/.claude/plugins/installed_plugins.json under $target_home
# (or $HOME if omitted) listing every plugin in CLAUDE_LSP_PLUGINS +
# CLAUDE_GENERAL_PLUGINS as installed. Sources scripts/lib/claude-plugins.sh
# so the stub stays accurate as the expected lists evolve.
#
# Usage:  write_installed_plugins_stub [target_home]
write_installed_plugins_stub() {
  local target_home="${1:-${HOME}}"
  local repo_root="${REPO_ROOT:?REPO_ROOT must be set by the test}"
  # shellcheck source=/dev/null
  source "${repo_root}/scripts/lib/claude-plugins.sh"
  mkdir -p "${target_home}/.claude/plugins"
  python3 - <<PY > "${target_home}/.claude/plugins/installed_plugins.json"
import json
plugins = {}
for name in "${CLAUDE_LSP_PLUGINS[*]} ${CLAUDE_GENERAL_PLUGINS[*]}".split():
    plugins[f"{name}@${CLAUDE_PLUGIN_MARKETPLACE_NAME}"] = {}
print(json.dumps({"plugins": plugins}, indent=2))
PY
}
