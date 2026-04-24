#!/usr/bin/env bash
# skill-verify.sh — A/B test helper for verifying that a user-vendored skill
# or slash command can be replaced by its bundled counterpart.
#
# Motivation: dotfiles issues #63 / #64 documented that description-match does
# NOT guarantee bundled-match. We only want to delete a vendored copy after
# manually confirming that the bundled version behaves the same in a fresh
# Claude Code session.
#
# Workflow:
#
#   1. ./scripts/skill-verify.sh start skill doc
#      → renames ~/.claude/skills/doc to doc.verify-bak.<timestamp>, records
#        the rename under ~/.claude/skills/.verify-log.tsv
#
#   2. Open a new Claude Code session and exercise the skill / command:
#      - For a skill: run a task that would normally trigger the skill.
#      - For a command: invoke /<name> and confirm the bundled fallback works.
#
#   3a. ./scripts/skill-verify.sh confirm skill doc
#       → deletes the .verify-bak copy (user has verified bundled works).
#
#   3b. ./scripts/skill-verify.sh restore skill doc
#       → moves the .verify-bak copy back (bundled differs — keep the vendored).
#
#   ./scripts/skill-verify.sh list
#       → shows pending renames so you don't forget to resolve them.
#
# Usage:
#   ./scripts/skill-verify.sh start   {skill|command} <name>
#   ./scripts/skill-verify.sh confirm {skill|command} <name>
#   ./scripts/skill-verify.sh restore {skill|command} <name>
#   ./scripts/skill-verify.sh list

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/lib/ui.sh"

LOG_FILE="${HOME}/.claude/.verify-log.tsv"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
}

require_kind() {
  case "$1" in
    skill|command) return 0 ;;
    *) printf 'skill-verify: unknown kind: %s (expected skill|command)\n' "$1" >&2; exit 64 ;;
  esac
}

kind_dir() {
  case "$1" in
    skill)   printf '%s/.claude/skills' "${HOME}" ;;
    command) printf '%s/.claude/commands' "${HOME}" ;;
  esac
}

# For skills the target is a directory (…/skills/<name>/). For commands it is
# a single file (…/commands/<name>.md).
kind_path() {
  local kind="$1" name="$2"
  case "${kind}" in
    skill)   printf '%s/%s' "$(kind_dir "${kind}")" "${name}" ;;
    command) printf '%s/%s.md' "$(kind_dir "${kind}")" "${name}" ;;
  esac
}

log_append() {
  local kind="$1" name="$2" original="$3" backup="$4"
  mkdir -p "$(dirname "${LOG_FILE}")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "${kind}" "${name}" "${original}" "${backup}" >> "${LOG_FILE}"
}

log_remove() {
  local backup="$1"
  [[ -f "${LOG_FILE}" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk -F '\t' -v b="${backup}" '$5 != b' "${LOG_FILE}" > "${tmp}"
  mv "${tmp}" "${LOG_FILE}"
}

cmd_start() {
  local kind="$1" name="$2"
  require_kind "${kind}"
  local target
  target="$(kind_path "${kind}" "${name}")"
  if [[ ! -e "${target}" ]]; then
    printf 'skill-verify: not found: %s\n' "${target}" >&2
    exit 2
  fi
  if [[ "${target}" == *.verify-bak.* ]]; then
    printf 'skill-verify: already a backup path: %s\n' "${target}" >&2
    exit 2
  fi
  local stamp backup
  stamp="$(date +%Y%m%d%H%M%S)"
  backup="${target}.verify-bak.${stamp}"
  mv "${target}" "${backup}"
  log_append "${kind}" "${name}" "${target}" "${backup}"
  section "A/B test started"
  ok "renamed  ${target/#${HOME}/\~}"
  ok "     to  ${backup/#${HOME}/\~}"
  info "Open a new Claude Code session and exercise the bundled ${kind}."
  info "Then run: ./scripts/skill-verify.sh {confirm|restore} ${kind} ${name}"
}

# Find the most recent backup for the given kind+name. `ls -d` keeps
# directories as themselves (skills are directories); without -d ls would
# enumerate their contents.
find_backup() {
  local kind="$1" name="$2"
  local target
  target="$(kind_path "${kind}" "${name}")"
  ls -1td "${target}.verify-bak."* 2>/dev/null | head -1
}

cmd_confirm() {
  local kind="$1" name="$2"
  require_kind "${kind}"
  local backup
  backup="$(find_backup "${kind}" "${name}" || true)"
  if [[ -z "${backup}" ]]; then
    printf 'skill-verify: no pending backup for %s/%s\n' "${kind}" "${name}" >&2
    exit 2
  fi
  rm -rf "${backup}"
  log_remove "${backup}"
  section "A/B test confirmed"
  ok "deleted ${backup/#${HOME}/\~}"
  info "Next: git rm the vendored source under home/dot_claude/${kind}s/ and commit."
}

cmd_restore() {
  local kind="$1" name="$2"
  require_kind "${kind}"
  local backup target
  backup="$(find_backup "${kind}" "${name}" || true)"
  if [[ -z "${backup}" ]]; then
    printf 'skill-verify: no pending backup for %s/%s\n' "${kind}" "${name}" >&2
    exit 2
  fi
  target="$(kind_path "${kind}" "${name}")"
  if [[ -e "${target}" ]]; then
    printf 'skill-verify: destination already exists: %s\n' "${target}" >&2
    exit 2
  fi
  mv "${backup}" "${target}"
  log_remove "${backup}"
  section "A/B test restored"
  ok "restored ${target/#${HOME}/\~}"
  info "Bundled differs from the vendored copy — keep the user version."
}

cmd_list() {
  section "Pending A/B renames"
  if [[ ! -f "${LOG_FILE}" ]]; then
    info "(none)"
    return
  fi
  local printed=0
  while IFS=$'\t' read -r ts kind name original backup; do
    [[ -n "${backup:-}" ]] || continue
    [[ -e "${backup}" ]] || continue
    printf '  %s  %-7s  %s\n' "${ts}" "${kind}" "${name}"
    printf '      backup: %s\n' "${backup/#${HOME}/\~}"
    printed=1
  done < "${LOG_FILE}"
  if [[ "${printed}" -eq 0 ]]; then
    info "(none)"
  fi
}

if [[ "$#" -eq 0 ]]; then
  usage
fi

case "${1:-}" in
  start)   [[ "$#" -eq 3 ]] || usage; cmd_start   "$2" "$3" ;;
  confirm) [[ "$#" -eq 3 ]] || usage; cmd_confirm "$2" "$3" ;;
  restore) [[ "$#" -eq 3 ]] || usage; cmd_restore "$2" "$3" ;;
  list)    [[ "$#" -eq 1 ]] || usage; cmd_list ;;
  -h|--help|help) usage ;;
  *) usage ;;
esac
