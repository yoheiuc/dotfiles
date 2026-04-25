# scripts/lib/claude-plugins.sh — shared list of Claude Code plugins owned by dotfiles.
# Sourced by post-setup.sh and doctor.sh so the install path and the verify path
# stay in sync. Add a plugin here, run `make install`, and `make doctor` will
# verify it on the next run.

# Per-language LSP plugins from anthropics/claude-plugins-official. Used by
# Claude Code's native LSP tool for symbol resolution, find-references,
# rename, hover, and diagnostics — strictly more accurate than grep for
# code-structure work.
CLAUDE_LSP_PLUGINS=(
  clangd-lsp
  csharp-lsp
  gopls-lsp
  jdtls-lsp
  kotlin-lsp
  lua-lsp
  php-lsp
  pyright-lsp
  ruby-lsp
  rust-analyzer-lsp
  swift-lsp
  typescript-lsp
)

# General-purpose plugins from anthropics/claude-plugins-official. Curated to
# avoid overlap with existing slash commands (/review, /ultrareview,
# /security-review), the `simplify` skill, and the gh / playwright-cli /
# Exa MCP integrations already in place.
CLAUDE_GENERAL_PLUGINS=(
  claude-md-management      # audit / session learning capture for CLAUDE.md
  claude-code-setup         # propose hooks / skills / MCP / subagents from a codebase
  feature-dev               # subagent workflow: explore → design → review
  explanatory-output-style  # opt-in output style with implementation rationale
)

CLAUDE_PLUGIN_MARKETPLACE_NAME="claude-plugins-official"
CLAUDE_PLUGIN_MARKETPLACE_SOURCE="anthropics/claude-plugins-official"

# Returns 0 if `<name>@claude-plugins-official` is recorded as installed in
# ~/.claude/plugins/installed_plugins.json. The file is missing entirely until
# the first `claude plugin install` runs, so non-existence == not installed.
claude_plugin_is_installed() {
  local name="$1"
  local file="${HOME}/.claude/plugins/installed_plugins.json"
  [[ -f "${file}" ]] || return 1
  jq -e --arg key "${name}@${CLAUDE_PLUGIN_MARKETPLACE_NAME}" \
    '.plugins | has($key)' "${file}" >/dev/null 2>&1
}
