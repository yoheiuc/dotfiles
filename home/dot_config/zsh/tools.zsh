# tools.zsh — third-party tool hooks and wrappers (existence-checked)

# starship prompt
if command -v starship &>/dev/null; then
  eval "$(starship init zsh)"
fi

# zoxide — smart cd
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi

# atuin — shell history
if command -v atuin &>/dev/null; then
  eval "$(atuin init zsh)"
  bindkey '?' self-insert
fi

# navi — interactive cheatsheet (Ctrl+G)
if command -v navi &>/dev/null; then
  eval "$(navi widget zsh)"
fi

dotprofile() {
  printf '%s\n' "${DOTFILES_PROFILE:-core}"
}

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
