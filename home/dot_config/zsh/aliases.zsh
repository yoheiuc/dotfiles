# aliases.zsh — shell aliases

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

# Codex shortcuts
alias cx='codex'
alias cxf='codex -p fast'
alias cxr='codex -p review'
alias cxd='codex -p deep'
alias cxl='codex resume --last'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'


# Repository navigation
alias qcd='cd "$(ghq root)/$(ghq list | fzf)"'
