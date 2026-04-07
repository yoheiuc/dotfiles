#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-status-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

fake_repo="${tmpdir}/repo"
stub_bin="${tmpdir}/bin"
mkdir -p \
  "${fake_repo}/home" \
  "${fake_repo}/scripts/lib" \
  "${fake_repo}/scripts" \
  "${stub_bin}" \
  "${tmpdir}/home/.config/dotfiles" \
  "${tmpdir}/home/.codex" \
  "${tmpdir}/home/.claude" \
  "${tmpdir}/home/.gemini" \
  "${tmpdir}/home/.serena" \
  "${tmpdir}/home/Library/Application Support/com.github.domt4.homebrew-autoupdate" \
  "${tmpdir}/home/Library/LaunchAgents"

cat > "${fake_repo}/home/dot_Brewfile.core" <<'EOF'
brew "git"
cask "ghostty"
EOF

cat > "${fake_repo}/home/dot_Brewfile.home" <<'EOF'
cask "bitwarden"
EOF

cp "${REPO_ROOT}/scripts/status.sh" "${fake_repo}/scripts/status.sh"
cp "${REPO_ROOT}/scripts/profile.sh" "${fake_repo}/scripts/profile.sh"
cp "${REPO_ROOT}/scripts/lib/ai-config.sh" "${fake_repo}/scripts/lib/ai-config.sh"
cp "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh" "${fake_repo}/scripts/lib/brew-autoupdate.sh"
cp "${REPO_ROOT}/scripts/lib/brew-profile.sh" "${fake_repo}/scripts/lib/brew-profile.sh"

cat > "${fake_repo}/scripts/brew-bundle.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "check" ]]; then
  if [[ "${BREW_CHECK_MODE:-ok}" == "ok" ]]; then
    printf "The Brewfile's dependencies are satisfied.\n"
    exit 0
  fi

  printf "brew bundle check failed\n"
  exit 1
fi

printf "unsupported\n" >&2
exit 1
EOF

cat > "${stub_bin}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

if [[ "${1:-}" == "status" ]]; then
  printf '%b' "${GIT_STATUS_OUT:-## main...origin/main\n}"
  exit 0
fi

exit 1
EOF

cat > "${stub_bin}/chezmoi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  printf '%b' "${CHEZMOI_STATUS_OUT:-}"
  exit "${CHEZMOI_STATUS_CODE:-0}"
fi

exit 1
EOF

cat > "${stub_bin}/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list)
    case "${2:-}" in
      --formula)
        printf '%b' "${BREW_LIST_FORMULA:-}"
        ;;
      --cask)
        printf '%b' "${BREW_LIST_CASK:-}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "${stub_bin}/launchctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "print" && "${2:-}" == "gui/$(id -u)/com.github.domt4.homebrew-autoupdate" && "${LAUNCHCTL_AUTUPDATE_LOADED:-0}" == "1" ]]; then
  printf 'state = running\n'
  exit 0
fi

exit 1
EOF

cat > "${stub_bin}/plutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-extract" && "${2:-}" == "StartInterval" ]]; then
  printf '%s\n' "${PLUTIL_START_INTERVAL:-86400}"
  exit 0
fi

exit 1
EOF

cat > "${stub_bin}/pinentry-mac" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x \
  "${fake_repo}/scripts/status.sh" \
  "${fake_repo}/scripts/profile.sh" \
  "${fake_repo}/scripts/lib/ai-config.sh" \
  "${fake_repo}/scripts/lib/brew-autoupdate.sh" \
  "${fake_repo}/scripts/lib/brew-profile.sh" \
  "${fake_repo}/scripts/brew-bundle.sh" \
  "${stub_bin}/git" \
  "${stub_bin}/chezmoi" \
  "${stub_bin}/brew" \
  "${stub_bin}/launchctl" \
  "${stub_bin}/plutil" \
  "${stub_bin}/pinentry-mac"

export PATH="${stub_bin}:${PATH}"
export DOTFILES_REPO_ROOT="${fake_repo}"
export HOME="${tmpdir}/home"

printf 'home\n' > "${HOME}/.config/dotfiles/profile"
cat > "${HOME}/.codex/config.toml" <<'EOF'
model = "gpt-5.4"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
approval_policy = "on-request"

[features]
multi_agent = true
codex_hooks = true

[mcp_servers.openaiDeveloperDocs]
url = "https://developers.openai.com/mcp"
EOF
cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "latest"
}
EOF
: > "${HOME}/.gemini/settings.json"
: > "${HOME}/.serena/serena_config.yml"
: > "${HOME}/.codex/hooks.json"
: > "${HOME}/.claude/CLAUDE.md"
: > "${HOME}/AGENTS.md"
cat > "${HOME}/.serena/serena_config.yml" <<'EOF'
language_backend: LSP
web_dashboard: true
web_dashboard_open_on_launch: false
project_serena_folder_location: "$projectDir/.serena"
EOF
cat > "${HOME}/Library/Application Support/com.github.domt4.homebrew-autoupdate/brew_autoupdate" <<'EOF'
#!/bin/sh
export SUDO_ASKPASS='/tmp/brew_autoupdate_sudo_gui'
/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade --formula -v && /opt/homebrew/bin/brew upgrade --cask -v --greedy && /opt/homebrew/bin/brew cleanup
EOF
cat > "${HOME}/Library/LaunchAgents/com.github.domt4.homebrew-autoupdate.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>StartInterval</key><integer>86400</integer></dict></plist>
EOF

run_capture env \
  GIT_STATUS_OUT=$'## main...origin/main\n' \
  CHEZMOI_STATUS_OUT='' \
  BREW_CHECK_MODE=ok \
  BREW_LIST_FORMULA=$'git\n' \
  BREW_LIST_CASK=$'ghostty\nbitwarden\n' \
  LAUNCHCTL_AUTUPDATE_LOADED=1 \
  PLUTIL_START_INTERVAL=86400 \
  bash "${fake_repo}/scripts/status.sh"
assert_eq "0" "${RUN_STATUS}" "status should succeed in the clean case"
assert_contains "${RUN_OUTPUT}" "Active profile: home" "status should print the active profile"
assert_contains "${RUN_OUTPUT}" "working tree: clean" "status should report a clean worktree"
assert_contains "${RUN_OUTPUT}" "chezmoi managed files: clean" "status should report a clean chezmoi state"
assert_contains "${RUN_OUTPUT}" "home Brew profile: all declared packages present" "status should report Brew health"
assert_contains "${RUN_OUTPUT}" "brew autoupdate: running (every 24h, all formulae/casks, with sudo support)" "status should audit brew autoupdate"
assert_contains "${RUN_OUTPUT}" "pinentry-mac: present" "status should report pinentry availability"
assert_contains "${RUN_OUTPUT}" "Codex config: no legacy bridge settings detected" "status should audit Codex config"
assert_contains "${RUN_OUTPUT}" "Codex config: sandbox mode is workspace-write" "status should validate Codex sandbox"
assert_contains "${RUN_OUTPUT}" "Codex OpenAI Docs MCP: registered" "status should validate Docs MCP"
assert_contains "${RUN_OUTPUT}" "Claude settings: auto-update channel is latest" "status should validate Claude channel"
assert_contains "${RUN_OUTPUT}" "Serena config: expected defaults detected" "status should audit Serena config"
assert_contains "${RUN_OUTPUT}" "Status looks good." "status should summarize a clean state"

cat > "${HOME}/.codex/config.toml" <<'EOF'
# --- BEGIN CCB ---
approval_policy = "never"
sandbox_mode = "danger-full-access"
EOF
cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "stable"
}
EOF
rm -f "${HOME}/.gemini/settings.json"
cat > "${HOME}/.serena/serena_config.yml" <<'EOF'
language_backend: JetBrains
web_dashboard: false
web_dashboard_open_on_launch: true
project_serena_folder_location: "/tmp/serena"
EOF
rm -f "${HOME}/Library/Application Support/com.github.domt4.homebrew-autoupdate/brew_autoupdate"
rm -f "${HOME}/Library/LaunchAgents/com.github.domt4.homebrew-autoupdate.plist"

run_capture env \
  GIT_STATUS_OUT=$'## main...origin/main\n M README.md\n' \
  CHEZMOI_STATUS_OUT=$'M ~/.zshrc\n' \
  BREW_CHECK_MODE=bad \
  BREW_LIST_FORMULA=$'git\n' \
  BREW_LIST_CASK=$'ghostty\n' \
  BREW_AUTOUPDATE_FORCE_PINENTRY_MISSING=1 \
  LAUNCHCTL_AUTUPDATE_LOADED=0 \
  bash "${fake_repo}/scripts/status.sh"
assert_eq "0" "${RUN_STATUS}" "status should stay informational even with warnings"
assert_contains "${RUN_OUTPUT}" "working tree: local changes detected" "status should warn on dirty worktree"
assert_contains "${RUN_OUTPUT}" "chezmoi managed files: pending changes detected" "status should warn on chezmoi drift"
assert_contains "${RUN_OUTPUT}" "home Brew profile: missing packages or check failed" "status should warn on Brew failures"
assert_contains "${RUN_OUTPUT}" "brew autoupdate: not configured" "status should warn on missing brew autoupdate"
assert_contains "${RUN_OUTPUT}" "pinentry-mac: missing" "status should warn on missing pinentry"
assert_contains "${RUN_OUTPUT}" "Gemini settings: missing" "status should report missing local settings"
assert_contains "${RUN_OUTPUT}" "Codex config: legacy bridge/auto-approval settings detected" "status should detect legacy Codex settings"
assert_contains "${RUN_OUTPUT}" "Codex config: sandbox mode should be workspace-write" "status should detect Codex sandbox drift"
assert_contains "${RUN_OUTPUT}" "Codex OpenAI Docs MCP: missing or wrong URL" "status should detect missing Docs MCP"
assert_contains "${RUN_OUTPUT}" "Claude settings: auto-update channel should be latest" "status should detect Claude channel drift"
assert_contains "${RUN_OUTPUT}" "Serena config: expected defaults drifted" "status should detect Serena config drift"
assert_contains "${RUN_OUTPUT}" "Attention needed:" "status should summarize warnings"

pass_test "tests/status.sh"
