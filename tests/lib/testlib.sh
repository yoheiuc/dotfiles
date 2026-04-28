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
# CLAUDE_GENERAL_PLUGINS (claude-plugins-official) and CLAUDE_DOCUMENT_PLUGINS
# (anthropic-agent-skills) as installed. Sources scripts/lib/claude-plugins.sh
# so the stub stays accurate as the expected lists evolve.
#
# Plugin / marketplace names are passed to Python via env vars (newline-
# separated for arrays) so quoting / special chars in upstream plugin names
# can never break the heredoc — pasting the bash arrays straight into a Python
# string would interpolate at shell level and shred JSON on any name with `"`,
# `\`, or newline. Doesn't matter for today's plugin list, but the stub feeds
# every test that touches plugin state, so harden once. Newline separator
# (not NUL) because bash command substitution strips embedded NULs.
#
# Usage:  write_installed_plugins_stub [target_home]
write_installed_plugins_stub() {
  local target_home="${1:-${HOME}}"
  local repo_root="${REPO_ROOT:?REPO_ROOT must be set by the test}"
  # shellcheck source=/dev/null
  source "${repo_root}/scripts/lib/claude-plugins.sh"
  mkdir -p "${target_home}/.claude/plugins"

  local primary_names doc_names
  primary_names="$(printf '%s\n' "${CLAUDE_LSP_PLUGINS[@]}" "${CLAUDE_GENERAL_PLUGINS[@]}")"
  doc_names="$(printf '%s\n' "${CLAUDE_DOCUMENT_PLUGINS[@]}")"

  STUB_PRIMARY_NAMES="${primary_names}" \
  STUB_DOC_NAMES="${doc_names}" \
  STUB_PRIMARY_MARKETPLACE="${CLAUDE_PLUGIN_MARKETPLACE_NAME}" \
  STUB_DOC_MARKETPLACE="${CLAUDE_DOCUMENT_MARKETPLACE_NAME}" \
  python3 - > "${target_home}/.claude/plugins/installed_plugins.json" <<'PY'
import json
import os


def _split(env_name: str) -> list[str]:
    return [s for s in os.environ.get(env_name, "").splitlines() if s]


plugins: dict[str, dict] = {}
primary_marketplace = os.environ["STUB_PRIMARY_MARKETPLACE"]
doc_marketplace = os.environ["STUB_DOC_MARKETPLACE"]
for name in _split("STUB_PRIMARY_NAMES"):
    plugins[f"{name}@{primary_marketplace}"] = {}
for name in _split("STUB_DOC_NAMES"):
    plugins[f"{name}@{doc_marketplace}"] = {}
print(json.dumps({"plugins": plugins}, indent=2))
PY
}
