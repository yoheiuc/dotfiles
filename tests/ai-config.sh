#!/usr/bin/env bash
# tests/ai-config.sh — isolated unit tests for scripts/lib/ai-config.sh helpers.
#
# Covers:
#   - ai_config_json_remove_mcp           (delete path; previously only
#                                          exercised end-to-end via ai-repair.sh)
#   - ai_config_json_upsert_mcp           (overwrite-on-args-drift contract that
#                                          ai-repair.sh's _upsert_*_mcp relies on)
#   - ai_config_json_read_mcp_exists/_field (parameterized readers added 2026-04-28
#                                          to remove the eval injection surface)

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

# ---- ai_config_json_upsert_mcp (overwrite-on-drift) ------------------------

# 5. Re-upserting with new args replaces the entry wholesale. ai-repair.sh's
#    _upsert_stdio_mcp diffs args at the bash level; if upsert silently merged
#    instead of overwriting, drift wouldn't actually be repaired.
cat > "${tmpdir}/drift.json" <<'EOF'
{"mcpServers": {"vision": {"type": "stdio", "command": "npx", "args": ["-y", "@old/package"]}}}
EOF
ai_config_json_upsert_mcp "${tmpdir}/drift.json" vision \
  '{"type":"stdio","command":"npx","args":["-y","@new/package"]}' >/dev/null
content="$(cat "${tmpdir}/drift.json")"
assert_contains "${content}" '@new/package' "upsert_mcp should write the new args"
assert_not_contains "${content}" '@old/package' "upsert_mcp should not retain old args"

# 6. Re-upserting with new env replaces env keys (no merge with stale env).
cat > "${tmpdir}/env-drift.json" <<'EOF'
{"mcpServers": {"vision": {"type": "stdio", "command": "npx", "args": ["-y"], "env": {"OLD_KEY": "1"}}}}
EOF
ai_config_json_upsert_mcp "${tmpdir}/env-drift.json" vision \
  '{"type":"stdio","command":"npx","args":["-y"],"env":{"NEW_KEY":"2"}}' >/dev/null
content="$(cat "${tmpdir}/env-drift.json")"
assert_contains "${content}" 'NEW_KEY' "upsert_mcp should write the new env keys"
assert_not_contains "${content}" 'OLD_KEY' "upsert_mcp should not retain old env keys"

# ---- ai_config_json_read_mcp_exists ----------------------------------------

cat > "${tmpdir}/mcp.json" <<'EOF'
{"mcpServers": {
  "exa":  {"type": "http",  "url": "https://example.com/exa"},
  "seq":  {"type": "stdio", "command": "npx", "args": ["-y", "@m/seq"]}
}}
EOF

# 7. Existing name → "present", exit 0.
result="$(ai_config_json_read_mcp_exists "${tmpdir}/mcp.json" exa)"
assert_eq "present" "${result}" "read_mcp_exists should print 'present' for existing entry"

# 8. Missing name → exit 1, no output.
set +e
output="$(ai_config_json_read_mcp_exists "${tmpdir}/mcp.json" nope 2>/dev/null)"
status=$?
set -e
assert_eq "1" "${status}" "read_mcp_exists should exit 1 for missing entry"
assert_eq "" "${output}" "read_mcp_exists should print nothing for missing entry"

# 9. Missing file → exit 1.
set +e
ai_config_json_read_mcp_exists "${tmpdir}/no-such-file.json" exa >/dev/null 2>&1
status=$?
set -e
assert_eq "1" "${status}" "read_mcp_exists should exit 1 for missing file"

# 10. Name lookup is exact — no eval / glob / prefix matching. Confirms that the
#     callers' shell-interpolated $name can never be re-interpreted as code.
set +e
output="$(ai_config_json_read_mcp_exists "${tmpdir}/mcp.json" "exa'); print('hi" 2>/dev/null)"
status=$?
set -e
assert_eq "1" "${status}" "read_mcp_exists should treat name as a literal key (no eval)"
assert_eq "" "${output}" "read_mcp_exists must not echo injected payload"

# ---- ai_config_json_read_mcp_field -----------------------------------------

# 11. Scalar fields print as-is.
result="$(ai_config_json_read_mcp_field "${tmpdir}/mcp.json" exa url)"
assert_eq "https://example.com/exa" "${result}" "read_mcp_field should print scalar as-is"

result="$(ai_config_json_read_mcp_field "${tmpdir}/mcp.json" seq command)"
assert_eq "npx" "${result}" "read_mcp_field should print stdio command"

# 12. Array fields are pipe-joined to match _upsert_stdio_mcp's diff format.
result="$(ai_config_json_read_mcp_field "${tmpdir}/mcp.json" seq args)"
assert_eq "-y|@m/seq" "${result}" "read_mcp_field should pipe-join array values"

# 13. Missing field → exit 1.
set +e
output="$(ai_config_json_read_mcp_field "${tmpdir}/mcp.json" exa command 2>/dev/null)"
status=$?
set -e
assert_eq "1" "${status}" "read_mcp_field should exit 1 when field missing"
assert_eq "" "${output}" "read_mcp_field should print nothing when field missing"

pass_test "tests/ai-config.sh"
