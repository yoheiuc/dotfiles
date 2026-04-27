#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-repair-test.XXXXXX")"
# `${REPO_ROOT}/.serena` is also scrubbed by ai-repair, so the fixture we plant
# below should always be removed by it. Add it to the trap defensively in case
# the test errors out before ai-repair runs; .serena/ is gitignored Serena-MCP
# residue and per L2 policy is meant to be removed.
trap 'rm -rf "${tmpdir}" "${REPO_ROOT}/.serena"' EXIT

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

# Fixtures: Serena residue in both home dir and repo root must be scrubbed by
# ai-repair. ~/.serena is the runtime cache + memories Serena MCP wrote;
# ${REPO_ROOT}/.serena/ is project-local residue (gitignored). Both directories
# are not cleared by `chezmoi apply` alone.
mkdir -p "${HOME}/.serena/cache"
mkdir -p "${REPO_ROOT}/.serena/cache"

# Fixtures: legacy vendored document skills (replaced by document-skills plugin
# in the anthropic-agent-skills marketplace). ai-repair should rm them so the
# plugin's skills become the single source.
for _legacy_doc in doc pdf presentation spreadsheet; do
  mkdir -p "${HOME}/.claude/skills/${_legacy_doc}"
  printf 'stub vendored SKILL\n' > "${HOME}/.claude/skills/${_legacy_doc}/SKILL.md"
done
unset _legacy_doc

run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed on first run"
assert_contains "${RUN_OUTPUT}" "Serena: removed retired ~/.serena" "ai-repair should remove ~/.serena residue"
assert_contains "${RUN_OUTPUT}" "Serena: removed retired" "ai-repair should announce repo-local .serena removal"
[[ ! -e "${HOME}/.serena" ]] || fail_test "ai-repair should physically remove ~/.serena directory"
[[ ! -e "${REPO_ROOT}/.serena" ]] || fail_test "ai-repair should physically remove ${REPO_ROOT}/.serena directory"
for _legacy_doc in doc pdf presentation spreadsheet; do
  assert_contains "${RUN_OUTPUT}" "Document skills: removed legacy vendored ~/.claude/skills/${_legacy_doc}" "ai-repair should announce removal of vendored ${_legacy_doc} skill"
  [[ ! -e "${HOME}/.claude/skills/${_legacy_doc}" ]] || fail_test "ai-repair should physically remove vendored ${_legacy_doc} skill"
done
unset _legacy_doc
assert_contains "${RUN_OUTPUT}" "Claude Code: auto-update channel set to latest" "ai-repair should normalize Claude Code channel"
assert_contains "${RUN_OUTPUT}" "Claude Code: ENABLE_TOOL_SEARCH env set" "ai-repair should set ENABLE_TOOL_SEARCH env"
assert_contains "${RUN_OUTPUT}" "Claude Code: effortLevel set to high" "ai-repair should set effortLevel to high (dotfiles baseline)"
assert_contains "${RUN_OUTPUT}" "Claude Code: hooks reset to baseline" "ai-repair should install baseline hooks"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"autoUpdatesChannel": "latest"' "ai-repair should write Claude auto-update channel"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"ENABLE_TOOL_SEARCH": "auto:5"' "ai-repair should write ENABLE_TOOL_SEARCH env toggle"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"effortLevel": "high"' "ai-repair should write effortLevel high"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"command": "$HOME/.claude/lsp-hint.sh"' "ai-repair should wire lsp-hint PreToolUse hook"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"command": "$HOME/.claude/auto-save.sh"' "ai-repair should wire auto-save Stop hook"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"command": "$HOME/.claude/chezmoi-auto-apply.sh"' "ai-repair should wire chezmoi-auto-apply Stop hook"

# Local-managed keys (permissions / model / statusLine) must be preserved:
# Claude Code writes them itself, dotfiles must not clobber them.
# effortLevel is now baseline-managed (snap-back to high), so a local
# `/effort medium` is overwritten on the next ai-repair — verified separately.
python3 -c "
import json
p = '${HOME}/.claude/settings.json'
with open(p) as f: d = json.load(f)
d['permissions'] = {'allow': ['Read(*)'], 'deny': ['Bash(rm*)']}
d['model'] = 'opus[1m]'
d['effortLevel'] = 'medium'
d['statusLine'] = {'type': 'command', 'command': 'my-statusline'}
with open(p, 'w') as f: json.dump(d, f, indent=2); f.write('\n')
"
run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed on re-run after user-local edits"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"Read(*)"' "ai-repair must preserve user-managed permissions.allow"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"Bash(rm*)"' "ai-repair must preserve user-managed permissions.deny"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"model": "opus[1m]"' "ai-repair must preserve user-managed model"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"effortLevel": "high"' "ai-repair must snap effortLevel back to high baseline"
assert_contains "${RUN_OUTPUT}" "Claude Code: effortLevel set to high" "ai-repair should re-set effortLevel after user override"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"command": "my-statusline"' "ai-repair must preserve user-managed statusLine"

# Verify Claude Code JSON registration
assert_not_contains "$(cat "${HOME}/.claude.json")" '"serena"' "ai-repair should not register retired Serena MCP for Claude Code"
assert_not_contains "$(cat "${HOME}/.claude.json")" '"github"' "ai-repair should not register removed GitHub MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"exa"' "ai-repair should register Exa MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"url": "https://mcp.exa.ai/mcp?tools=web_search_exa,web_fetch_exa,web_search_advanced_exa"' "ai-repair should set Exa MCP URL with all 3 tools enabled"
assert_contains "$(cat "${HOME}/.claude.json")" '"jamf-docs"' "ai-repair should register Jamf docs MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"url": "https://developer.jamf.com/mcp"' "ai-repair should set Jamf docs MCP URL for Claude Code"
assert_not_contains "$(cat "${HOME}/.claude.json")" 'mcp.notion.com' "ai-repair should not register retired Notion MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"slack"' "ai-repair should register Slack MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"url": "https://mcp.slack.com/mcp"' "ai-repair should set Slack MCP URL for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"callbackPort": 3118' "ai-repair should include Slack OAuth callbackPort"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@modelcontextprotocol/server-filesystem' "ai-repair should not register retired filesystem MCP for Claude Code"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@drawio/mcp@latest' "ai-repair should not register retired drawio MCP for Claude Code"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@playwright/mcp@latest' "ai-repair should not register retired Playwright MCP for Claude Code"
assert_not_contains "$(cat "${HOME}/.claude.json")" 'chrome-devtools-mcp@latest' "ai-repair should not register retired chrome-devtools MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"vision"' "ai-repair should register vision MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '@tuannvm/vision-mcp-server' "ai-repair should set Claude vision MCP args"
assert_contains "$(cat "${HOME}/.claude.json")" '"sequential-thinking"' "ai-repair should register sequential-thinking MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '@modelcontextprotocol/server-sequential-thinking' "ai-repair should set Claude sequential-thinking MCP args"
assert_not_contains "$(cat "${HOME}/.claude.json")" '"brave-search"' "ai-repair should not register retired Brave Search MCP for Claude Code"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@modelcontextprotocol/server-brave-search' "ai-repair should not set retired Claude Brave Search MCP args"

# Re-run should be idempotent
run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed on re-run"
assert_contains "${RUN_OUTPUT}" "already registered" "ai-repair should detect existing registration"
assert_contains "${RUN_OUTPUT}" "auto-update channel already set to latest" "ai-repair should detect existing Claude baseline"

# Legacy MCP removal — simulate an old dotfiles install and verify convergence.
python3 -c "
import json
p = '${HOME}/.claude.json'
with open(p) as f: d = json.load(f)
d.setdefault('mcpServers', {})['playwright'] = {
  'type': 'stdio', 'command': 'npx', 'args': ['-y', '@playwright/mcp@latest']
}
d['mcpServers']['filesystem'] = {
  'type': 'stdio', 'command': 'bash',
  'args': ['-lc', 'npx -y @modelcontextprotocol/server-filesystem \"\$HOME\"']
}
d['mcpServers']['drawio'] = {
  'type': 'stdio', 'command': 'npx', 'args': ['-y', '@drawio/mcp@latest']
}
d['mcpServers']['notion'] = {
  'type': 'http', 'url': 'https://mcp.notion.com/mcp'
}
d['mcpServers']['github'] = {
  'type': 'stdio', 'command': 'npx',
  'args': ['-y', '@modelcontextprotocol/server-github']
}
d['mcpServers']['owlocr'] = {
  'type': 'stdio', 'command': 'bash',
  'args': ['-lc', 'uvx --quiet --from git+https://github.com/jangisaac-dev/owlocr-mcp owlocr-mcp']
}
d['mcpServers']['chrome-devtools'] = {
  'type': 'stdio', 'command': 'npx',
  'args': ['-y', 'chrome-devtools-mcp@latest']
}
d['mcpServers']['brave-search'] = {
  'type': 'stdio', 'command': '${HOME}/.local/bin/mcp-with-keychain-secret',
  'args': ['BRAVE_API_KEY', 'dotfiles.ai.mcp', 'brave-api-key', 'npx', '-y', '@modelcontextprotocol/server-brave-search']
}
d['mcpServers']['serena'] = {
  'type': 'stdio', 'command': '${HOME}/.local/bin/serena-mcp',
  'args': ['claude-code'], 'env': {'UV_NATIVE_TLS': 'true'}
}
with open(p, 'w') as f: json.dump(d, f, indent=2); f.write('\n')
"

run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed when purging legacy MCPs"
assert_contains "${RUN_OUTPUT}" "legacy playwright MCP removed" "ai-repair should announce legacy playwright removal"
assert_contains "${RUN_OUTPUT}" "legacy filesystem MCP removed" "ai-repair should announce legacy filesystem removal"
assert_contains "${RUN_OUTPUT}" "legacy drawio MCP removed" "ai-repair should announce legacy drawio removal"
assert_contains "${RUN_OUTPUT}" "legacy notion MCP removed" "ai-repair should announce legacy notion removal"
assert_contains "${RUN_OUTPUT}" "legacy github MCP removed" "ai-repair should announce legacy github removal"
assert_contains "${RUN_OUTPUT}" "legacy owlocr MCP removed" "ai-repair should announce legacy owlocr removal"
assert_contains "${RUN_OUTPUT}" "legacy chrome-devtools MCP removed" "ai-repair should announce legacy chrome-devtools removal"
assert_contains "${RUN_OUTPUT}" "legacy brave-search MCP removed" "ai-repair should announce legacy brave-search removal"
assert_contains "${RUN_OUTPUT}" "legacy serena MCP removed" "ai-repair should announce legacy serena removal"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@playwright/mcp@latest' "ai-repair should strip legacy playwright from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@modelcontextprotocol/server-filesystem' "ai-repair should strip legacy filesystem from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@drawio/mcp@latest' "ai-repair should strip legacy drawio from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" 'mcp.notion.com' "ai-repair should strip legacy notion from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@modelcontextprotocol/server-github' "ai-repair should strip legacy github from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" 'jangisaac-dev/owlocr-mcp' "ai-repair should strip legacy owlocr from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" 'chrome-devtools-mcp@latest' "ai-repair should strip legacy chrome-devtools from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@modelcontextprotocol/server-brave-search' "ai-repair should strip legacy brave-search from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" '/.local/bin/serena-mcp' "ai-repair should strip legacy serena wrapper reference from .claude.json"

# Retired session-topic hook cleanup — simulate an old dotfiles install that
# had the Haiku session-topic feature installed, and verify convergence:
# the orphan UserPromptSubmit entry gets stripped from settings.json by the
# wholesale hooks rewrite, and the script file + cache dir are actively
# removed by the orphan cleanup loop.
touch "${HOME}/.claude/session-topic.sh"
chmod +x "${HOME}/.claude/session-topic.sh"
mkdir -p "${HOME}/.claude/session-topics"
touch "${HOME}/.claude/session-topics/abc123.count"
# Dead ~/.claude/.mcp.json (Claude Code never loaded it; chezmoi source removed
# 2026-04-26). ai-repair should rm it on existing machines.
printf '{"mcpServers":{}}\n' > "${HOME}/.claude/.mcp.json"
# Leftover Serena wrapper should be cleaned by the same retired-helper loop.
mkdir -p "${HOME}/.local/bin"
touch "${HOME}/.local/bin/serena-mcp"
chmod +x "${HOME}/.local/bin/serena-mcp"
# Leftover Serena state dir (cache + memories) — chezmoi never managed it,
# so ai-repair should rm it actively. Mirrors the Codex retire pattern.
mkdir -p "${HOME}/.serena/cache"
mkdir -p "${HOME}/.serena/memories"
: > "${HOME}/.serena/cache/dummy"
# Leftover vendored frontend-design skill should also be cleaned.
mkdir -p "${HOME}/.claude/skills/frontend-design"
: > "${HOME}/.claude/skills/frontend-design/SKILL.md"
# Retired slash commands (E refactor 2026-04-26) — simulate machines that
# synced before the source files were deleted; ai-repair should rm them.
mkdir -p "${HOME}/.claude/commands"
for _retired in api-design ci debug diagram doc docker notebook pdf perf playwright presentation refactor research screenshot security-review spreadsheet test ui-ux; do
  : > "${HOME}/.claude/commands/${_retired}.md"
done
unset _retired
python3 -c "
import json
p = '${HOME}/.claude/settings.json'
with open(p) as f: d = json.load(f)
d.setdefault('hooks', {})['UserPromptSubmit'] = [{
  'matcher': '',
  'hooks': [{'type': 'command', 'command': '\$HOME/.claude/session-topic.sh'}]
}]
with open(p, 'w') as f: json.dump(d, f, indent=2); f.write('\n')
"
run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed when cleaning retired session-topic hook"
assert_contains "${RUN_OUTPUT}" "removed retired helper" "ai-repair should announce session-topic.sh removal"
assert_contains "${RUN_OUTPUT}" "removed retired session-topics cache" "ai-repair should announce session-topics cache removal"
assert_not_contains "$(cat "${HOME}/.claude/settings.json")" 'session-topic.sh' "ai-repair should strip orphan UserPromptSubmit hook from settings.json"
assert_not_contains "$(cat "${HOME}/.claude/settings.json")" 'UserPromptSubmit' "ai-repair should leave no UserPromptSubmit hook entry in settings.json"
[[ ! -e "${HOME}/.claude/session-topic.sh" ]] || fail_test "session-topic.sh should be removed"
[[ ! -d "${HOME}/.claude/session-topics" ]] || fail_test "session-topics cache dir should be removed"
[[ ! -e "${HOME}/.claude/.mcp.json" ]] || fail_test "dead ~/.claude/.mcp.json should be removed"
assert_contains "${RUN_OUTPUT}" "removed dead ~/.claude/.mcp.json" "ai-repair should announce dead .mcp.json removal"
[[ ! -e "${HOME}/.local/bin/serena-mcp" ]] || fail_test "retired serena-mcp wrapper should be removed"
[[ ! -e "${HOME}/.serena" ]] || fail_test "retired ~/.serena state dir should be removed"
assert_contains "${RUN_OUTPUT}" "Serena: removed retired ~/.serena" "ai-repair should announce ~/.serena cleanup"
[[ ! -d "${HOME}/.claude/skills/frontend-design" ]] || fail_test "retired vendored frontend-design skill should be removed"
assert_contains "${RUN_OUTPUT}" "removed retired vendored skill" "ai-repair should announce frontend-design cleanup"

# Retired slash commands should all be gone, with at least one announcement.
assert_contains "${RUN_OUTPUT}" "removed retired slash command" "ai-repair should announce retired slash command cleanup"
for _retired in api-design ci debug diagram doc docker notebook pdf perf playwright presentation refactor research screenshot security-review spreadsheet test ui-ux; do
  [[ ! -e "${HOME}/.claude/commands/${_retired}.md" ]] || fail_test "retired slash command ${_retired}.md should be removed"
done
unset _retired

pass_test "tests/ai-repair.sh"
