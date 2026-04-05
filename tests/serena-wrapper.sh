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

repo_auto_index="${tmpdir}/repo-auto-index"
mkdir -p "${repo_auto_index}/subdir"
git init -q "${repo_auto_index}"
repo_auto_index_real="$(cd "${repo_auto_index}" && pwd -P)"

run_capture env \
  HOME="${tmpdir}/home" \
  SERENA_UVX_BIN="${fake_uvx}" \
  SERENA_UVX_LOG="${tmpdir}/uvx-auto-index.log" \
  bash -lc "cd '${repo_auto_index}/subdir' && bash '${REPO_ROOT}/home/dot_local/bin/executable_serena-mcp' codex"
assert_eq "0" "${RUN_STATUS}" "serena wrapper should succeed when auto-index is enabled"
auto_index_log="$(cat "${tmpdir}/uvx-auto-index.log")"
assert_contains "${auto_index_log}" "serena index-project ${repo_auto_index_real}" "wrapper should run serena index-project for the git root before starting MCP"
assert_contains "${auto_index_log}" "serena start-mcp-server --context=codex --project-from-cwd --open-web-dashboard False" "wrapper should forward the expected Serena MCP arguments"

repo_skip_index="${tmpdir}/repo-skip-index"
git init -q "${repo_skip_index}"

run_capture env \
  HOME="${tmpdir}/home" \
  SERENA_UVX_BIN="${fake_uvx}" \
  SERENA_UVX_LOG="${tmpdir}/uvx-skip-index.log" \
  SERENA_AUTO_INDEX=0 \
  bash -lc "cd '${repo_skip_index}' && bash '${REPO_ROOT}/home/dot_local/bin/executable_serena-mcp' claude-code"
assert_eq "0" "${RUN_STATUS}" "serena wrapper should succeed when auto-index is disabled"
skip_index_log="$(cat "${tmpdir}/uvx-skip-index.log")"
assert_not_contains "${skip_index_log}" "serena index-project" "wrapper should skip index-project when SERENA_AUTO_INDEX=0"
assert_contains "${skip_index_log}" "--context=claude-code" "wrapper should preserve the requested Serena context"

non_git_dir="${tmpdir}/non-git-dir"
mkdir -p "${non_git_dir}"

run_capture env \
  HOME="${tmpdir}/home" \
  SERENA_UVX_BIN="${fake_uvx}" \
  SERENA_UVX_LOG="${tmpdir}/uvx-non-git.log" \
  bash -lc "cd '${non_git_dir}' && bash '${REPO_ROOT}/home/dot_local/bin/executable_serena-mcp' codex"
assert_eq "0" "${RUN_STATUS}" "serena wrapper should succeed outside a git repo"
non_git_log="$(cat "${tmpdir}/uvx-non-git.log")"
assert_not_contains "${non_git_log}" "serena index-project" "wrapper should not run index-project outside a git repo"
assert_contains "${non_git_log}" "serena start-mcp-server --context=codex --project-from-cwd --open-web-dashboard False" "wrapper should still start MCP outside a git repo"

pass_test "tests/serena-wrapper.sh"
