#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-audit-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/home/.codex" "${tmpdir}/home/.claude" "${tmpdir}/home/.gemini"
mkdir -p "${tmpdir}/scripts/lib"
export HOME="${tmpdir}/home"

cp "${REPO_ROOT}/scripts/ai-audit.sh" "${tmpdir}/scripts/ai-audit.sh"
cp "${REPO_ROOT}/scripts/lib/ai-config.sh" "${tmpdir}/scripts/lib/ai-config.sh"
chmod +x "${tmpdir}/scripts/ai-audit.sh" "${tmpdir}/scripts/lib/ai-config.sh"

cat > "${HOME}/.codex/config.toml" <<'EOF'
model = "gpt-5.4"
EOF
: > "${HOME}/.claude/settings.json"
: > "${HOME}/.gemini/settings.json"
: > "${HOME}/.codex/hooks.json"
: > "${HOME}/.claude/CLAUDE.md"
: > "${HOME}/AGENTS.md"

run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should succeed in the clean case"
assert_contains "${RUN_OUTPUT}" "Codex config: present" "ai-audit should report local codex config"
assert_contains "${RUN_OUTPUT}" "Claude settings: present" "ai-audit should report local claude settings"
assert_contains "${RUN_OUTPUT}" "Codex config: no legacy bridge settings detected" "ai-audit should scan codex config"
assert_contains "${RUN_OUTPUT}" "AI config audit looks good." "ai-audit should summarize a clean state"

cat > "${HOME}/.codex/config.toml" <<'EOF'
# --- BEGIN CCB ---
approval_policy = "never"
sandbox_mode = "danger-full-access"
EOF
printf 'cc-bridge\n' > "${HOME}/.claude/settings.json"
rm -f "${HOME}/.gemini/settings.json"
: > "${HOME}/.codex/config.toml.pre-unmanage-test"

run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should stay informational with warnings"
assert_contains "${RUN_OUTPUT}" "Gemini settings: missing" "ai-audit should warn on missing gemini settings"
assert_contains "${RUN_OUTPUT}" "Codex config: legacy bridge or unsafe approval settings detected" "ai-audit should detect legacy codex settings"
assert_contains "${RUN_OUTPUT}" "Claude settings: legacy bridge or unsafe approval settings detected" "ai-audit should detect legacy claude settings"
assert_contains "${RUN_OUTPUT}" "Codex config backups: found backup files to review or delete" "ai-audit should report backup files"
assert_contains "${RUN_OUTPUT}" "AI config audit needs attention:" "ai-audit should summarize warnings"

pass_test "tests/ai-audit.sh"
