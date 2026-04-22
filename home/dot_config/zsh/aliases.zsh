# aliases.zsh — shell aliases
# shellcheck shell=bash

# Modern replacements
alias ls='eza --icons'
alias ll='eza -lah --icons --git'
alias cat='bat --paging=never'
alias grep='rg'
alias find='fd'

# Git shortcuts
alias g='git'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'


# AI tools
# `-D` を `--dangerously-skip-permissions` に展開する共通ラッパ。
# （claude native の `-d` は `--debug` なので、衝突を避けて大文字 `-D` を採用）
_cc() {
  local a args=()
  for a in "$@"; do
    if [[ "$a" == "-D" ]]; then
      args+=(--dangerously-skip-permissions)
    else
      args+=("$a")
    fi
  done
  command claude "${args[@]}"
}
cc()  { _cc "$@"; }
ccc() { _cc --continue "$@"; }
ccr() { _cc --resume "$@"; }

# Repository navigation
alias qcd='cd "$(ghq root)/$(ghq list | fzf)"'
