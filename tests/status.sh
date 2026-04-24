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
  "${tmpdir}/home/.claude" \
  "${tmpdir}/home/.serena" \
  "${tmpdir}/home/Library/Application Support/com.github.domt4.homebrew-autoupdate" \
  "${tmpdir}/home/Library/LaunchAgents"

cat > "${fake_repo}/home/dot_Brewfile" <<'EOF'
brew "git"
cask "ghostty"
cask "bitwarden"
EOF

cp "${REPO_ROOT}/scripts/status.sh" "${fake_repo}/scripts/status.sh"
cp "${REPO_ROOT}/scripts/lib/ui.sh" "${fake_repo}/scripts/lib/ui.sh"
cp "${REPO_ROOT}/scripts/lib/ai-config.sh" "${fake_repo}/scripts/lib/ai-config.sh"
cp "${REPO_ROOT}/scripts/lib/ai_config.py" "${fake_repo}/scripts/lib/ai_config.py"
cp "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh" "${fake_repo}/scripts/lib/brew-autoupdate.sh"

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
exit 1
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
  "${fake_repo}/scripts/lib/ai-config.sh" \
  "${fake_repo}/scripts/lib/brew-autoupdate.sh" \
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

cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "latest"
}
EOF
: > "${HOME}/.claude/CLAUDE.md"
cat > "${HOME}/.serena/serena_config.yml" <<'EOF'
language_backend: LSP
web_dashboard: true
web_dashboard_open_on_launch: false
project_serena_folder_location: "$projectDir/.serena"
EOF
run_capture env \
  GIT_STATUS_OUT=$'## main...origin/main\n' \
  CHEZMOI_STATUS_OUT='' \
  BREW_CHECK_MODE=ok \
  LAUNCHCTL_AUTUPDATE_LOADED=0 \
  bash "${fake_repo}/scripts/status.sh"
assert_eq "0" "${RUN_STATUS}" "status should succeed in the clean case"
assert_contains "${RUN_OUTPUT}" "working tree: clean" "status should report a clean worktree"
assert_contains "${RUN_OUTPUT}" "chezmoi managed files: clean" "status should report a clean chezmoi state"
assert_contains "${RUN_OUTPUT}" "Brewfile: all declared packages present" "status should report Brew health"
assert_contains "${RUN_OUTPUT}" "brew autoupdate: disabled by dotfiles policy" "status should enforce disabled brew autoupdate policy"
assert_contains "${RUN_OUTPUT}" "Claude settings: auto-update channel is latest" "status should validate Claude channel"
assert_contains "${RUN_OUTPUT}" "Serena config: expected defaults detected" "status should audit Serena config"
assert_contains "${RUN_OUTPUT}" "Status looks good." "status should summarize a clean state"

cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "stable"
}
EOF
cat > "${HOME}/.serena/serena_config.yml" <<'EOF'
language_backend: JetBrains
web_dashboard: false
web_dashboard_open_on_launch: true
project_serena_folder_location: "/tmp/serena"
EOF
cat > "${HOME}/Library/Application Support/com.github.domt4.homebrew-autoupdate/brew_autoupdate" <<'EOF'
#!/bin/sh
/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade --formula -v
EOF
cat > "${HOME}/Library/LaunchAgents/com.github.domt4.homebrew-autoupdate.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>StartInterval</key><integer>3600</integer></dict></plist>
EOF

run_capture env \
  GIT_STATUS_OUT=$'## main...origin/main\n M README.md\n' \
  CHEZMOI_STATUS_OUT=$'M ~/.zshrc\n' \
  BREW_CHECK_MODE=bad \
  LAUNCHCTL_AUTUPDATE_LOADED=1 \
  bash "${fake_repo}/scripts/status.sh"
assert_eq "0" "${RUN_STATUS}" "status should stay informational even with warnings"
assert_contains "${RUN_OUTPUT}" "working tree: local changes detected" "status should warn on dirty worktree"
assert_contains "${RUN_OUTPUT}" "chezmoi managed files: pending changes detected" "status should warn on chezmoi drift"
assert_contains "${RUN_OUTPUT}" "Brewfile: missing packages or check failed" "status should warn on Brew failures"
assert_contains "${RUN_OUTPUT}" "brew autoupdate: enabled, but dotfiles policy is disabled" "status should warn when brew autoupdate is enabled"
assert_contains "${RUN_OUTPUT}" "Claude settings: auto-update channel should be latest" "status should detect Claude channel drift"
assert_contains "${RUN_OUTPUT}" "Serena config: expected defaults drifted" "status should detect Serena config drift"
assert_contains "${RUN_OUTPUT}" "Attention needed:" "status should summarize warnings"

pass_test "tests/status.sh"
