#!/usr/bin/env bash
# tests/frontend-design-skill.sh — verify the vendored frontend-design skill.
#
# The skill is vendored from anthropics/claude-plugins-official (Apache-2.0)
# so chezmoi apply distributes it to every machine instead of relying on
# `/plugin install frontend-design@claude-plugins-official` being run manually.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

SKILL_DIR="${REPO_ROOT}/home/dot_claude/skills/frontend-design"
SKILL_FILE="${SKILL_DIR}/SKILL.md"
LICENSE_FILE="${SKILL_DIR}/LICENSE.txt"

[[ -f "${SKILL_FILE}" ]] || fail_test "SKILL.md missing at ${SKILL_FILE}"
[[ -f "${LICENSE_FILE}" ]] || fail_test "LICENSE.txt missing at ${LICENSE_FILE} (Apache-2.0 attribution required)"

skill_content="$(cat "${SKILL_FILE}")"
assert_contains "${skill_content}" "name: frontend-design" "SKILL.md frontmatter should declare name"
assert_contains "${skill_content}" "description:" "SKILL.md frontmatter should declare description"
assert_contains "${skill_content}" "Design Thinking" "SKILL.md should retain upstream content"

# Behavior check: the file must parse as valid YAML front-matter + Markdown.
# Claude Code loads skills by parsing the first --- ... --- block as YAML; a
# malformed vendored copy breaks skill discovery at runtime with no useful
# error. Validate structure here so the regression surfaces at test time.
python3 - "${SKILL_FILE}" <<'PY' || fail_test "SKILL.md front-matter does not parse"
import re
import sys

content = open(sys.argv[1]).read()
m = re.match(r'---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
if not m:
    sys.exit("SKILL.md does not start with a YAML front-matter fence")
fm = m.group(1)
# Minimal YAML-ish validation without pulling PyYAML: every non-blank line
# before the closing fence must look like `key: value` or a list continuation.
for line in fm.splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith('#'):
        continue
    if stripped.startswith('- '):
        continue
    if ':' not in stripped:
        sys.exit(f"front-matter line without colon: {stripped!r}")
if 'name:' not in fm or 'description:' not in fm:
    sys.exit("front-matter missing required 'name:' / 'description:' keys")
PY

license_content="$(cat "${LICENSE_FILE}")"
assert_contains "${license_content}" "Apache License" "LICENSE.txt should be Apache 2.0"

# doctor.sh must check for the skill so missing vendored files surface as a warning.
doctor_content="$(cat "${REPO_ROOT}/scripts/doctor.sh")"
assert_contains "${doctor_content}" "frontend-design/SKILL.md" "doctor.sh should probe the vendored skill"

pass_test "tests/frontend-design-skill.sh"
