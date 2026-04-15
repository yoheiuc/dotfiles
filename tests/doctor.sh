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

cat > "${STUB_BIN}/launchctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "print" && "${2:-}" == "gui/$(id -u)/com.github.domt4.homebrew-autoupdate" && "${LAUNCHCTL_AUTUPDATE_LOADED:-0}" == "1" ]]; then
  printf 'state = running\n'
  exit 0
fi

exit 1
EOF

cat > "${STUB_BIN}/plutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-extract" && "${2:-}" == "StartInterval" ]]; then
  printf '%s\n' "${PLUTIL_START_INTERVAL:-86400}"
  exit 0
fi

exit 1
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
  *)
    exit 1
    ;;
esac
EOF

cat > "${STUB_BIN}/pinentry-mac" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "${STUB_BIN}/xcode-select" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-p" ]]; then
  printf '/Library/Developer/CommandLineTools\n'
  exit 0
fi
exit 1
EOF

cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf 'swift 5.9\n'
  exit 0
fi
if [[ "${1:-}" == "-e" ]]; then
  exit 0
fi
exit 1
EOF

chmod +x "${STUB_BIN}/brew" "${STUB_BIN}/chezmoi" "${STUB_BIN}/git" "${STUB_BIN}/claude" "${STUB_BIN}/codex" "${STUB_BIN}/launchctl" "${STUB_BIN}/plutil" "${STUB_BIN}/pinentry-mac" "${STUB_BIN}/xcode-select" "${STUB_BIN}/swift"

run_doctor() {
  local home_dir="$1"
  shift

  mkdir -p "${home_dir}/.config/git/hooks" "${home_dir}/.config/dotfiles" "${home_dir}/.codex"
  : > "${home_dir}/.config/git/hooks/pre-commit"
  chmod +x "${home_dir}/.config/git/hooks/pre-commit"
  mkdir -p "${home_dir}/dotfiles/scripts/lib" "${home_dir}/.serena" "${home_dir}/Library/Application Support/com.github.domt4.homebrew-autoupdate" "${home_dir}/Library/LaunchAgents"
  cp "${REPO_ROOT}/scripts/lib/brew-profile.sh" "${home_dir}/dotfiles/scripts/lib/brew-profile.sh"
  cp "${REPO_ROOT}/scripts/lib/ai-config.sh" "${home_dir}/dotfiles/scripts/lib/ai-config.sh"
  cp "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh" "${home_dir}/dotfiles/scripts/lib/brew-autoupdate.sh"

  env HOME="${home_dir}" PATH="${STUB_BIN}:${ORIGINAL_PATH}" "$@" DOTFILES_REPO_ROOT="${home_dir}/dotfiles" \
    bash "${REPO_ROOT}/scripts/doctor.sh"
}

# ---- Scenario 1: healthy home profile ----
home_ok="${tmpdir}/home-ok"
mkdir -p "${home_ok}/.config/dotfiles" "${home_ok}/.codex" "${home_ok}/.serena" "${home_ok}/.local/bin" "${home_ok}/Library/Application Support/com.github.domt4.homebrew-autoupdate" "${home_ok}/Library/LaunchAgents"
printf 'home\n' > "${home_ok}/.config/dotfiles/profile"
cat > "${home_ok}/.claude.json" <<EOF
{
  "mcpServers": {
    "serena": {
      "type": "stdio",
      "command": "${home_ok}/.local/bin/serena-mcp",
      "args": ["claude-code"],
      "env": {}
    }
  }
}
EOF
cat > "${home_ok}/.codex/config.toml" <<EOF
model = "gpt-5.4"
model_reasoning_effort = "high"
personality = "pragmatic"
sandbox_mode = "workspace-write"
approval_policy = "on-request"

[profiles.fast]
model = "codex-mini-latest"
model_reasoning_effort = "low"
personality = "pragmatic"

[features]
multi_agent = true
codex_hooks = true

[mcp_servers.serena]
command = "${home_ok}/.local/bin/serena-mcp"
args = ["codex"]

[mcp_servers.openaiDeveloperDocs]
url = "https://developers.openai.com/mcp"
EOF
mkdir -p "${home_ok}/.claude"
cat > "${home_ok}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "latest"
}
EOF
mkdir -p "${home_ok}/.codex/skills/codex-auto-save-memory/scripts"
: > "${home_ok}/.codex/hooks.json"
: > "${home_ok}/.codex/skills/codex-auto-save-memory/scripts/autosave_memory.py"
cat > "${home_ok}/.serena/serena_config.yml" <<'EOF'
language_backend: LSP
web_dashboard: true
web_dashboard_open_on_launch: false
project_serena_folder_location: "$projectDir/.serena"
EOF
run_capture run_doctor "${home_ok}" \
  LAUNCHCTL_AUTUPDATE_LOADED=0 \
  BREW_FORMULAE=$'chezmoi\ngit\n' \
  BREW_CASKS=$'ghostty\n'
assert_eq "0" "${RUN_STATUS}" "doctor should pass in the healthy home profile case"
assert_contains "${RUN_OUTPUT}" "Daily checks live in: make status / make ai-audit" "doctor should point to the lighter commands"
assert_contains "${RUN_OUTPUT}" "No Brew profile drift detected for 'home'" "doctor should report clean drift status"
assert_contains "${RUN_OUTPUT}" "auto-update channel: latest" "doctor should validate Claude channel"
assert_contains "${RUN_OUTPUT}" "default model: gpt-5.4" "doctor should validate Codex model baseline"
assert_contains "${RUN_OUTPUT}" "sandbox mode: workspace-write" "doctor should validate Codex sandbox baseline"
assert_contains "${RUN_OUTPUT}" "approval policy: on-request" "doctor should validate Codex approval baseline"
assert_contains "${RUN_OUTPUT}" "OpenAI Docs MCP: registered" "doctor should validate Docs MCP"
assert_contains "${RUN_OUTPUT}" "brew autoupdate: disabled by dotfiles policy" "doctor should validate disabled brew autoupdate policy"
assert_contains "${RUN_OUTPUT}" "serena config: language_backend = LSP" "doctor should validate Serena global config"
assert_contains "${RUN_OUTPUT}" "serena MCP: registered" "doctor should detect Claude serena registration"
assert_contains "${RUN_OUTPUT}" "serena MCP: registered via wrapper" "doctor should detect Codex wrapper registration"

# ---- Scenario 2: drift ----
home_drift="${tmpdir}/home-drift"
mkdir -p "${home_drift}/.config/dotfiles" "${home_drift}/.codex" "${home_drift}/.serena" "${home_drift}/Library/Application Support/com.github.domt4.homebrew-autoupdate" "${home_drift}/Library/LaunchAgents"
printf 'core\n' > "${home_drift}/.config/dotfiles/profile"
cat > "${home_drift}/.codex/config.toml" <<'EOF'
model = "codex-mini-latest"
[features]
codex_hooks = true
EOF
mkdir -p "${home_drift}/.claude"
cat > "${home_drift}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "stable"
}
EOF
mkdir -p "${home_drift}/.codex/skills/codex-auto-save-memory/scripts"
: > "${home_drift}/.codex/hooks.json"
: > "${home_drift}/.codex/skills/codex-auto-save-memory/scripts/autosave_memory.py"
cat > "${home_drift}/.serena/serena_config.yml" <<'EOF'
language_backend: JetBrains
web_dashboard: false
web_dashboard_open_on_launch: true
project_serena_folder_location: "/tmp/serena"
EOF
cat > "${home_drift}/Library/Application Support/com.github.domt4.homebrew-autoupdate/brew_autoupdate" <<'EOF'
#!/bin/sh
/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade --formula -v
EOF
cat > "${home_drift}/Library/LaunchAgents/com.github.domt4.homebrew-autoupdate.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>StartInterval</key><integer>3600</integer></dict></plist>
EOF

run_capture run_doctor "${home_drift}" \
  LAUNCHCTL_AUTUPDATE_LOADED=1 \
  BREW_DOCTOR_CLT_WARN=1 \
  BREW_FORMULAE=$'chezmoi\ngit\n' \
  BREW_CASKS=$'ghostty\nbitwarden\n'
assert_eq "0" "${RUN_STATUS}" "doctor should stay green when only optional drift warnings are present"
assert_contains "${RUN_OUTPUT}" "Brew profile drift: casks installed outside 'core' profile" "doctor should warn on cask drift"
assert_contains "${RUN_OUTPUT}" "auto-update channel should be latest" "doctor should warn on Claude channel drift"
assert_contains "${RUN_OUTPUT}" "default model should be gpt-5.4" "doctor should warn on Codex model drift"
assert_contains "${RUN_OUTPUT}" "sandbox mode should be workspace-write" "doctor should warn on Codex sandbox drift"
assert_contains "${RUN_OUTPUT}" "approval policy should be on-request" "doctor should warn on Codex approval drift"
assert_contains "${RUN_OUTPUT}" "OpenAI Docs MCP: missing" "doctor should warn on missing Docs MCP"
assert_contains "${RUN_OUTPUT}" "brew autoupdate: enabled, but dotfiles policy is disabled" "doctor should warn when brew autoupdate is enabled"
assert_contains "${RUN_OUTPUT}" "serena config: language_backend is not LSP" "doctor should warn on Serena config drift"
assert_contains "${RUN_OUTPUT}" "bitwarden" "doctor should list drifting cask names"
assert_contains "${RUN_OUTPUT}" "serena MCP: not registered" "doctor should warn about missing serena MCP"

pass_test "tests/doctor.sh"
