#!/usr/bin/env bash
# tests/post-setup.sh — verify scripts/post-setup.sh idempotency.
#
# Full integration testing of post-setup.sh would require stubbing ~10 external
# CLIs (claude, clasp, playwright-cli, ntn, npm, npx, curl, brew,
# launchctl, uvx, stat). Instead, this test focuses on the property that
# actually matters — **running post-setup.sh twice produces identical config
# files** — by stubbing every CLI to the "already installed" path and
# asserting that the sha256 of ~/.claude/settings.json, ~/.claude.json, and
# the brew-autoupdate cleanup state does not change between runs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-post-setup-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

export HOME="${tmpdir}/home"
mkdir -p "${HOME}/.claude" "${HOME}/.agents/skills" "${HOME}/.local/bin"

stub_bin="${tmpdir}/bin"
mkdir -p "${stub_bin}"

# ---- Stubs for every external CLI that post-setup.sh may invoke ------------
# All stubs take the "already installed / success" path so the script's
# conditional branches pick the no-op route.

make_stub() {
  local name="$1"
  local body="$2"
  cat > "${stub_bin}/${name}" <<EOF
#!/usr/bin/env bash
${body}
EOF
  chmod +x "${stub_bin}/${name}"
}

make_stub claude 'case "${1:-}" in
  --version) echo "claude 1.0.0 (native)"; exit 0 ;;
  install) exit 0 ;;
  plugin|plugins)
    case "${2:-}" in
      marketplace) exit 0 ;;
      install) exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac'

make_stub clasp 'echo "clasp 3.0.0"; exit 0'
make_stub playwright-cli 'case "${1:-}" in
  --version) echo "playwright-cli 0.1.8" ;;
  install-browser) exit 0 ;;
  install) exit 0 ;;
  *) exit 0 ;;
esac'
make_stub aider 'echo "aider 0.50.0"; exit 0'
make_stub ntn 'echo "ntn 0.10.0"; exit 0'
make_stub uvx 'exit 0'
make_stub npm 'exit 0'
make_stub npx 'case "${1:-}" in
  -y)
    # `npx -y skills add ...` — treat as success (skills already installed).
    exit 0
    ;;
  *) exit 0 ;;
esac'
make_stub curl 'exit 0'
make_stub launchctl 'exit 1  # "not loaded" is the expected post-setup.sh path'
make_stub brew 'case "${1:-}" in
  autoupdate) exit 0 ;;
  *) exit 0 ;;
esac'

# Pre-populate skill SKILL.md files so post-setup takes the "already present" path
# and does not attempt network install via npx.
mkdir -p "${HOME}/.claude/skills/find-skills" "${HOME}/.agents/skills/find-skills"
printf 'stub\n' > "${HOME}/.claude/skills/find-skills/SKILL.md"
printf 'stub\n' > "${HOME}/.agents/skills/find-skills/SKILL.md"
mkdir -p "${HOME}/.claude/skills/notion-cli"
printf 'stub\n' > "${HOME}/.claude/skills/notion-cli/SKILL.md"

# Pre-populate ~/.claude.json so the sequential-thinking upsert has a parseable base.
cat > "${HOME}/.claude.json" <<'EOF'
{
  "mcpServers": {}
}
EOF

# Pre-populate Claude Code plugin state so post-setup takes the "already
# installed" branch for the marketplace + each LSP plugin (idempotent path).
mkdir -p "${HOME}/.claude/plugins"
cat > "${HOME}/.claude/plugins/known_marketplaces.json" <<'EOF'
{
  "claude-plugins-official": {
    "source": {"source": "github", "repo": "anthropics/claude-plugins-official"}
  }
}
EOF
# Build installed_plugins.json from the same list doctor / post-setup use.
source "${REPO_ROOT}/scripts/lib/claude-plugins.sh"
{
  printf '{\n  "plugins": {\n'
  _sep=""
  for _p in "${CLAUDE_LSP_PLUGINS[@]}" "${CLAUDE_GENERAL_PLUGINS[@]}"; do
    printf '%s    "%s@%s": {}' "${_sep}" "${_p}" "${CLAUDE_PLUGIN_MARKETPLACE_NAME}"
    _sep=$',\n'
  done
  printf '\n  }\n}\n'
} > "${HOME}/.claude/plugins/installed_plugins.json"
unset _p _sep

# brew-autoupdate: no plist exists, so the cleanup no-op is the expected path.

# ai-repair.sh is called by post-setup.sh when uvx is present. Stub that too
# by short-circuiting the subprocess — post-setup calls it via `bash
# "${REPO_ROOT}/scripts/ai-repair.sh"`. We override by making the script
# a no-op via env, but the cleanest route is to intercept uvx to "not found"
# so post-setup takes the warn-and-skip branch.
rm -f "${stub_bin}/uvx"  # remove uvx so `command -v uvx` fails

# Homebrew prefix dir so the compinit perms block doesn't error.
export HOMEBREW_PREFIX="${tmpdir}/brew"
mkdir -p "${HOMEBREW_PREFIX}/share"

# Hermetic env for the `env -i … bash post-setup.sh` callsites below.
# Base values (HOME / PATH / TMPDIR / TERM / locale) live in
# tests/lib/testlib.sh#hermetic_base_env_init — see that function for the
# rationale (parent-shell leak prevention). PATH points at our stubs (plus
# minimal system dirs for cat / printf / stat etc.) so post-setup takes the
# "already installed" no-op path; HOMEBREW_PREFIX is extended in so the
# script's compinit perms block doesn't error.
hermetic_base_env_init "${stub_bin}:/usr/bin:/bin:/usr/sbin:/sbin"
HERMETIC_BASE_ENV+=(HOMEBREW_PREFIX="${HOMEBREW_PREFIX}")

hash_file() {
  if [[ -f "$1" ]]; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'missing\n'
  fi
}

# ---- Run 1 -----------------------------------------------------------------
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/post-setup.sh"
assert_eq "0" "${RUN_STATUS}" "post-setup first run should succeed"
assert_contains "${RUN_OUTPUT}" "Claude Code auto-update channel: latest" "post-setup should normalize Claude channel"
# sequential-thinking is now registered by ai-repair.sh (post-setup calls it),
# so the message comes through that subscript: "sequential-thinking MCP registered"
assert_contains "${RUN_OUTPUT}" "sequential-thinking MCP" "post-setup should register sequential-thinking via ai-repair"
assert_contains "${RUN_OUTPUT}" "brew autoupdate: disabled by dotfiles policy" "post-setup should disable brew autoupdate"
assert_contains "${RUN_OUTPUT}" "marketplace claude-plugins-official: already registered" "post-setup should skip marketplace add when present"
assert_contains "${RUN_OUTPUT}" "plugin pyright-lsp@claude-plugins-official: already installed" "post-setup should skip already-installed LSP plugin"
assert_contains "${RUN_OUTPUT}" "plugin claude-md-management@claude-plugins-official: already installed" "post-setup should skip already-installed general plugin"
# Sanity check: no traces of the retired bulk-installed skill groups should
# leak back into post-setup (gws / recipe / persona / document-skills).
assert_not_contains "${RUN_OUTPUT}" "gws skills" "post-setup should not install gws bulk skills any more"
assert_not_contains "${RUN_OUTPUT}" "anthropic-agent-skills" "post-setup should not touch the retired anthropic-agent-skills marketplace"

hash_settings_1="$(hash_file "${HOME}/.claude/settings.json")"
hash_claudejson_1="$(hash_file "${HOME}/.claude.json")"

# ---- Run 2 -----------------------------------------------------------------
run_capture env -i "${HERMETIC_BASE_ENV[@]}" \
  bash "${REPO_ROOT}/scripts/post-setup.sh"
assert_eq "0" "${RUN_STATUS}" "post-setup second run (idempotent) should succeed"
assert_contains "${RUN_OUTPUT}" "sequential-thinking MCP already registered" "second run should skip re-registering sequential-thinking"

hash_settings_2="$(hash_file "${HOME}/.claude/settings.json")"
hash_claudejson_2="$(hash_file "${HOME}/.claude.json")"

assert_eq "${hash_settings_1}" "${hash_settings_2}" "${HOME}/.claude/settings.json should be byte-identical across two runs"
assert_eq "${hash_claudejson_1}" "${hash_claudejson_2}" "${HOME}/.claude.json should be byte-identical across two runs"

pass_test "tests/post-setup.sh"
