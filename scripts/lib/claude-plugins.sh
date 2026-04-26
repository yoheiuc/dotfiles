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
  frontend-design           # aesthetic guideline for Web frontend (complements ui-ux-pro-max DB)
  microsoft-docs            # MS Learn search / fetch + code reference for Azure / .NET / M365
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

# Render the install summary for one plugin group (LSP / general / ...) on
# stdout, and return 0 if the group is fully installed, 1 if any plugin is
# missing. Caller picks the UI wrapper (ok / warn / attention) per its tone.
#
# Usage:  claude_plugins_check_summary <label> <missing_predicate_fn> <total>
#   if msg="$(claude_plugins_check_summary LSP claude_lsp_plugins_missing "${#CLAUDE_LSP_PLUGINS[@]}")"; then
#     ok "$msg"
#   else
#     attention "$msg"
#   fi
#
# Living in this lib so doctor.sh and ai-audit.sh can never drift in
# message shape (which they did before this helper existed).
claude_plugins_check_summary() {
  local label="$1" predicate_fn="$2" total="$3"
  local missing_list missing_count
  missing_list="$("${predicate_fn}" | tr '\n' ' ')"
  missing_list="${missing_list% }"
  if [[ -z "${missing_list// /}" ]]; then
    printf '%s plugins: all %s installed (via %s)\n' \
      "${label}" "${total}" "${CLAUDE_PLUGIN_MARKETPLACE_NAME}"
    return 0
  fi
  missing_count="$("${predicate_fn}" | wc -l | tr -d ' ')"
  printf '%s plugins missing (%s/%s): %s — run: ./scripts/post-setup.sh\n' \
    "${label}" "${missing_count}" "${total}" "${missing_list}"
  return 1
}
