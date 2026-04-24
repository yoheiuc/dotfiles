#!/usr/bin/env bash
# tests/ai-config.sh — isolated unit tests for scripts/lib/ai-config.sh helpers.
#
# Focus: ai_config_json_remove_mcp, since it's only exercised end-to-end via
# ai-repair.sh today.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-config-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

# ---- ai_config_json_remove_mcp ---------------------------------------------

# 1. Missing file → "absent", no error.
result="$(ai_config_json_remove_mcp "${tmpdir}/no-such-file.json" foo 2>/dev/null || true)"
assert_eq "absent" "${result}" "remove_mcp should report 'absent' for missing file"

# 2. File without the key → "absent".
cat > "${tmpdir}/empty.json" <<'EOF'
{"mcpServers": {"keep": {"type": "http", "url": "https://example.com"}}}
EOF
result="$(ai_config_json_remove_mcp "${tmpdir}/empty.json" foo)"
assert_eq "absent" "${result}" "remove_mcp should report 'absent' when key not present"
assert_contains "$(cat "${tmpdir}/empty.json")" '"keep"' "remove_mcp should not touch other entries when key absent"

# 3. File with the key → "removed", siblings preserved.
cat > "${tmpdir}/with-target.json" <<'EOF'
{"mcpServers": {
  "drop": {"type": "stdio", "command": "x"},
  "keep": {"type": "http", "url": "https://example.com"}
}}
EOF
result="$(ai_config_json_remove_mcp "${tmpdir}/with-target.json" drop)"
assert_eq "removed" "${result}" "remove_mcp should report 'removed' when key was present"
content="$(cat "${tmpdir}/with-target.json")"
assert_not_contains "${content}" '"drop"' "remove_mcp should strip the target key"
assert_contains "${content}" '"keep"' "remove_mcp should preserve sibling keys"

# 4. File with no mcpServers section at all → "absent", file untouched.
cat > "${tmpdir}/no-section.json" <<'EOF'
{"otherKey": 1}
EOF
result="$(ai_config_json_remove_mcp "${tmpdir}/no-section.json" foo)"
assert_eq "absent" "${result}" "remove_mcp should report 'absent' when mcpServers missing"
assert_contains "$(cat "${tmpdir}/no-section.json")" '"otherKey": 1' "remove_mcp should not corrupt JSON when no mcpServers"

pass_test "tests/ai-config.sh"
