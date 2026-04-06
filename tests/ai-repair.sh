#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-repair-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/home/.local/bin" "${tmpdir}/bin"
export HOME="${tmpdir}/home"
export PATH="${tmpdir}/bin:${PATH}"
export DOTFILES_REPO_ROOT="${REPO_ROOT}"

cat > "${HOME}/.local/bin/serena-mcp" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${HOME}/.local/bin/serena-mcp"

cat > "${tmpdir}/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${CLAUDE_LOG}"

case "${1:-} ${2:-}" in
  "mcp get")
    exit 1
    ;;
  "mcp add")
    exit 0
    ;;
esac

exit 0
EOF

cat > "${tmpdir}/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${CODEX_LOG}"

case "${1:-} ${2:-}" in
  "mcp get")
    exit 1
    ;;
  "mcp add")
    exit 0
    ;;
esac

exit 0
EOF

chmod +x "${tmpdir}/bin/claude" "${tmpdir}/bin/codex"

run_capture env \
  CLAUDE_LOG="${tmpdir}/claude.log" \
  CODEX_LOG="${tmpdir}/codex.log" \
  bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed when creating missing Serena state"
assert_contains "${RUN_OUTPUT}" "Created Serena config" "ai-repair should create Serena config when missing"
assert_contains "${RUN_OUTPUT}" "Claude Code Serena registration created" "ai-repair should register Serena for Claude Code"
assert_contains "${RUN_OUTPUT}" "Codex Serena registration created" "ai-repair should register Serena for Codex"
assert_contains "$(cat "${tmpdir}/claude.log")" "mcp add --scope user serena -- ${HOME}/.local/bin/serena-mcp claude-code" "ai-repair should add Claude Code Serena wrapper registration"
assert_contains "$(cat "${tmpdir}/codex.log")" "mcp add serena -- ${HOME}/.local/bin/serena-mcp codex" "ai-repair should add Codex Serena wrapper registration"
assert_contains "$(cat "${HOME}/.serena/serena_config.yml")" 'project_serena_folder_location: "$projectDir/.serena"' "ai-repair should write the expected Serena config"

pass_test "tests/ai-repair.sh"
