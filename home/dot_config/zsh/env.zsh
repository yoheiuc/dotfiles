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

# Persisted machine role for dotfiles operations
export DOTFILES_PROFILE="core"
_dotfiles_profile_path="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/profile"
if [[ -r "${_dotfiles_profile_path}" ]]; then
  _dotfiles_profile="$(tr -d '[:space:]' < "${_dotfiles_profile_path}")"
  [[ -n "${_dotfiles_profile}" ]] && export DOTFILES_PROFILE="${_dotfiles_profile}"
fi
unset _dotfiles_profile_path _dotfiles_profile
