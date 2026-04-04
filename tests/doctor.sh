#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-doctor-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

ORIGINAL_PATH="${PATH}"
STUB_BIN="${tmpdir}/bin"
mkdir -p "${STUB_BIN}"

cat > "${STUB_BIN}/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    printf 'Homebrew 9.9.9\n'
    ;;
  list)
    case "${2:-}" in
      --formula)
        printf '%b' "${BREW_FORMULAE:-}"
        ;;
      --cask)
        printf '%b' "${BREW_CASKS:-}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  bundle)
    shift
    if [[ "${1:-}" == "check" ]]; then
      printf "The Brewfile's dependencies are satisfied.\n"
      exit 0
    fi
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "${STUB_BIN}/chezmoi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    printf 'chezmoi version v9.9.9\n'
    ;;
  doctor)
    cat <<'OUT'
RESULT   CHECK          MESSAGE
ok       version        v9.9.9
ok       source-dir     ~/dotfiles is a git working tree (clean)
OUT
    ;;
  diff)
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "${STUB_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "config" || "${2:-}" != "--global" ]]; then
  exit 1
fi

case "${*: -1}" in
  user.name)
    printf 'yoheiuc\n'
    ;;
  user.email)
    printf '16657439+yoheiuc@users.noreply.github.com\n'
    ;;
  core.hooksPath)
    printf '%s/.config/git/hooks\n' "${HOME}"
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "${STUB_BIN}/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    printf '2.1.84 (Claude Code)\n'
    ;;
  mcp)
    if [[ "${2:-}" == "list" ]]; then
      printf '%s' "${CLAUDE_MCP_LIST_OUTPUT:-}"
      exit "${CLAUDE_MCP_LIST_STATUS:-0}"
    fi
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "${STUB_BIN}/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    printf 'codex-cli 0.118.0\n'
    ;;
  mcp)
    if [[ "${2:-}" == "list" ]]; then
      printf '%s' "${CODEX_MCP_LIST_OUTPUT:-}"
      exit "${CODEX_MCP_LIST_STATUS:-0}"
    fi
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "${STUB_BIN}/brew" "${STUB_BIN}/chezmoi" "${STUB_BIN}/git" "${STUB_BIN}/claude" "${STUB_BIN}/codex"

run_doctor() {
  local home_dir="$1"
  shift

  mkdir -p "${home_dir}/.config/git/hooks" "${home_dir}/.config/dotfiles" "${home_dir}/.codex"
  : > "${home_dir}/.config/git/hooks/pre-commit"
  chmod +x "${home_dir}/.config/git/hooks/pre-commit"

  env HOME="${home_dir}" PATH="${STUB_BIN}:${ORIGINAL_PATH}" "$@" \
    bash "${REPO_ROOT}/scripts/doctor.sh"
}

home_ok="${tmpdir}/home-ok"
mkdir -p "${home_ok}/.config/dotfiles" "${home_ok}/.codex"
printf 'home\n' > "${home_ok}/.config/dotfiles/profile"
cat > "${home_ok}/.claude.json" <<'EOF'
{
  "mcpServers": {
    "serena": {
      "command": "/Users/example/.local/bin/serena-mcp",
      "args": ["claude-code"]
    }
  }
}
EOF
cat > "${home_ok}/.codex/config.toml" <<'EOF'
[features]
codex_hooks = true
EOF
mkdir -p "${home_ok}/.codex/skills/codex-auto-save-memory/scripts"
: > "${home_ok}/.codex/hooks.json"
: > "${home_ok}/.codex/skills/codex-auto-save-memory/scripts/autosave_memory.py"

run_capture run_doctor "${home_ok}" \
  BREW_FORMULAE=$'chezmoi\ngit\n' \
  BREW_CASKS=$'ghostty\n' \
  CLAUDE_MCP_LIST_OUTPUT=$'Timed out after 15s\n' \
  CLAUDE_MCP_LIST_STATUS=124 \
  CODEX_MCP_LIST_OUTPUT=$'Name    Command                                Args   Env  Cwd  Status   Auth\nserena  '"${home_ok}"'/.local/bin/serena-mcp  codex  -    -    enabled  Unsupported\n'
assert_eq "0" "${RUN_STATUS}" "doctor should pass in the healthy home profile case"
assert_contains "${RUN_OUTPUT}" "No work/home-only Brew packages are installed outside 'home' profile" "doctor should report clean drift status"
assert_contains "${RUN_OUTPUT}" "serena MCP: registered (interactive health check timed out)" "doctor should accept Claude timeout fallback when serena is registered"
assert_contains "${RUN_OUTPUT}" "serena MCP: enabled via wrapper" "doctor should recognize Codex wrapper configuration"

home_drift="${tmpdir}/home-drift"
mkdir -p "${home_drift}/.config/dotfiles" "${home_drift}/.codex"
printf 'core\n' > "${home_drift}/.config/dotfiles/profile"
cat > "${home_drift}/.codex/config.toml" <<'EOF'
[features]
codex_hooks = true
EOF
mkdir -p "${home_drift}/.codex/skills/codex-auto-save-memory/scripts"
: > "${home_drift}/.codex/hooks.json"
: > "${home_drift}/.codex/skills/codex-auto-save-memory/scripts/autosave_memory.py"

run_capture run_doctor "${home_drift}" \
  BREW_FORMULAE=$'chezmoi\ngit\nlaishulu/homebrew/macism\n' \
  BREW_CASKS=$'ghostty\nbitwarden\n' \
  CLAUDE_MCP_LIST_OUTPUT='' \
  CODEX_MCP_LIST_OUTPUT=''
assert_eq "0" "${RUN_STATUS}" "doctor should stay green when only optional drift warnings are present"
assert_contains "${RUN_OUTPUT}" "Brew profile drift: formulae installed outside 'core' profile" "doctor should warn on formula drift"
assert_contains "${RUN_OUTPUT}" "laishulu/homebrew/macism" "doctor should list drifting formula names"
assert_contains "${RUN_OUTPUT}" "Brew profile drift: casks installed outside 'core' profile" "doctor should warn on cask drift"
assert_contains "${RUN_OUTPUT}" "bitwarden" "doctor should list drifting cask names"

pass_test "tests/doctor.sh"
