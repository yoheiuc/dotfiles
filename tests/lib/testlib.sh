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
