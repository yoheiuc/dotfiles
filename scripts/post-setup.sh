#!/usr/bin/env bash
# post-setup.sh — additional setup that runs after dotfiles are applied
#
# Responsibility (imperative install layer; declarative file sync is chezmoi's job):
#   - Install/update Claude Code CLI via native installer and keep it on latest
#   - Register Claude Code marketplaces and install plugins listed in claude-plugins.sh
#     (LSP + general from claude-plugins-official, document skills from anthropic-agent-skills)
#   - Install clasp (via npm install -g @google/clasp)
#   - Install playwright-cli + Chromium + skill files under ~/.claude/skills
#   - Install Google Workspace CLI (gws) / find-skills / security-best-practices /
#     ui-ux-pro-max skills under ~/.claude/skills via `npx skills add ...`
#   - Keep brew-autoupdate disabled (manual brew update/upgrade policy)
#
# Out of scope (handled elsewhere; do not duplicate here):
#   - MCP server registration in ~/.claude.json   → scripts/ai-repair.sh
#   - settings.json baseline keys (hooks/effort)   → scripts/ai-repair.sh
#   - Drift detection / diff reporting             → scripts/ai-audit.sh
#
# Safe to re-run: already-configured items are skipped.
# Called automatically by: make install / make sync
#
# Usage: ./scripts/post-setup.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/lib/ui.sh"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"
source "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh"
source "${REPO_ROOT}/scripts/lib/claude-plugins.sh"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }

# ---- Claude Code CLI -------------------------------------------------------
log "Claude Code CLI..."

CLAUDE_SETTINGS_JSON="${HOME}/.claude/settings.json"
mkdir -p "$(dirname "${CLAUDE_SETTINGS_JSON}")"
ai_config_json_upsert_key "${CLAUDE_SETTINGS_JSON}" autoUpdatesChannel '"latest"'

if command -v claude &>/dev/null; then
  claude_path="$(command -v claude)"
  if [[ "${claude_path}" == "/opt/homebrew/bin/claude" ]]; then
    log "Migrating Claude Code from Homebrew to native latest..."
    claude install latest
    hash -r
  fi
  ok "Claude Code available: $(claude --version 2>/dev/null | head -1 || true)"
else
  log "Installing Claude Code native latest..."
  # Official Anthropic installer: https://claude.ai/install.sh (vendor-signed, pinned to latest channel).
  # curl | bash is the documented install path; see https://docs.anthropic.com/claude-code
  curl -fsSL https://claude.ai/install.sh | bash
  hash -r
  ok "Claude Code installed: $(claude --version 2>/dev/null | head -1 || true)"
fi
ok "Claude Code auto-update channel: latest"
unset CLAUDE_SETTINGS_JSON claude_path

# ---- Claude Code marketplace + plugins -------------------------------------
# Plugins live in two marketplaces:
#   * claude-plugins-official (LSP + general):  anthropics/claude-plugins-official
#   * anthropic-agent-skills  (document skills): anthropics/skills
# Both register-once + install-many; consolidated into one helper so adding a
# third marketplace later doesn't grow the duplication tax.
_install_claude_marketplace_plugins() {
  local marketplace_name="$1" marketplace_source="$2"
  shift 2
  local plugins=("$@")

  if jq -e --arg name "${marketplace_name}" \
      'has($name)' "${HOME}/.claude/plugins/known_marketplaces.json" >/dev/null 2>&1; then
    ok "marketplace ${marketplace_name}: already registered"
  else
    log "Adding marketplace ${marketplace_source}..."
    if claude plugin marketplace add "${marketplace_source}"; then
      ok "marketplace ${marketplace_name}: registered"
    else
      warn "marketplace add failed — run manually: claude plugin marketplace add ${marketplace_source}"
    fi
  fi

  local _plugin
  for _plugin in "${plugins[@]}"; do
    if claude_plugin_is_installed "${_plugin}" "${marketplace_name}"; then
      ok "plugin ${_plugin}@${marketplace_name}: already installed"
    else
      log "Installing plugin ${_plugin}@${marketplace_name}..."
      if claude plugin install "${_plugin}@${marketplace_name}"; then
        ok "plugin ${_plugin}@${marketplace_name}: installed"
      else
        warn "plugin ${_plugin} install failed — run manually: claude plugin install ${_plugin}@${marketplace_name}"
      fi
    fi
  done
}

log "Claude Code plugins (claude-plugins-official)..."

if command -v claude &>/dev/null; then
  _install_claude_marketplace_plugins \
    "${CLAUDE_PLUGIN_MARKETPLACE_NAME}" \
    "${CLAUDE_PLUGIN_MARKETPLACE_SOURCE}" \
    "${CLAUDE_LSP_PLUGINS[@]}" \
    "${CLAUDE_GENERAL_PLUGINS[@]}"

  log "Claude Code plugins (anthropic-agent-skills)..."
  _install_claude_marketplace_plugins \
    "${CLAUDE_DOCUMENT_MARKETPLACE_NAME}" \
    "${CLAUDE_DOCUMENT_MARKETPLACE_SOURCE}" \
    "${CLAUDE_DOCUMENT_PLUGINS[@]}"
else
  warn "claude not found — skipping plugin install"
fi

# ---- clasp (Google Apps Script CLI) ----------------------------------------
log "clasp..."

if command -v clasp &>/dev/null; then
  ok "clasp already installed: $(clasp --version 2>/dev/null | head -1 || true)"
else
  if ! command -v npm &>/dev/null; then
    warn "npm not found — run `make install` first."
    exit 1
  fi

  log "Installing clasp via npm..."
  npm install -g @google/clasp
  if command -v clasp &>/dev/null; then
    ok "clasp installed: $(clasp --version 2>/dev/null | head -1 || true)"
  else
    warn "clasp CLI still not found after install — open a new terminal and re-run."
    exit 1
  fi
fi

# ---- Playwright CLI --------------------------------------------------------
log "Playwright CLI..."

if command -v playwright-cli &>/dev/null; then
  ok "playwright-cli already installed: $(playwright-cli --version 2>/dev/null | head -1 || true)"
else
  if ! command -v npm &>/dev/null; then
    warn "npm not found — run `make install` first."
    exit 1
  fi

  log "Installing @playwright/cli via npm..."
  npm install -g @playwright/cli@latest
  hash -r
  if command -v playwright-cli &>/dev/null; then
    ok "playwright-cli installed: $(playwright-cli --version 2>/dev/null | head -1 || true)"
  else
    warn "playwright-cli still not found after install — open a new terminal and re-run."
    exit 1
  fi
fi

# Stealth は `~/.playwright/cli.config.json` 経由で `launchOptions.args` に
# `--disable-blink-features=AutomationControlled` を、`ignoreDefaultArgs` に
# `--enable-automation` を入れて `navigator.webdriver` を消す方式。設定ファイル
# 自体は chezmoi が `home/dot_playwright/cli.config.json` から配置するので
# post-setup 側では何もしない（doctor が適用を verify する）。
# 当初 rebrowser-patches で `playwright` を patch する Phase 1 を計画したが、
# Anthropic 配布の `@playwright/cli` が bundle 化した `playwright-core` の
# `lib/coreBundle.js` 一本化レイアウトと非互換で見送り（archive 2026-04-28）。

# Install Chromium browser (idempotent — CLI detects existing binaries).
# Don't silence output: Chromium download can take minutes on slow networks and
# the user should see progress.
if playwright-cli install-browser; then
  ok "playwright-cli: Chromium ready"
else
  warn "playwright-cli install-browser failed — run manually: playwright-cli install-browser"
fi

# Install skill files into ~/.claude/skills/playwright-cli.
# `playwright-cli install --skills` is CWD-relative and writes to
# `./.claude/skills/playwright-cli`, so force the CWD to $HOME — otherwise the
# skill dir lands wherever post-setup happens to be invoked from
# (e.g. the dotfiles checkout).
if (cd "${HOME}" && playwright-cli install --skills); then
  ok "playwright-cli: skills installed for Claude Code"
else
  warn "playwright-cli install --skills failed — run manually from \$HOME: (cd \"\${HOME}\" && playwright-cli install --skills)"
fi

# ---- Aider CLI -------------------------------------------------------------
log "Aider CLI..."

if command -v aider &>/dev/null; then
  ok "Aider already installed: $(aider --version 2>/dev/null | head -1 || true)"
else
  warn "aider not found — install via Brewfile (brew \"aider\")"
fi

# ---- ai-repair (Claude Code local drift) ----------------------------------
# ai-repair は Claude Code 設定ベースラインの補正と legacy MCP 掃除を担当。
# 5 baseline MCP (vision / sequential-thinking / exa / jamf-docs / slack) と
# settings.json の baseline 4 key、retired artifact の能動削除まで全部やる。
# post-setup の一環として必ず走らせる（冪等）。
bash "${REPO_ROOT}/scripts/ai-repair.sh"

# ---- Google Workspace CLI skills (Claude Code) ----------------------------
log "Google Workspace CLI skills..."

if ! command -v gws &>/dev/null; then
  warn "gws not found — run \`make install\` first (googleworkspace-cli)"
elif ! command -v npx &>/dev/null; then
  warn "npx not found — gws skills skipped (run \`make install\` first)"
else
  _dir="${HOME}/.claude/skills"
  mkdir -p "${_dir}"
  if compgen -G "${_dir}/gws-*/SKILL.md" >/dev/null; then
    ok "gws skills already present under ${_dir/#${HOME}/\~}"
  else
    log "Installing gws skills for claude-code into ${_dir/#${HOME}/\~} ..."
    if npx -y skills add https://github.com/googleworkspace/cli -a claude-code -g -y; then
      ok "gws skills installed"
    else
      warn "npx skills add failed — re-run or install manually"
    fi
  fi
  unset _dir
fi

# ---- find-skills (vercel-labs/skills) -------------------------------------
# find-skills lets Claude Code search and install further skills from
# natural-language queries (English keywords work best). `npx skills add
# -a claude-code` places the bundle under ~/.claude/skills/find-skills AND
# ~/.agents/skills/find-skills, so the agent can self-discover skills without
# manual /plugin install steps.
log "find-skills skill..."

if ! command -v npx &>/dev/null; then
  warn "npx not found — find-skills skipped (run \`make install\` first)"
else
  _dir="${HOME}/.claude/skills"
  mkdir -p "${_dir}"
  if [[ -f "${_dir}/find-skills/SKILL.md" ]]; then
    ok "find-skills already present under ${_dir/#${HOME}/\~}"
  else
    log "Installing find-skills for claude-code into ${_dir/#${HOME}/\~} ..."
    if npx -y skills add https://github.com/vercel-labs/skills -a claude-code -g -y --skill find-skills; then
      ok "find-skills installed"
    else
      warn "npx skills add failed — re-run or install manually"
    fi
  fi
  unset _dir
fi

# Notion: 2026-04-28 に ntn CLI + notion-cli skill から remote HTTP MCP
# (https://mcp.notion.com/mcp) に移行。CLI / skill 経由では routine の page CRUD
# 駆動が安定しなかった。MCP 登録は ai-repair.sh が担当、stale な
# `~/.claude/skills/notion-cli/` の rm も同 script で能動処理。

# ---- ui-ux-pro-max skill (nextlevelbuilder/ui-ux-pro-max-skill) -----------
# UI/UX design intelligence (50+ styles, 161 color palettes, 57 font pairings,
# 161 product types, 99 UX guidelines, 25 chart types across 10 stacks).
# Previously vendored under home/dot_claude/skills/ui-ux-pro-max/ (~1500 lines
# incl. 16 CSV data files and 3 Python scripts). Migrated 2026-04-26 to
# upstream npx-skills install — same tier-2 pattern as security-best-practices.
log "ui-ux-pro-max skill..."

if ! command -v npx &>/dev/null; then
  warn "npx not found — ui-ux-pro-max skipped (run \`make install\` first)"
else
  _dir="${HOME}/.claude/skills"
  mkdir -p "${_dir}"
  if [[ -f "${_dir}/ui-ux-pro-max/.upstream-installed" ]]; then
    ok "ui-ux-pro-max skill already installed from upstream under ${_dir/#${HOME}/\~}"
  else
    log "Installing ui-ux-pro-max skill for claude-code into ${_dir/#${HOME}/\~} ..."
    if npx -y skills add https://github.com/nextlevelbuilder/ui-ux-pro-max-skill -a claude-code -g -y --skill ui-ux-pro-max; then
      mkdir -p "${_dir}/ui-ux-pro-max"
      touch "${_dir}/ui-ux-pro-max/.upstream-installed"
      ok "ui-ux-pro-max skill installed"
    else
      warn "npx skills add failed — re-run or install manually"
    fi
  fi
  unset _dir
fi

# ---- security-best-practices skill (tech-leads-club/agent-skills) ---------
# Per-language security review references (Go, Python, JavaScript/TypeScript).
# Previously vendored under home/dot_claude/skills/security-best-practices/
# (~8K lines). Migrated 2026-04-26 to upstream npx-skills install — the
# upstream is `npx skills add` compatible, putting it on the L2 "upstream
# CLI skill distribution" tier above vendoring (which is the last resort).
# ai-repair.sh actively rms the stale vendored copy first so this re-install
# step on existing machines doesn't get short-circuited by the existence check.
log "security-best-practices skill..."

if ! command -v npx &>/dev/null; then
  warn "npx not found — security-best-practices skipped (run \`make install\` first)"
else
  _dir="${HOME}/.claude/skills"
  mkdir -p "${_dir}"
  # Marker `.upstream-installed` distinguishes upstream-installed copies from
  # legacy vendored ones; ai-repair.sh uses this to know whether to rm.
  if [[ -f "${_dir}/security-best-practices/.upstream-installed" ]]; then
    ok "security-best-practices skill already installed from upstream under ${_dir/#${HOME}/\~}"
  else
    log "Installing security-best-practices skill for claude-code into ${_dir/#${HOME}/\~} ..."
    if npx -y skills add https://github.com/tech-leads-club/agent-skills -a claude-code -g -y --skill security-best-practices; then
      # mkdir -p before touch: real installs create the dir, but test stubs
      # may not — defensive so the marker write never errors out and breaks
      # the install chain.
      mkdir -p "${_dir}/security-best-practices"
      touch "${_dir}/security-best-practices/.upstream-installed"
      ok "security-best-practices skill installed"
    else
      warn "npx skills add failed — re-run or install manually"
    fi
  fi
  unset _dir
fi

# ---- Homebrew share perms (zsh compinit) ----------------------------------
# Homebrew installs /opt/homebrew/share as group-writable (drwxrwxr-x), which
# zsh's compinit flags as "insecure" and prompts on every shell start. Drop
# group-write to silence the prompt. chmod is idempotent.
log "Homebrew share perms (zsh compinit)..."

_brew_share="${HOMEBREW_PREFIX:-/opt/homebrew}/share"
if [[ -d "${_brew_share}" ]]; then
  _before="$(stat -f '%Lp' "${_brew_share}" 2>/dev/null || echo '?')"
  chmod g-w "${_brew_share}"
  _after="$(stat -f '%Lp' "${_brew_share}" 2>/dev/null || echo '?')"
  if [[ "${_before}" != "${_after}" ]]; then
    ok "${_brew_share}: perms ${_before} -> ${_after} (dropped group-write)"
  else
    ok "${_brew_share}: perms ${_after}, already clean"
  fi
  unset _before _after
else
  warn "${_brew_share} not found — skipping compinit perms fix"
fi
unset _brew_share

# ---- brew autoupdate -------------------------------------------------------
log "brew autoupdate..."
launchctl bootout "gui/$(id -u)/$(brew_autoupdate_label)" >/dev/null 2>&1 || true
brew autoupdate delete >/dev/null 2>&1 || true
rm -f "$(brew_autoupdate_plist_path)" "$(brew_autoupdate_runner_path)"
ok "brew autoupdate: disabled by dotfiles policy"

printf '\nVerify with: make doctor\n'

if command -v playwright-cli >/dev/null 2>&1; then
  printf '\n\033[1mTo let agents drive an AI-dedicated browser (Microsoft Edge):\033[0m\n'
  printf '  policy: AI-driven browsing happens in a dedicated Edge profile,\n'
  printf '          isolated from your main Chrome (no Gmail / banking / admin).\n'
  printf '  stealth: ~/.playwright/cli.config.json (chezmoi 管理) が\n'
  printf '           --disable-blink-features=AutomationControlled / ignoreDefaultArgs:[--enable-automation]\n'
  printf '           を入れて navigator.webdriver を抑える。verify: pwedge https://bot.sannysoft.com/\n'
  printf '  one-time setup (per machine):\n'
  printf '    1. ensure microsoft-edge cask is installed: brew bundle --file ~/.Brewfile\n'
  printf '    2. (optional) override the profile dir in ~/.zshenv:\n'
  printf '         export PLAYWRIGHT_AI_EDGE_PROFILE=$HOME/.ai-edge\n'
  printf '  daily use:\n'
  printf '    pwedge https://example.com   (opens Edge headed, persistent profile)\n'
  printf '    → launch Claude Code from that shell; PLAYWRIGHT_CLI_SESSION=edge\n'
  printf '  rationale + risks: see ~/.claude/CLAUDE.md "ブラウザ自動化のセキュリティ規則" / "ブラウザ自動化の運用デフォルト"\n'
fi
