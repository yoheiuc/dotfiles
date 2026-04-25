#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-doctor-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

ORIGINAL_PATH="${PATH}"
STUB_BIN="${tmpdir}/bin"
mkdir -p "${STUB_BIN}"

# Strip any PATH directory that shadows an optional tool the drift scenario
# expects to be "not found" (currently: clasp). On CI the tool is unavailable
# so this is a no-op; on dev boxes with brew-installed clasp, PATH would
# otherwise leak the real binary through ORIGINAL_PATH and break the
# "clasp not found" assertion.
sanitize_path_for_optional_tools() {
  local original="$1"
  shift
  local tools=("$@")
  local out=""
  local IFS=:
  local part
  for part in ${original}; do
    local keep=1
    local tool
    for tool in "${tools[@]}"; do
      if [[ -x "${part}/${tool}" ]]; then
        keep=0
        break
      fi
    done
    if [[ "${keep}" == "1" ]]; then
      out="${out:+${out}:}${part}"
    fi
  done
  printf '%s\n' "${out}"
}
SANITIZED_PATH="$(sanitize_path_for_optional_tools "${ORIGINAL_PATH}" clasp)"

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
    printf 'test-user\n'
    ;;
  user.email)
    printf 'test-user@users.noreply.github.com\n'
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

cat > "${STUB_BIN}/gcloud" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  version)
    printf 'Google Cloud SDK 520.0.0\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "${STUB_BIN}/clasp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    printf '2.5.0\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "${STUB_BIN}/brew" "${STUB_BIN}/chezmoi" "${STUB_BIN}/git" "${STUB_BIN}/claude" "${STUB_BIN}/launchctl" "${STUB_BIN}/plutil" "${STUB_BIN}/pinentry-mac" "${STUB_BIN}/xcode-select" "${STUB_BIN}/swift" "${STUB_BIN}/gcloud" "${STUB_BIN}/clasp"

run_doctor() {
  local home_dir="$1"
  shift

  mkdir -p "${home_dir}/.config/git/hooks"
  : > "${home_dir}/.config/git/hooks/pre-commit"
  chmod +x "${home_dir}/.config/git/hooks/pre-commit"
  mkdir -p "${home_dir}/dotfiles/scripts/lib" "${home_dir}/Library/Application Support/com.github.domt4.homebrew-autoupdate" "${home_dir}/Library/LaunchAgents"
  cp "${REPO_ROOT}/scripts/lib/ui.sh" "${home_dir}/dotfiles/scripts/lib/ui.sh"
  cp "${REPO_ROOT}/scripts/lib/ai-config.sh" "${home_dir}/dotfiles/scripts/lib/ai-config.sh"
  cp "${REPO_ROOT}/scripts/lib/ai_config.py" "${home_dir}/dotfiles/scripts/lib/ai_config.py"
  cp "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh" "${home_dir}/dotfiles/scripts/lib/brew-autoupdate.sh"

  local runtime_path="${DOCTOR_TEST_PATH_OVERRIDE:-${STUB_BIN}:${ORIGINAL_PATH}}"
  env HOME="${home_dir}" PATH="${runtime_path}" "$@" DOTFILES_REPO_ROOT="${home_dir}/dotfiles" \
    bash "${REPO_ROOT}/scripts/doctor.sh"
}

# ---- Scenario 1: healthy ----
home_ok="${tmpdir}/home-ok"
mkdir -p "${home_ok}/.local/bin" "${home_ok}/.local/lib/python-ssl-compat" "${home_ok}/Library/Application Support/com.github.domt4.homebrew-autoupdate" "${home_ok}/Library/LaunchAgents"
cp "${REPO_ROOT}/home/dot_local/lib/python-ssl-compat/sitecustomize.py" "${home_ok}/.local/lib/python-ssl-compat/sitecustomize.py"
cat > "${home_ok}/.claude.json" <<'EOF'
{
  "mcpServers": {}
}
EOF
mkdir -p "${home_ok}/.claude"
cat > "${home_ok}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "latest"
}
EOF
# Pre-populate installed_plugins.json with the full expected LSP + general
# set so the healthy scenario passes both plugin checks. Shared helper lives
# in tests/lib/testlib.sh — keeps doctor.sh and ai-audit.sh fixtures in sync.
write_installed_plugins_stub "${home_ok}"
run_capture run_doctor "${home_ok}" \
  LAUNCHCTL_AUTUPDATE_LOADED=0 \
  BREW_FORMULAE=$'chezmoi\ngit\n' \
  BREW_CASKS=$'ghostty\n'
assert_eq "0" "${RUN_STATUS}" "doctor should pass in the healthy case"
assert_contains "${RUN_OUTPUT}" "Daily checks live in: make status / make ai-audit" "doctor should point to the lighter commands"
assert_contains "${RUN_OUTPUT}" "Brewfile: all packages present" "doctor should report Brewfile health"
assert_contains "${RUN_OUTPUT}" "auto-update channel: latest" "doctor should validate Claude channel"
assert_contains "${RUN_OUTPUT}" "brew autoupdate: disabled by dotfiles policy" "doctor should validate disabled brew autoupdate policy"
assert_contains "${RUN_OUTPUT}" "serena MCP: removed (native LSP plugins in use)" "doctor should confirm Serena is retired"
assert_contains "${RUN_OUTPUT}" "LSP plugins: all 12 installed" "doctor should confirm all LSP plugins are present"
assert_contains "${RUN_OUTPUT}" "general plugins: all 4 installed" "doctor should confirm all general plugins are present"
assert_contains "${RUN_OUTPUT}" "Google Cloud SDK" "doctor should detect gcloud version"
assert_contains "${RUN_OUTPUT}" "VERIFY_X509_STRICT bypass: active" "doctor should confirm SSL compat is active"
assert_contains "${RUN_OUTPUT}" "clasp 2.5.0" "doctor should detect clasp version"

# ---- Scenario 2: drift ----
home_drift="${tmpdir}/home-drift"
mkdir -p "${home_drift}/Library/Application Support/com.github.domt4.homebrew-autoupdate" "${home_drift}/Library/LaunchAgents"
mkdir -p "${home_drift}/.claude"
cat > "${home_drift}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "stable"
}
EOF
# Simulate a legacy Serena registration so the drift scenario exercises the
# retired-state warning path in doctor.
cat > "${home_drift}/.claude.json" <<EOF
{
  "mcpServers": {
    "serena": {
      "type": "stdio",
      "command": "${home_drift}/.local/bin/serena-mcp",
      "args": ["claude-code"]
    }
  }
}
EOF
cat > "${home_drift}/Library/Application Support/com.github.domt4.homebrew-autoupdate/brew_autoupdate" <<'EOF'
#!/bin/sh
/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade --formula -v
EOF
cat > "${home_drift}/Library/LaunchAgents/com.github.domt4.homebrew-autoupdate.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>StartInterval</key><integer>3600</integer></dict></plist>
EOF

# Hide clasp stub so drift scenario triggers the warning. Also drop any
# directory from ORIGINAL_PATH that exposes a real clasp binary — otherwise
# dev boxes with brew-installed clasp would shadow through from
# /opt/homebrew/bin after the STUB_BIN stub is moved.
mv "${STUB_BIN}/clasp" "${STUB_BIN}/_clasp.bak"

DOCTOR_TEST_PATH_OVERRIDE="${STUB_BIN}:${SANITIZED_PATH}" \
  run_capture run_doctor "${home_drift}" \
  LAUNCHCTL_AUTUPDATE_LOADED=1 \
  BREW_DOCTOR_CLT_WARN=1 \
  BREW_FORMULAE=$'chezmoi\ngit\n' \
  BREW_CASKS=$'ghostty\nbitwarden\n'

# Restore clasp stub
mv "${STUB_BIN}/_clasp.bak" "${STUB_BIN}/clasp"
assert_eq "0" "${RUN_STATUS}" "doctor should stay green when only optional drift warnings are present"
assert_contains "${RUN_OUTPUT}" "auto-update channel should be latest" "doctor should warn on Claude channel drift"
assert_contains "${RUN_OUTPUT}" "brew autoupdate: enabled, but dotfiles policy is disabled" "doctor should warn when brew autoupdate is enabled"
assert_contains "${RUN_OUTPUT}" "serena MCP: legacy registration detected" "doctor should warn when a legacy Serena MCP registration is still present"
assert_contains "${RUN_OUTPUT}" "LSP plugins missing" "doctor should warn when LSP plugins are not installed"
assert_contains "${RUN_OUTPUT}" "general plugins missing" "doctor should warn when general plugins are not installed"
assert_contains "${RUN_OUTPUT}" "VERIFY_X509_STRICT bypass: not active" "doctor should warn when SSL compat is missing"
assert_contains "${RUN_OUTPUT}" "clasp not found" "doctor should warn when clasp is missing"

pass_test "tests/doctor.sh"
