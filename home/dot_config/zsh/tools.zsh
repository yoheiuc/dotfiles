# tools.zsh — third-party tool hooks and wrappers (existence-checked)
# Each init output is cached via _zsh_cache_eval (defined in env.zsh) to avoid
# forking the tool's init subprocess on every shell startup.
# shellcheck shell=bash disable=SC1090

_tool_bin() { command -v "$1" 2>/dev/null; }

# starship prompt
_b="$(_tool_bin starship)" && _zsh_cache_eval starship "$_b" 'starship init zsh'

# zoxide — smart cd
_b="$(_tool_bin zoxide)" && _zsh_cache_eval zoxide "$_b" 'zoxide init zsh'

# atuin — shell history
if _b="$(_tool_bin atuin)"; then
  _zsh_cache_eval atuin "$_b" 'atuin init zsh'
  bindkey '?' self-insert
fi

# navi — interactive cheatsheet (Ctrl+G)
_b="$(_tool_bin navi)" && _zsh_cache_eval navi "$_b" 'navi widget zsh'

# direnv — per-directory env vars
_b="$(_tool_bin direnv)" && _zsh_cache_eval direnv "$_b" 'direnv hook zsh'

unset _b
unfunction _tool_bin

dothelp() {
  local repo_root=""

  if [[ -x "${HOME}/dotfiles/scripts/dotfiles-help.sh" ]]; then
    repo_root="${HOME}/dotfiles"
  elif [[ -x "${HOME}/.local/share/chezmoi/scripts/dotfiles-help.sh" ]]; then
    repo_root="${HOME}/.local/share/chezmoi"
  else
    echo "dotfiles-help.sh が見つかりません" >&2
    return 1
  fi

  DOTFILES_REPO_ROOT="${repo_root}" bash "${repo_root}/scripts/dotfiles-help.sh" "$@"
}

# gemini — one-shot prompt helpers
_gemini_require() {
  if ! command -v gemini >/dev/null 2>&1; then
    echo "gemini CLI が見つかりません" >&2
    return 127
  fi
}

_gemini_current_diff() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "git 管理下のディレクトリで実行してください" >&2
    return 1
  fi

  local staged working
  staged="$(git diff --cached -- .)"
  working="$(git diff -- .)"

  if [[ -z "$staged$working" ]]; then
    echo "レビュー対象の差分がありません" >&2
    return 1
  fi

  if [[ -n "$staged" ]]; then
    printf '%s\n\n%s' "### Staged diff" "$staged"
  fi

  if [[ -n "$working" ]]; then
    [[ -n "$staged" ]] && printf '\n\n'
    printf '%s\n\n%s' "### Working tree diff" "$working"
  fi
}

gr() {
  _gemini_require || return

  if (( $# == 0 )); then
    echo "usage: gr <prompt>" >&2
    return 1
  fi

  command gemini -p "$*"
}

gmr() {
  _gemini_require || return

  local diff extra prompt
  diff="$(_gemini_current_diff)" || return
  extra="$*"
  prompt="以下の差分をコードレビューしてください。バグ、回帰、テスト不足だけを優先し、重大度順に短く指摘してください。要約や称賛は不要です。"

  if [[ -n "$extra" ]]; then
    prompt="${prompt}

追加指示:
${extra}"
  fi

  command gemini -p "${prompt}

対象差分:
${diff}"
}

gms() {
  _gemini_require || return

  local diff extra prompt
  diff="$(_gemini_current_diff)" || return
  extra="$*"
  prompt="以下の差分を簡潔に要約してください。何が変わったか、気をつける点、次にやるとよい確認を短く整理してください。"

  if [[ -n "$extra" ]]; then
    prompt="${prompt}

追加指示:
${extra}"
  fi

  command gemini -p "${prompt}

対象差分:
${diff}"
}

gmd() {
  _gemini_require || return

  local diff extra prompt
  diff="$(_gemini_current_diff)" || return
  extra="$*"
  prompt="以下の差分を読み、変更の意図・影響・見落としやすいリスクを短く説明してください。"

  if [[ -n "$extra" ]]; then
    prompt="${prompt}

追加指示:
${extra}"
  fi

  command gemini -p "${prompt}

対象差分:
${diff}"
}

# gcloud — Google Cloud SDK shell completions
_gcloud_inc="${HOMEBREW_PREFIX:-/opt/homebrew}/share/google-cloud-sdk"
if [[ -d "${_gcloud_inc}" ]]; then
  [[ -f "${_gcloud_inc}/path.zsh.inc" ]]       && source "${_gcloud_inc}/path.zsh.inc"
  [[ -f "${_gcloud_inc}/completion.zsh.inc" ]]  && source "${_gcloud_inc}/completion.zsh.inc"
fi
unset _gcloud_inc

# fzf — fuzzy finder
if command -v fzf &>/dev/null; then
  # Shell completions
  _fzf_completion="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/completion.zsh"
  _fzf_keybinds="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh"
  [[ -f "$_fzf_completion" ]] && source "$_fzf_completion"
  [[ -f "$_fzf_keybinds"   ]] && source "$_fzf_keybinds"
  unset _fzf_completion _fzf_keybinds

  # Default options
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
fi
