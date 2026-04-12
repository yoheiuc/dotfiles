#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-secrets-wrapper-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

fake_home="${tmpdir}/home"
mkdir -p "${fake_home}/.local/bin" "${fake_home}/.codex" "${fake_home}/.config/dotfiles"
export FAKE_SECURITY_DB="${tmpdir}/security-db"

cat > "${tmpdir}/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
db="${FAKE_SECURITY_DB:?}"
mkdir -p "$(dirname "${db}")"
touch "${db}"
cmd="${1:?}"
shift
case "${cmd}" in
  add-generic-password)
    service=""
    account=""
    secret=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -U) shift ;;
        -s) service="$2"; shift 2 ;;
        -a) account="$2"; shift 2 ;;
        -w) secret="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    grep -v "^${service}"$'\t'"${account}"$'\t' "${db}" > "${db}.tmp" || true
    printf '%s\t%s\t%s\n' "${service}" "${account}" "${secret}" >> "${db}.tmp"
    mv "${db}.tmp" "${db}"
    ;;
  find-generic-password)
    service=""
    account=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -w) shift ;;
        -s) service="$2"; shift 2 ;;
        -a) account="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    awk -F '\t' -v s="${service}" -v a="${account}" '$1==s && $2==a { print $3; found=1 } END { exit found ? 0 : 1 }' "${db}"
    ;;
  delete-generic-password)
    service=""
    account=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -s) service="$2"; shift 2 ;;
        -a) account="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    grep -v "^${service}"$'\t'"${account}"$'\t' "${db}" > "${db}.tmp" || true
    mv "${db}.tmp" "${db}"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${tmpdir}/security"

cat > "${fake_home}/.local/bin/serena-mcp" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${fake_home}/.local/bin/serena-mcp"

run_capture env \
  HOME="${fake_home}" \
  XDG_CONFIG_HOME="${fake_home}/.config" \
  DOTFILES_REPO_ROOT="${REPO_ROOT}" \
  SECURITY_BIN="${tmpdir}/security" \
  bash -lc "printf 'ghp_from_wrapper\n\n' | bash '${REPO_ROOT}/home/dot_local/bin/executable_ai-secrets'"
assert_eq "0" "${RUN_STATUS}" "ai-secrets wrapper should succeed"
assert_not_contains "${RUN_OUTPUT}" "ghp_from_wrapper" "ai-secrets wrapper should not echo the GitHub token"
assert_contains "$(cat "${FAKE_SECURITY_DB}")" $'dotfiles.ai.mcp\tgithub-personal-access-token\tghp_from_wrapper' "ai-secrets wrapper should persist the token to Keychain"
assert_contains "$(cat "${fake_home}/.codex/config.toml")" 'mcp-with-keychain-secret' "ai-secrets wrapper should refresh Codex config"

pass_test "tests/ai-secrets-wrapper.sh"
