#!/usr/bin/env bash
# tests/commands.sh — guard the Claude slash command bundle.
#
# Each file under home/dot_claude/commands/ becomes `/<name>` in Claude Code
# after chezmoi apply. Keep them substantive, non-empty, and listed in the
# README so forks can tell at a glance what's bundled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

COMMANDS_DIR="${REPO_ROOT}/home/dot_claude/commands"
[[ -d "${COMMANDS_DIR}" ]] || fail_test "commands dir missing: ${COMMANDS_DIR}"

shopt -s nullglob
commands=( "${COMMANDS_DIR}"/*.md )
shopt -u nullglob

if (( ${#commands[@]} < 10 )); then
  fail_test "expected >=10 slash commands, found ${#commands[@]}"
fi

readme="$(cat "${REPO_ROOT}/README.md")"

for cmd_file in "${commands[@]}"; do
  cmd_name="$(basename "${cmd_file}" .md)"

  # Every command must start with a non-empty first line (the one-liner description).
  first_line="$(head -1 "${cmd_file}")"
  if [[ -z "${first_line// }" ]]; then
    fail_test "${cmd_name}: first line is empty (must be one-line description)"
  fi

  # Minimum size: commands shorter than ~15 lines are probably stubs.
  line_count=$(wc -l < "${cmd_file}" | tr -d '[:space:]')
  if (( line_count < 15 )); then
    fail_test "${cmd_name}: only ${line_count} lines (minimum 15 for a real workflow guide)"
  fi

  # README must list the command. Fork users rely on this to discover what's bundled.
  if [[ "${readme}" != *"/${cmd_name}\`"* ]]; then
    fail_test "README.md does not list /${cmd_name} in the slash-commands table"
  fi
done

pass_test "tests/commands.sh"
