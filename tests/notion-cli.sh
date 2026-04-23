#!/usr/bin/env bash
# tests/notion-cli.sh — guard the cross-file integration of the ntn (Notion CLI).
#
# The ntn CLI must be wired into the same surfaces that playwright-cli is, per
# the project CLAUDE.md "CLI 系ツールを追加するときは…" rule:
#   - scripts/post-setup.sh   (install + skill placement)
#   - scripts/doctor.sh       (version check)
#   - scripts/status.sh       (daily status section)
#   - home/dot_local/share/navi/cheats/dotfiles/notion.cheat
#   - home/dot_claude/CLAUDE.md / home/AGENTS.md routing tables
# This test is a thin presence-check; it does NOT exercise ntn itself.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

cheat="${REPO_ROOT}/home/dot_local/share/navi/cheats/dotfiles/notion.cheat"
[[ -f "${cheat}" ]] || fail_test "navi cheat missing: ${cheat}"
cheat_body="$(cat "${cheat}")"
assert_contains "${cheat_body}" "ntn login" "notion.cheat should document ntn login"
assert_contains "${cheat_body}" "ntn block list" "notion.cheat should document Markdown read"
assert_contains "${cheat_body}" "ntn block append" "notion.cheat should document Markdown append"
assert_contains "${cheat_body}" "NOTION_API_TOKEN" "notion.cheat should mention env-var auth for CI"

post_setup="$(cat "${REPO_ROOT}/scripts/post-setup.sh")"
assert_contains "${post_setup}" "https://ntn.dev" "post-setup.sh should run the ntn installer"
assert_contains "${post_setup}" "makenotion/skills" "post-setup.sh should install the notion-cli skill from makenotion/skills"

doctor="$(cat "${REPO_ROOT}/scripts/doctor.sh")"
assert_contains "${doctor}" "ntn (Notion CLI" "doctor.sh should have a ntn section"
assert_contains "${doctor}" "command -v ntn" "doctor.sh should probe for ntn"

status="$(cat "${REPO_ROOT}/scripts/status.sh")"
assert_contains "${status}" "Notion CLI" "status.sh should report a Notion CLI section"
assert_contains "${status}" "command -v ntn" "status.sh should probe for ntn"

claude_routing="$(cat "${REPO_ROOT}/home/dot_claude/CLAUDE.md")"
assert_contains "${claude_routing}" "ntn" "home/dot_claude/CLAUDE.md routing table should mention ntn"

codex_routing="$(cat "${REPO_ROOT}/home/AGENTS.md")"
assert_contains "${codex_routing}" "ntn" "home/AGENTS.md routing table should mention ntn"
assert_contains "${codex_routing}" "notion-cli" "home/AGENTS.md skill table should list notion-cli"

# Behavior check: the notion-cli install block in post-setup must have an
# idempotent skip branch. Without it, `make install` on an already-configured
# machine would re-run `npx skills add` and trip the network.
assert_contains "${post_setup}" "notion-cli/SKILL.md" "post-setup.sh should check for an existing notion-cli skill before re-installing"
assert_contains "${post_setup}" "notion-cli skill already present" "post-setup.sh should have an idempotent skip branch for notion-cli"

# The navi cheat file must have valid navi structure: a `%` tag header and at
# least a handful of real command lines. Catches accidental truncation to a
# blank stub.
pct_lines=$(grep -c '^%' "${cheat}" || true)
# Count lines that are not blank, not a comment (#), and not a tag (%).
cmd_lines=$(grep -cEv '^[[:space:]]*(#|%|$)' "${cheat}" || true)
if (( pct_lines < 1 )) || (( cmd_lines < 5 )); then
  fail_test "notion.cheat must have >=1 tag line and >=5 command lines (got tags: ${pct_lines}, cmds: ${cmd_lines})"
fi

pass_test "tests/notion-cli.sh"
