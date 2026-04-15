#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-secrets-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/home/.local/bin"
export HOME="${tmpdir}/home"
export XDG_CONFIG_HOME="${HOME}/.config"
export DOTFILES_REPO_ROOT="${REPO_ROOT}"
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
export SECURITY_BIN="${tmpdir}/security"

cat > "${HOME}/.local/bin/serena-mcp" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${HOME}/.local/bin/serena-mcp"

run_capture bash -lc "printf 'BSAtest_prompted_key\n' | bash '${REPO_ROOT}/scripts/ai-secrets.sh'"
assert_eq "0" "${RUN_STATUS}" "ai-secrets should succeed with piped input"
assert_contains "${RUN_OUTPUT}" "Saved Brave API key to Keychain service dotfiles.ai.mcp" "ai-secrets should report keychain save"
assert_not_contains "${RUN_OUTPUT}" "BSAtest_prompted_key" "ai-secrets should not print the Brave API key"

assert_contains "$(cat "${FAKE_SECURITY_DB}")" $'dotfiles.ai.mcp\tbrave-api-key\tBSAtest_prompted_key' "ai-secrets should persist the Brave API key to Keychain"
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'mcp-with-keychain-secret' "ai-secrets should configure Codex to use the keychain wrapper"
assert_contains "$(cat "${HOME}/.claude.json")" '"exa"' "ai-secrets should keep Exa registered for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"brave-search"' "ai-secrets should register Brave Search MCP for Claude Code"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" 'BSAtest_prompted_key' "ai-secrets should not write the Brave API key into Codex config"
assert_not_contains "$(cat "${HOME}/.claude.json")" 'BSAtest_prompted_key' "ai-secrets should not write the Brave API key into Claude config"
assert_not_contains "$(ls -a "${HOME}/.config/dotfiles" 2>/dev/null || true)" 'ai-secrets.env' "ai-secrets should not leave a plaintext secrets file"

pass_test "tests/ai-secrets.sh"
