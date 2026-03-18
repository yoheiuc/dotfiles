# tools.zsh — third-party tool hooks (existence-checked)

# direnv
if command -v direnv &>/dev/null; then
  eval "$(direnv hook zsh)"
fi

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
fi

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
