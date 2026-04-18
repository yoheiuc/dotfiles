#!/usr/bin/env bash
# tests/ai-config.sh — isolated unit tests for scripts/lib/ai-config.sh helpers.
#
# Focus: ai_config_json_remove_mcp / ai_config_toml_remove_mcp_section, since
# they're only exercised end-to-end via ai-repair.sh today and the regex used
# to strip [mcp_servers.<name>.tools.*] subsections is brittle enough to want
# direct coverage.

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

# ---- ai_config_toml_remove_mcp_section --------------------------------------

# 5. Missing file → "absent".
result="$(ai_config_toml_remove_mcp_section "${tmpdir}/no-such-file.toml" foo 2>/dev/null || true)"
assert_eq "absent" "${result}" "toml remove should report 'absent' for missing file"

# 6. Section absent → "absent", file untouched.
cat > "${tmpdir}/no-target.toml" <<'EOF'
model = "gpt-5.4"

[mcp_servers.keep]
url = "https://example.com"
EOF
before="$(cat "${tmpdir}/no-target.toml")"
result="$(ai_config_toml_remove_mcp_section "${tmpdir}/no-target.toml" drop)"
assert_eq "absent" "${result}" "toml remove should report 'absent' when section missing"
assert_eq "${before}" "$(cat "${tmpdir}/no-target.toml")" "toml remove should not touch file when section missing"

# 7. Single section removed → "removed", other sections preserved.
cat > "${tmpdir}/single.toml" <<'EOF'
model = "gpt-5.4"

[mcp_servers.keep]
url = "https://keep.example.com"

[mcp_servers.drop]
command = "npx"
args = ["-y", "@some/pkg"]

[mcp_servers.also_keep]
url = "https://also.example.com"
EOF
result="$(ai_config_toml_remove_mcp_section "${tmpdir}/single.toml" drop)"
assert_eq "removed" "${result}" "toml remove should report 'removed' for single matching section"
content="$(cat "${tmpdir}/single.toml")"
assert_not_contains "${content}" '[mcp_servers.drop]' "toml remove should strip the target section header"
assert_not_contains "${content}" '@some/pkg' "toml remove should strip the target section body"
assert_contains "${content}" '[mcp_servers.keep]' "toml remove should preserve other sections (above)"
assert_contains "${content}" '[mcp_servers.also_keep]' "toml remove should preserve other sections (below)"

# 8. Section + child .tools.* subsections removed (the playwright pattern).
cat > "${tmpdir}/with-children.toml" <<'EOF'
[mcp_servers.keep]
url = "https://keep.example.com"

[mcp_servers.drop]
command = "npx"
args = ["-y", "@some/pkg"]

[mcp_servers.drop.tools.foo_bar]
approval_mode = "approve"

[mcp_servers.drop.tools.baz_qux]
approval_mode = "approve"

[mcp_servers.tail_keep]
url = "https://tail.example.com"
EOF
result="$(ai_config_toml_remove_mcp_section "${tmpdir}/with-children.toml" drop)"
assert_eq "removed" "${result}" "toml remove should report 'removed' when children present"
content="$(cat "${tmpdir}/with-children.toml")"
assert_not_contains "${content}" '[mcp_servers.drop]' "toml remove should strip parent section"
assert_not_contains "${content}" '[mcp_servers.drop.tools.foo_bar]' "toml remove should strip child .tools.* subsection"
assert_not_contains "${content}" '[mcp_servers.drop.tools.baz_qux]' "toml remove should strip all child .tools.* subsections"
assert_contains "${content}" '[mcp_servers.keep]' "toml remove should preserve sibling above"
assert_contains "${content}" '[mcp_servers.tail_keep]' "toml remove should preserve sibling below"

# 9. Section as the LAST in file → file ends cleanly.
cat > "${tmpdir}/last.toml" <<'EOF'
[mcp_servers.keep]
url = "https://keep.example.com"

[mcp_servers.drop]
command = "x"
EOF
result="$(ai_config_toml_remove_mcp_section "${tmpdir}/last.toml" drop)"
assert_eq "removed" "${result}" "toml remove should handle last-in-file section"
content="$(cat "${tmpdir}/last.toml")"
assert_not_contains "${content}" '[mcp_servers.drop]' "toml remove should strip last section"
# File must end with exactly one trailing newline (no truncation, no double-newline mess).
trailing_bytes="$(tail -c 1 "${tmpdir}/last.toml" | od -An -c | tr -d ' ')"
assert_eq '\n' "${trailing_bytes}" "toml remove should leave exactly one trailing newline"

# 10. Section name with hyphen (chrome-devtools-style) — re.escape coverage.
cat > "${tmpdir}/hyphen.toml" <<'EOF'
[mcp_servers.chrome-devtools]
command = "npx"

[mcp_servers.keep]
url = "https://example.com"
EOF
result="$(ai_config_toml_remove_mcp_section "${tmpdir}/hyphen.toml" chrome-devtools)"
assert_eq "removed" "${result}" "toml remove should handle hyphenated section names"
assert_not_contains "$(cat "${tmpdir}/hyphen.toml")" '[mcp_servers.chrome-devtools]' "toml remove should strip hyphenated section"

# 11. Idempotent removal: second call on already-removed section returns "absent".
result="$(ai_config_toml_remove_mcp_section "${tmpdir}/hyphen.toml" chrome-devtools)"
assert_eq "absent" "${result}" "toml remove should be idempotent (no-op on second call)"

pass_test "tests/ai-config.sh"
