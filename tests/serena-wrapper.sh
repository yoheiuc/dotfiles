#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-serena-wrapper-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

fake_uvx="${tmpdir}/uvx"
cat > "${fake_uvx}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SERENA_UVX_LOG}"
EOF
chmod +x "${fake_uvx}"

# Test: basic MCP start in a git repo
repo="${tmpdir}/repo"
mkdir -p "${repo}/subdir"
git init -q "${repo}"

run_capture env \
  HOME="${tmpdir}/home" \
  SERENA_UVX_BIN="${fake_uvx}" \
  SERENA_UVX_LOG="${tmpdir}/uvx.log" \
  bash -lc "cd '${repo}/subdir' && bash '${REPO_ROOT}/home/dot_local/bin/executable_serena-mcp' claude-code"
assert_eq "0" "${RUN_STATUS}" "serena wrapper should succeed"
uvx_log="$(cat "${tmpdir}/uvx.log")"
assert_contains "${uvx_log}" "-q --from git+https://github.com/oraios/serena serena start-mcp-server --context=claude-code --project-from-cwd --open-web-dashboard False" "wrapper should forward the expected Serena MCP arguments quietly"
assert_not_contains "${uvx_log}" "index-project" "wrapper should not auto-index"

# Test: non-git directory
non_git_dir="${tmpdir}/non-git-dir"
mkdir -p "${non_git_dir}"

run_capture env \
  HOME="${tmpdir}/home" \
  SERENA_UVX_BIN="${fake_uvx}" \
  SERENA_UVX_LOG="${tmpdir}/uvx-non-git.log" \
  bash -lc "cd '${non_git_dir}' && bash '${REPO_ROOT}/home/dot_local/bin/executable_serena-mcp' claude-code"
assert_eq "0" "${RUN_STATUS}" "serena wrapper should succeed outside a git repo"
non_git_log="$(cat "${tmpdir}/uvx-non-git.log")"
assert_contains "${non_git_log}" "--context=claude-code" "wrapper should preserve the requested Serena context"

pass_test "tests/serena-wrapper.sh"
