#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-audit-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/home/.codex" "${tmpdir}/home/.claude" "${tmpdir}/home/.gemini" "${tmpdir}/home/.serena"
mkdir -p "${tmpdir}/scripts/lib"
mkdir -p "${tmpdir}/bin"
export HOME="${tmpdir}/home"
export PATH="${tmpdir}/bin:${PATH}"

cp "${REPO_ROOT}/scripts/ai-audit.sh" "${tmpdir}/scripts/ai-audit.sh"
cp "${REPO_ROOT}/scripts/lib/ai-config.sh" "${tmpdir}/scripts/lib/ai-config.sh"
chmod +x "${tmpdir}/scripts/ai-audit.sh" "${tmpdir}/scripts/lib/ai-config.sh"

cat > "${tmpdir}/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  mcp)
    if [[ "${2:-}" == "list" ]]; then
      printf '%s' "${CLAUDE_MCP_LIST_OUTPUT:-}"
      exit "${CLAUDE_MCP_LIST_STATUS:-0}"
    fi
    ;;
esac

exit 1
EOF

cat > "${tmpdir}/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  mcp)
    if [[ "${2:-}" == "list" ]]; then
      printf '%s' "${CODEX_MCP_LIST_OUTPUT:-}"
      exit "${CODEX_MCP_LIST_STATUS:-0}"
    fi
    ;;
esac

exit 1
EOF

chmod +x "${tmpdir}/bin/claude" "${tmpdir}/bin/codex"

cat > "${HOME}/.codex/config.toml" <<'EOF'
model = "gpt-5.4"
EOF
: > "${HOME}/.claude/settings.json"
: > "${HOME}/.gemini/settings.json"
: > "${HOME}/.codex/hooks.json"
: > "${HOME}/.claude/CLAUDE.md"
: > "${HOME}/AGENTS.md"
cat > "${HOME}/.serena/serena_config.yml" <<'EOF'
language_backend: LSP
web_dashboard: true
web_dashboard_open_on_launch: false
project_serena_folder_location: "$projectDir/.serena"
EOF

run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should succeed in the clean case"
assert_contains "${RUN_OUTPUT}" "Codex config: present" "ai-audit should report local codex config"
assert_contains "${RUN_OUTPUT}" "Claude settings: present" "ai-audit should report local claude settings"
assert_contains "${RUN_OUTPUT}" "Codex config: no legacy bridge settings detected" "ai-audit should scan codex config"
assert_contains "${RUN_OUTPUT}" "Serena config: web_dashboard enabled" "ai-audit should validate Serena config"
assert_contains "${RUN_OUTPUT}" "Claude Code Serena MCP: missing" "ai-audit should report missing Claude MCP registration"
assert_contains "${RUN_OUTPUT}" "Codex Serena MCP: missing" "ai-audit should report missing Codex MCP registration"
assert_contains "${RUN_OUTPUT}" "AI config audit needs attention:" "ai-audit should summarize MCP registration warnings"

cat > "${HOME}/.codex/config.toml" <<'EOF'
# --- BEGIN CCB ---
approval_policy = "never"
sandbox_mode = "danger-full-access"
EOF
printf 'cc-bridge\n' > "${HOME}/.claude/settings.json"
rm -f "${HOME}/.gemini/settings.json"
: > "${HOME}/.codex/config.toml.pre-unmanage-test"
cat > "${HOME}/.serena/serena_config.yml" <<'EOF'
language_backend: JetBrains
web_dashboard: false
web_dashboard_open_on_launch: true
project_serena_folder_location: "/tmp/serena"
EOF
cat > "${HOME}/.claude.json" <<'EOF'
{
  "mcpServers": {
    "serena": {
      "command": "/Users/example/.local/bin/serena-mcp",
      "args": ["claude-code"]
    }
  }
}
EOF

run_capture env \
  CLAUDE_MCP_LIST_OUTPUT=$'Timed out after 15s\n' \
  CLAUDE_MCP_LIST_STATUS=124 \
  CODEX_MCP_LIST_OUTPUT=$'Name    Command  Args   Env  Cwd  Status   Auth\nserena  uvx      --from git+https://github.com/oraios/serena serena start-mcp-server --context=codex --project-from-cwd --open-web-dashboard False  -    -    enabled  Unsupported\n' \
  bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should stay informational with warnings"
assert_contains "${RUN_OUTPUT}" "Gemini settings: missing" "ai-audit should warn on missing gemini settings"
assert_contains "${RUN_OUTPUT}" "Codex config: legacy bridge or unsafe approval settings detected" "ai-audit should detect legacy codex settings"
assert_contains "${RUN_OUTPUT}" "Claude settings: legacy bridge or unsafe approval settings detected" "ai-audit should detect legacy claude settings"
assert_contains "${RUN_OUTPUT}" "Serena config: language_backend should be LSP" "ai-audit should detect Serena config drift"
assert_contains "${RUN_OUTPUT}" "Claude Code Serena MCP: registered (interactive health check timed out)" "ai-audit should accept Claude MCP timeout fallback"
assert_contains "${RUN_OUTPUT}" "Codex Serena MCP: legacy uvx registration detected" "ai-audit should detect legacy Codex MCP registration"
assert_contains "${RUN_OUTPUT}" "Codex config backups: found backup files to review or delete" "ai-audit should report backup files"
assert_contains "${RUN_OUTPUT}" "AI config audit needs attention:" "ai-audit should summarize warnings"

pass_test "tests/ai-audit.sh"
