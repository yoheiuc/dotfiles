# completion.zsh — zsh completion system

# XDG-compliant completion cache
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

# zsh-completions — extra completions from Homebrew (must be before compinit)
_zsh_completions="${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-completions"
[[ -d "$_zsh_completions" ]] && fpath=("$_zsh_completions" $fpath)
unset _zsh_completions

# compinit — skip insecure dirs check (-C) and precompile the dump to .zwc so
# zsh reads the binary form, which is noticeably faster on large dumps.
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
autoload -Uz compinit
compinit -C -d "$_zcompdump"
if [[ -s "$_zcompdump" && ( ! -s "${_zcompdump}.zwc" || "$_zcompdump" -nt "${_zcompdump}.zwc" ) ]]; then
  zcompile "$_zcompdump"
fi
unset _zcompdump

# codex — register completion after compinit defines compdef.
# Cached via _zsh_cache_eval (defined in env.zsh) to avoid forking codex each startup.
if _codex_bin="$(command -v codex 2>/dev/null)"; then
  _zsh_cache_eval codex-completion "$_codex_bin" \
    "codex completion zsh 2>/dev/null | sed '/^WARNING: proceeding, even though we could not update PATH:/d'"
fi
unset _codex_bin

# Style
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'  # case-insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

if (( $+functions[_codex] )); then
  compdef _codex cx cxf cxr cxd cxl
fi

# ---------- Homebrew zsh plugins (must be after compinit) ----------
# Loading order matters: you-should-use → autosuggestions → syntax-highlighting
# syntax-highlighting must be last (it wraps ZLE widgets set by earlier plugins).

_brew="${HOMEBREW_PREFIX:-/opt/homebrew}/share"

# you-should-use — reminds you of existing aliases
[[ -f "$_brew/zsh-you-should-use/you-should-use.plugin.zsh" ]] \
  && source "$_brew/zsh-you-should-use/you-should-use.plugin.zsh"

# autosuggestions — inline history suggestions (→ to accept)
[[ -f "$_brew/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] \
  && source "$_brew/zsh-autosuggestions/zsh-autosuggestions.zsh"

# syntax-highlighting — real-time command colouring (MUST be last)
[[ -f "$_brew/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] \
  && source "$_brew/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

unset _brew
