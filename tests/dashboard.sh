#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-dashboard-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

fake_repo="${tmpdir}/repo"
output_path="${tmpdir}/dashboard.md"
mkdir -p "${fake_repo}/scripts"

cat > "${fake_repo}/scripts/status.sh" <<'EOF'
#!/usr/bin/env bash
printf '\033[1m=== dotfiles status ===\033[0m\n'
printf 'Active profile: home\n'
printf '\n[Repo]\n'
printf '  \033[1;32m✓\033[0m  git: main...origin/main\n'
printf '  \033[1;33m⚠\033[0m  working tree: local changes detected\n'
EOF

cat > "${fake_repo}/scripts/ai-audit.sh" <<'EOF'
#!/usr/bin/env bash
printf '\033[1m=== AI config audit ===\033[0m\n'
printf '\n[Local Config Files]\n'
printf '  - Codex config: present (/tmp/home/.codex/config.toml, 12 bytes)\n'
printf '  \033[1;32m✓\033[0m  Codex config: no legacy bridge settings detected\n'
printf '  \033[1;33m⚠\033[0m  Gemini settings: missing (/tmp/home/.gemini/settings.json)\n'
EOF

cp "${REPO_ROOT}/scripts/dashboard.sh" "${fake_repo}/scripts/dashboard.sh"
chmod +x "${fake_repo}/scripts/status.sh" "${fake_repo}/scripts/ai-audit.sh" "${fake_repo}/scripts/dashboard.sh"

run_capture env DOTFILES_REPO_ROOT="${fake_repo}" bash "${fake_repo}/scripts/dashboard.sh" "${output_path}"
assert_eq "0" "${RUN_STATUS}" "dashboard should succeed"
assert_contains "${RUN_OUTPUT}" "Generated Markdown dashboard:" "dashboard should print the output path"
assert_contains "${RUN_OUTPUT}" "status warnings: 1" "dashboard should count status warnings"
assert_contains "${RUN_OUTPUT}" "ai audit warnings: 1" "dashboard should count audit warnings"

dashboard_contents="$(cat "${output_path}")"
assert_contains "${dashboard_contents}" "# Dotfiles Dashboard" "dashboard markdown should have a title"
assert_contains "${dashboard_contents}" '- Active profile: `home`' "dashboard should summarize the active profile"
assert_contains "${dashboard_contents}" "- Status summary: 1 warning(s)" "dashboard should summarize status warnings"
assert_contains "${dashboard_contents}" "- AI audit summary: 1 warning(s)" "dashboard should summarize audit warnings"
assert_contains "${dashboard_contents}" "## Status Highlights" "dashboard should include status highlights"
assert_contains "${dashboard_contents}" "- git: main...origin/main" "dashboard should capture status highlights"
assert_contains "${dashboard_contents}" "- working tree: local changes detected" "dashboard should keep warning highlights"
assert_contains "${dashboard_contents}" "## AI Highlights" "dashboard should include ai highlights"
assert_contains "${dashboard_contents}" "- Codex config: present (/tmp/home/.codex/config.toml, 12 bytes)" "dashboard should include ai file highlights"
assert_contains "${dashboard_contents}" "## Raw Status Output" "dashboard should include raw status output"
assert_contains "${dashboard_contents}" "## Raw AI Audit Output" "dashboard should include raw ai output"
assert_not_contains "${dashboard_contents}" $'\033' "dashboard markdown should not contain ANSI escapes"

pass_test "tests/dashboard.sh"
