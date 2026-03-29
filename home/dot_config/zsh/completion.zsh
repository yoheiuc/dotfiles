# completion.zsh — zsh completion system

# XDG-compliant completion cache
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

# Only call compinit once per session; skip insecure dirs check for speed
autoload -Uz compinit
compinit -C -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

# codex — register completion after compinit defines compdef
if command -v codex &>/dev/null; then
  eval "$(codex completion zsh 2>/dev/null | sed '/^WARNING: proceeding, even though we could not update PATH:/d')"
fi

# Style
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'  # case-insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

if (( $+functions[_codex] )); then
  compdef _codex cx cxf cxr cxd cxl
fi
