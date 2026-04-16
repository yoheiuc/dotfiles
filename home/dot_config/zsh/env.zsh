# env.zsh — environment variables and PATH

# Homebrew (Apple Silicon path; falls back gracefully on Intel)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
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

# Persisted machine role for dotfiles operations
export DOTFILES_PROFILE="core"
_dotfiles_profile_path="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/profile"
if [[ -r "${_dotfiles_profile_path}" ]]; then
  _dotfiles_profile="$(tr -d '[:space:]' < "${_dotfiles_profile_path}")"
  [[ -n "${_dotfiles_profile}" ]] && export DOTFILES_PROFILE="${_dotfiles_profile}"
fi
unset _dotfiles_profile_path _dotfiles_profile
