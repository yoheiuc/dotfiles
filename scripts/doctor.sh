#!/usr/bin/env bash
# doctor.sh — verify dotfiles setup health
#
# Exit code: 0 = all required checks passed, 1 = at least one required check failed
# Optional (warn-only) items never affect the exit code.
#
# Usage: ./scripts/doctor.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"
source "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh"

ok()      { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn()    { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
fail()    { printf '  \033[1;31m✗\033[0m  %s\n' "$*"; REQUIRED_FAILED=1; }
info()    { printf '  - %s\n' "$*"; }
section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }

REQUIRED_FAILED=0

echo
printf '\033[1m=== dotfiles doctor ===\033[0m\n'
info "Daily checks live in: make status / make ai-audit"

# ===========================================================================
# REQUIRED checks — failures increment REQUIRED_FAILED and affect exit code
# ===========================================================================

section "Xcode Command Line Tools (required)"
if xcode-select -p &>/dev/null; then
  clt_path="$(xcode-select -p)"
  ok "CLT installed: ${clt_path}"

  # Check for Swift execution (basic JIT/REPL test)
  if ! swift -e "print(0)" &>/dev/null; then
    fail "CLT is installed but broken (Swift execution failed) — run: sudo rm -rf ${clt_path} && xcode-select --install"
  fi

  # Check if brew doctor reports deeper CLT/Swift issues or updates.
  # Since brew doctor can be slow, we'll only scan for specific CLT-related strings.
  # This catches the "No Cask quarantine support available" and "A newer release is available" cases.
  clt_brew_warnings="$(brew doctor 2>&1 | grep -Ei "Command Line Tools|Swift compilation failed" || true)"
  if [[ -n "${clt_brew_warnings}" ]]; then
    warn "Homebrew reported CLT issues or updates:"
    printf '%s\n' "${clt_brew_warnings}" | sed 's/^/    /'
    warn "  Recommended: update from Software Update or run: sudo rm -rf ${clt_path} && xcode-select --install"
  fi
else
  fail "CLT not found — run: xcode-select --install"
fi

section "Homebrew (required)"
if brew --version &>/dev/null; then
  ok "brew $(brew --version | head -1)"
else
  fail "brew not found — install from https://brew.sh"
fi

section "chezmoi (required)"
if chezmoi --version &>/dev/null; then
  ok "$(chezmoi --version)"

  # chezmoi doctor — runs built-in self-checks (gpg, age, diff tool, etc.)
  printf '  chezmoi doctor:\n'
  chezmoi_doctor_out="$(chezmoi doctor 2>&1 || true)"
  printf '%s\n' "$chezmoi_doctor_out" | sed 's/^/    /'
  if printf '%s\n' "$chezmoi_doctor_out" | grep -Ev '^[[:space:]]*failed[[:space:]]+latest-version[[:space:]]' | grep -Eq '^[[:space:]]*failed[[:space:]]'; then
    warn "chezmoi doctor: reported failed checks above"
  fi

  # Pending diff (warn only — user may intentionally defer apply)
  diff_out=$(chezmoi diff 2>&1 || true)
  if [[ -z "$diff_out" ]]; then
    ok "chezmoi diff: clean (no pending changes)"
  else
    warn "chezmoi diff: unapplied changes detected"
    warn "  Preview: chezmoi apply -n -v"
  fi
else
  fail "chezmoi not found — run: brew install chezmoi"
fi

section "Brewfile (required)"
brew_check_out="$(bash "${REPO_ROOT}/scripts/brew-bundle.sh" check 2>&1 || true)"
if printf '%s\n' "$brew_check_out" | grep -q "The Brewfile's dependencies are satisfied."; then
  ok "Brewfile: all packages present"
else
  fail "Brewfile: missing packages — run: make sync"
  printf '%s\n' "$brew_check_out" | grep -v '^Using ' | sed 's/^/    /' || true
fi

section "Git identity/privacy (required)"
expected_hooks_path="${HOME}/.config/git/hooks"

git_name="$(git config --global --get user.name || true)"
git_email="$(git config --global --get user.email || true)"
git_hooks_path="$(git config --global --path --get core.hooksPath || true)"

if [[ -n "${git_name}" ]]; then
  ok "git user.name: ${git_name}"
else
  fail "git user.name is unset — configure your git identity"
fi

if [[ -n "${git_email}" ]]; then
  ok "git user.email: ${git_email}"
else
  fail "git user.email is unset — configure your git identity"
fi

if [[ "${git_hooks_path}" == "${expected_hooks_path}" ]]; then
  ok "git hooksPath: ${git_hooks_path}"
else
  fail "git hooksPath mismatch — expected '${expected_hooks_path}', got '${git_hooks_path:-<unset>}'"
fi

if [[ -x "${expected_hooks_path}/pre-commit" ]]; then
  ok "git pre-commit hook: present"
else
  fail "git pre-commit hook missing — run: chezmoi apply"
fi

# ===========================================================================
# OPTIONAL checks — warn only, never fail the script
# ===========================================================================

section "zsh compinit security (optional)"
if command -v zsh &>/dev/null; then
  _compaudit_out="$(zsh -fc 'autoload -Uz compaudit; compaudit' 2>/dev/null || true)"
  if [[ -z "${_compaudit_out}" ]]; then
    ok "compaudit: no insecure directories"
  else
    warn "compaudit flagged insecure directories (triggers compinit prompt on shell start):"
    printf '%s\n' "${_compaudit_out}" | sed 's/^/    /'
    warn "  Fix with: chmod g-w <dir>  (most common offender: /opt/homebrew/share)"
  fi
  unset _compaudit_out
else
  warn "zsh not found — skipping compaudit check"
fi

section "node (optional)"
if node --version &>/dev/null; then
  ok "node $(node --version)"
else
  warn "node not found — needed for Codex CLI installs via npm"
fi

section "playwright-cli (optional)"
if command -v playwright-cli &>/dev/null; then
  ok "$(playwright-cli --version 2>&1 | head -1)"
  # Attach to user's logged-in Chrome (playwright-cli v0.1.8+) requires
  # Chrome 144+ and remote debugging toggled on via chrome://inspect. These
  # can't be introspected from a shell; just surface the checklist.
  info "real-Chrome attach (pwattach): Chrome 144+ + chrome://inspect/#remote-debugging ON"
else
  warn "playwright-cli not found — run: ./scripts/post-setup.sh"
fi

section "ntn (Notion CLI, optional)"
if command -v ntn &>/dev/null; then
  ok "ntn $(ntn --version 2>&1 | head -1 || true)"
else
  warn "ntn not found — run: ./scripts/post-setup.sh"
fi

section "mmdc (mermaid-cli, optional)"
if command -v mmdc &>/dev/null; then
  ok "mmdc $(mmdc --version 2>&1 | head -1 || true)"
else
  warn "mmdc not found — install via Brewfile (brew \"mermaid-cli\")"
fi

section "pandoc (optional)"
if command -v pandoc &>/dev/null; then
  ok "$(pandoc --version 2>&1 | head -1)"
else
  warn "pandoc not found — install via Brewfile (brew \"pandoc\")"
fi

section "pdflatex (optional, for Pandoc PDF output)"
if command -v pdflatex &>/dev/null; then
  ok "pdflatex: available ($(pdflatex --version 2>&1 | head -1 || true))"
else
  warn "pdflatex not found — install via Brewfile (cask \"basictex\") and restart shell"
fi

section "uv (optional)"
if uv --version &>/dev/null; then
  ok "$(uv --version)"
else
  warn "uv not found — needed for Serena MCP (uvx)"
fi

section "brew-autoupdate (optional)"
if command -v launchctl >/dev/null 2>&1 && command -v plutil >/dev/null 2>&1; then
  if brew_autoupdate_is_loaded || [[ -f "$(brew_autoupdate_plist_path)" ]]; then
    warn "brew autoupdate: enabled, but dotfiles policy is disabled — run: ./scripts/post-setup.sh"
  else
    ok "brew autoupdate: disabled by dotfiles policy"
  fi
else
  warn "brew autoupdate audit skipped — launchctl/plutil unavailable"
fi

section "Serena config (optional)"
SERENA_CONFIG_PATH="${HOME}/.serena/serena_config.yml"
if [[ -f "${SERENA_CONFIG_PATH}" ]]; then
  ok "serena config: present (${SERENA_CONFIG_PATH})"

  if ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^language_backend:[[:space:]]*LSP([[:space:]]|$)'; then
    ok "serena config: language_backend = LSP"
  else
    warn "serena config: language_backend is not LSP"
  fi

  if ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^web_dashboard:[[:space:]]*true([[:space:]]|$)'; then
    ok "serena config: web_dashboard = true"
  else
    warn "serena config: web_dashboard should be true"
  fi

  if ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^web_dashboard_open_on_launch:[[:space:]]*false([[:space:]]|$)'; then
    ok "serena config: dashboard auto-open disabled"
  else
    warn "serena config: web_dashboard_open_on_launch should be false"
  fi

  if ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^project_serena_folder_location:[[:space:]]*"\$projectDir/\.serena"([[:space:]]|$)'; then
    ok "serena config: project metadata stored in-project"
  else
    warn 'serena config: project_serena_folder_location should be "$projectDir/.serena"'
  fi
else
  warn "serena config missing — expected at ${SERENA_CONFIG_PATH}"
fi
unset SERENA_CONFIG_PATH

section "gcloud (optional)"
if command -v gcloud &>/dev/null; then
  gcloud_version_line="$(gcloud version 2>&1 | head -1 || true)"
  if [[ -n "$gcloud_version_line" ]]; then
    ok "$gcloud_version_line"
  else
    warn "gcloud found but version returned no usable output"
  fi
else
  warn "gcloud not found — install via Brewfile (cask \"gcloud-cli\")"
fi

section "Python SSL compat (optional)"
_ssl_compat_file="${HOME}/.local/lib/python-ssl-compat/sitecustomize.py"
if [[ -f "${_ssl_compat_file}" ]]; then
  ok "VERIFY_X509_STRICT bypass: active (${_ssl_compat_file})"
  ok "To disable after cert rotation: rm ${_ssl_compat_file/#${HOME}/\~}"
else
  warn "VERIFY_X509_STRICT bypass: not active"
  warn "  Python 3.13+ may fail behind corporate CASB/proxies (Netskope, Zscaler)"
  warn "  Restore with: chezmoi apply"
fi
unset _ssl_compat_file

section "Ghostty (optional)"
# Ghostty CLI may not be in PATH when installed as a .app bundle.
# /Applications/Ghostty.app/Contents/MacOS/ghostty is the binary path.
_ghostty=""
if command -v ghostty &>/dev/null; then
  _ghostty="ghostty"
elif [[ -x "/Applications/Ghostty.app/Contents/MacOS/ghostty" ]]; then
  _ghostty="/Applications/Ghostty.app/Contents/MacOS/ghostty"
fi

if [[ -n "$_ghostty" ]]; then
  if ghostty_version_out="$("$_ghostty" --version 2>&1)"; then
    ghostty_version_line="$(printf '%s\n' "$ghostty_version_out" | grep '^Ghostty' | head -1 || true)"
    if [[ -n "$ghostty_version_line" ]]; then
      ok "ghostty ${ghostty_version_line}"
    else
      warn "ghostty CLI returned unexpected output"
      warn "  $(printf '%s\n' "$ghostty_version_out" | head -1)"
    fi
  else
    warn "ghostty CLI found but --version failed"
    warn "  $(printf '%s\n' "$ghostty_version_out" | head -1)"
  fi
else
  warn "ghostty not found in PATH or /Applications — install via Brewfile (cask \"ghostty\")"
fi
unset _ghostty


section "zellij (optional)"
if zellij --version &>/dev/null; then
  ok "$(zellij --version 2>&1 | head -1)"
else
  warn "zellij not found — install via Brewfile (brew 'zellij')"
fi

section "ghq (optional)"
if ghq --version &>/dev/null; then
  ok "$(ghq --version 2>&1 | head -1)"
else
  warn "ghq not found — install via Brewfile (brew \"ghq\")"
fi

section "navi (optional)"
if command -v navi &>/dev/null; then
  ok "$(navi --version 2>&1 | head -1)"
  _navi_cheats="${HOME}/.local/share/navi/cheats/dotfiles"
  if [[ -d "$_navi_cheats" ]]; then
    _navi_cheat_count="$(find "${_navi_cheats}" -maxdepth 1 -type f -name '*.cheat' | wc -l | tr -d ' ')"
  else
    _navi_cheat_count="0"
  fi
  if [[ "${_navi_cheat_count}" != "0" ]]; then
    ok "navi cheatsheets: present (${_navi_cheat_count} files)"
  else
    warn "navi cheatsheets not found — run: chezmoi apply"
  fi
  unset _navi_cheats _navi_cheat_count
else
  warn "navi not found — install via Brewfile (brew \"navi\")"
fi

section "Claude Code (optional)"
if command -v claude &>/dev/null; then
  ok "$(claude --version 2>&1 | head -1)"
  if [[ "$(ai_config_json_read "${HOME}/.claude/settings.json" "d.get('autoUpdatesChannel','')" 2>/dev/null || true)" == "latest" ]]; then
    ok "auto-update channel: latest"
  else
    warn "auto-update channel should be latest — run: ./scripts/post-setup.sh"
  fi
  _claude_json="${HOME}/.claude.json"
  case "$(ai_config_mcp_registration_state "${_claude_json}" serena "${HOME}/.local/bin/serena-mcp")" in
    ok)
      ok "serena MCP: registered"
      ;;
    wrong-command)
      warn "serena MCP: registered with wrong command — run: make ai-repair"
      ;;
    missing)
      warn "serena MCP: not registered — run: make ai-repair"
      ;;
  esac
  unset _claude_json

  if [[ -f "${HOME}/.claude/skills/frontend-design/SKILL.md" ]]; then
    ok "frontend-design skill: present"
  else
    warn "frontend-design skill missing — run: chezmoi apply"
  fi

  if [[ -f "${HOME}/.claude/skills/find-skills/SKILL.md" ]]; then
    ok "find-skills skill: present"
  else
    warn "find-skills skill missing — run: ./scripts/post-setup.sh"
  fi
else
  warn "claude not found — run: ./scripts/post-setup.sh"
fi

section "Gemini CLI (optional)"
if command -v gemini &>/dev/null; then
  ok "$(gemini --version 2>&1 | head -1 || true)"
else
  warn "gemini not found — install via Brewfile (brew \"gemini-cli\")"
fi

section "clasp (optional)"
if command -v clasp &>/dev/null; then
  ok "clasp $(clasp --version 2>/dev/null | head -1 || true)"
else
  warn "clasp not found — run: ./scripts/post-setup.sh"
fi

section "Codex (optional)"
if command -v codex &>/dev/null; then
  codex_version_line="$(codex --version 2>&1 | head -1)"
  if [[ -n "$codex_version_line" ]]; then
    ok "$codex_version_line"
  else
    warn "codex found but --version returned no usable output"
  fi

  _codex_config="${HOME}/.codex/config.toml"
  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('model','')" 2>/dev/null || true)" == "gpt-5.4" ]]; then
    ok "default model: gpt-5.4"
  else
    warn "default model should be gpt-5.4 — run: make ai-repair"
  fi

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('sandbox_mode','')" 2>/dev/null || true)" == "workspace-write" ]]; then
    ok "sandbox mode: workspace-write"
  else
    warn "sandbox mode should be workspace-write — run: make ai-repair"
  fi

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('approval_policy','')" 2>/dev/null || true)" == "on-request" ]]; then
    ok "approval policy: on-request"
  else
    warn "approval policy should be on-request — run: make ai-repair"
  fi

  case "$(ai_config_codex_mcp_state "${_codex_config}" "${HOME}/.local/bin/serena-mcp")" in
    ok)
      ok "serena MCP: registered via wrapper"
      ;;
    wrong-command)
      warn "serena MCP: registered with wrong command — run: make ai-repair"
      ;;
    missing)
      warn "serena MCP: not registered — run: make ai-repair"
      ;;
  esac

  if grep -q 'codex_hooks[[:space:]]*=[[:space:]]*true' "${_codex_config}" 2>/dev/null; then
    ok "codex hooks: enabled"
  else
    warn "codex hooks: disabled — set [features].codex_hooks = true"
  fi

  case "$(ai_config_codex_mcp_url_state "${_codex_config}" openaiDeveloperDocs "https://developers.openai.com/mcp")" in
    ok)
      ok "OpenAI Docs MCP: registered"
      ;;
    wrong-url)
      warn "OpenAI Docs MCP: wrong URL — run: make ai-repair"
      ;;
    missing)
      warn "OpenAI Docs MCP: missing — run: make ai-repair"
      ;;
  esac
  unset _codex_config

  if [[ -f "${HOME}/.codex/hooks.json" ]]; then
    ok "codex hooks.json: present"
  else
    warn "codex hooks.json missing — run: chezmoi apply"
  fi

  if [[ -f "${HOME}/.codex/skills/codex-auto-save-memory/scripts/autosave_memory.py" ]]; then
    ok "codex auto-save memory skill: present"
  else
    warn "codex auto-save memory skill missing — run: chezmoi apply"
  fi

  # `npx skills add` now uses ~/.agents/skills/ as the unified location for
  # Codex-tagged skills, even when `-a codex` is passed. Check both for
  # forward/backward compatibility.
  if [[ -f "${HOME}/.codex/skills/find-skills/SKILL.md" \
     || -f "${HOME}/.agents/skills/find-skills/SKILL.md" ]]; then
    ok "find-skills skill: present"
  else
    warn "find-skills skill missing — run: ./scripts/post-setup.sh"
  fi
else
  warn "codex not found — install Codex CLI separately"
fi

# ===========================================================================
# Result
# ===========================================================================

echo
if [[ "$REQUIRED_FAILED" -eq 0 ]]; then
  printf '\033[1;32mAll required checks passed.\033[0m\n\n'
  printf 'Use `make status` for the quick pass and `make doctor` when you want deeper verification.\n'
else
  printf '\033[1;31m%d required check(s) failed — see above.\033[0m\n\n' "$REQUIRED_FAILED"
  exit 1
fi
