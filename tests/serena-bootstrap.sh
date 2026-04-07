#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-serena-bootstrap-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

fake_home="${tmpdir}/home"
fake_bin="${tmpdir}/bin"
mkdir -p "${fake_home}/.local/bin" "${fake_bin}"

cat > "${fake_bin}/uvx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SERENA_BOOTSTRAP_LOG}"
EOF

cat > "${fake_home}/.local/bin/serena-mcp" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "${fake_bin}/uvx" "${fake_home}/.local/bin/serena-mcp"

repo_git="${tmpdir}/repo-git"
mkdir -p "${repo_git}/subdir"
git init -q "${repo_git}"
repo_git_real="$(cd "${repo_git}" && pwd -P)"

run_capture env \
  HOME="${fake_home}" \
  PATH="${fake_bin}:${PATH}" \
  SERENA_BOOTSTRAP_LOG="${tmpdir}/bootstrap-git.log" \
  bash "${REPO_ROOT}/scripts/serena-bootstrap.sh" "${repo_git}/subdir"
assert_eq "0" "${RUN_STATUS}" "serena-bootstrap should succeed for a git project"
git_log="$(cat "${tmpdir}/bootstrap-git.log")"
assert_contains "${git_log}" "serena index-project ${repo_git_real}" "serena-bootstrap should normalize subdir paths to the git root"

project_non_git="${tmpdir}/project-non-git"
mkdir -p "${project_non_git}"

run_capture env \
  HOME="${fake_home}" \
  PATH="${fake_bin}:${PATH}" \
  SERENA_BOOTSTRAP_LOG="${tmpdir}/bootstrap-non-git.log" \
  bash "${REPO_ROOT}/scripts/serena-bootstrap.sh" "${project_non_git}"
assert_eq "0" "${RUN_STATUS}" "serena-bootstrap should succeed for a non-git directory"
non_git_log="$(cat "${tmpdir}/bootstrap-non-git.log")"
assert_contains "${non_git_log}" "serena index-project " "serena-bootstrap should run serena index-project for a non-git directory"

run_capture env \
  HOME="${fake_home}" \
  PATH="/usr/bin:/bin" \
  bash "${REPO_ROOT}/scripts/serena-bootstrap.sh" "${project_non_git}"
assert_eq "1" "${RUN_STATUS}" "serena-bootstrap should fail when uvx is missing"
assert_contains "${RUN_OUTPUT}" "uvx not found" "serena-bootstrap should explain the missing uvx dependency"

pass_test "tests/serena-bootstrap.sh"
