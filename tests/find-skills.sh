#!/usr/bin/env bash
# tests/find-skills.sh — guard the cross-file integration of the find-skills skill.
#
# find-skills (vercel-labs/skills) lets Claude Code search available skills
# from natural-language queries. It follows the same CLI-distributed skill
# pattern as gws and notion-cli, per the project CLAUDE.md "外部 CLI で配布
# される skill" rule. Touching any of the following surfaces without updating
# the rest leaves new machines out of sync:
#   - scripts/post-setup.sh   (npx skills add install block)
#   - scripts/doctor.sh       (Claude Code skill presence check)
#   - home/dot_claude/CLAUDE.md (routing so the agent uses it first)
#
# This test is a thin presence-check; it does NOT exercise `npx skills` itself.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

post_setup="$(cat "${REPO_ROOT}/scripts/post-setup.sh")"
assert_contains "${post_setup}" "vercel-labs/skills" "post-setup.sh should install find-skills from vercel-labs/skills"
assert_contains "${post_setup}" "--skill find-skills" "post-setup.sh should pin the --skill find-skills argument"
assert_contains "${post_setup}" "find-skills/SKILL.md" "post-setup.sh should skip when find-skills is already installed"

doctor="$(cat "${REPO_ROOT}/scripts/doctor.sh")"
assert_contains "${doctor}" ".claude/skills/find-skills/SKILL.md" "doctor.sh should probe the Claude Code find-skills skill"

claude_routing="$(cat "${REPO_ROOT}/home/dot_claude/CLAUDE.md")"
assert_contains "${claude_routing}" "find-skills" "home/dot_claude/CLAUDE.md should route Claude to find-skills when no matching skill is known"

# Behavior check: the post-setup install block must actually be idempotent.
# Verify both branches exist — "already present" (skip) and fresh-install —
# and that the install targets live under $HOME (not the dotfiles checkout).
assert_contains "${post_setup}" '"${HOME}/.claude/skills"' "post-setup.sh should install find-skills under \$HOME/.claude/skills"
assert_contains "${post_setup}" "already present" "post-setup.sh should have an idempotent skip branch"

pass_test "tests/find-skills.sh"
