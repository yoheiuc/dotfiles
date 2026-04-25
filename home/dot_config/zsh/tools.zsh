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

  # Default options + Catppuccin Mocha palette (matches Ghostty / starship / Claude statusline).
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border
    --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
    --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
    --color=selected-bg:#45475a
    --color=border:#313244,label:#cdd6f4'
fi

# bat — syntax highlighter (also drives `delta` syntax theme via `delta.syntax-theme`).
command -v bat >/dev/null 2>&1 && export BAT_THEME="Catppuccin Mocha"
