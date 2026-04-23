# env.zsh — environment variables and PATH
# shellcheck shell=bash disable=SC1090

# _zsh_cache_eval — cache `eval "$(cmd ...)"` output to a file and source it,
# regenerating only when the command binary is newer than the cache. Avoids
# forking a subprocess on every shell startup.
#   $1 = cache key (filename)
#   $2 = bin path (used as mtime reference)
#   $3 = command to run (shell string; eval'd)
_zsh_cache_eval() {
  local key="$1" bin="$2" cmd="$3"
  local dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/inits"
  local file="${dir}/${key}.zsh"
  [[ -x "$bin" || -f "$bin" ]] || return 1
  if [[ ! -s "$file" || "$bin" -nt "$file" ]]; then
    mkdir -p "$dir"
    eval "$cmd" > "$file" 2>/dev/null || { rm -f "$file"; return 1; }
  fi
  source "$file"
}

# Homebrew (Apple Silicon path; falls back gracefully on Intel)
if [[ -x /opt/homebrew/bin/brew ]]; then
  _zsh_cache_eval brew-shellenv /opt/homebrew/bin/brew '/opt/homebrew/bin/brew shellenv'
elif [[ -x /usr/local/bin/brew ]]; then
  _zsh_cache_eval brew-shellenv /usr/local/bin/brew '/usr/local/bin/brew shellenv'
fi

# User-local binaries (pip install --user, cargo install, etc.)
export PATH="${HOME}/.local/bin:${PATH}"

# Language defaults
export LANG="en_US.UTF-8"

# Default to a beginner-friendly terminal editor
export EDITOR="micro"
export VISUAL="${EDITOR}"

# Match bat theme to Ghostty (Catppuccin Mocha)
export BAT_THEME="Catppuccin Mocha"

# Default Python version for uv
export UV_PYTHON="3.12"

# Python 3.13 SSL compat — corporate CASB/proxy workaround (Netskope, Zscaler)
# Python 3.13+ enables VERIFY_X509_STRICT, which rejects MITM CA certificates
# that lack RFC 5280 compliance. sitecustomize.py restores 3.12-equivalent behaviour.
# To disable after certificate rotation: rm ~/.local/lib/python-ssl-compat/sitecustomize.py
_ssl_compat="${HOME}/.local/lib/python-ssl-compat"
if [[ -f "${_ssl_compat}/sitecustomize.py" ]]; then
  export PYTHONPATH="${_ssl_compat}${PYTHONPATH:+:${PYTHONPATH}}"
fi
unset _ssl_compat

# Claude Code — flicker-free fullscreen rendering
export CLAUDE_CODE_NO_FLICKER=1

