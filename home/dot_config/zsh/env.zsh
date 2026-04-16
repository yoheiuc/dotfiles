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

# Google Cloud SDK — force Python 3.12 for corporate proxy compatibility
# Python 3.13+ enables VERIFY_X509_STRICT by default, which rejects
# corporate CASB/proxy (Netskope, Zscaler etc.) MITM CA certificates
# that lack RFC 5280 compliance (basicConstraints not critical, missing AKI).
# Lookup order: python3.12 in PATH → uv-managed Python 3.12
if command -v python3.12 &>/dev/null; then
  export CLOUDSDK_PYTHON="$(command -v python3.12)"
elif command -v uv &>/dev/null; then
  _gcloud_py="$(uv python find 3.12 2>/dev/null || true)"
  if [[ -n "${_gcloud_py}" && -x "${_gcloud_py}" ]]; then
    export CLOUDSDK_PYTHON="${_gcloud_py}"
  fi
  unset _gcloud_py
fi

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
