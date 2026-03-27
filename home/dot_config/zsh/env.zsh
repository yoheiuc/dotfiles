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
