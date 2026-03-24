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

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# AI session launcher
alias ai='bash "${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi/scripts/ai-tmux.sh"'

# Repository navigation
alias qcd='cd "$(ghq root)/$(ghq list | fzf)"'
