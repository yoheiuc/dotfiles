# dotfiles

Personal macOS dotfiles managed with [chezmoi](https://chezmoi.io).

## Prerequisites

| Tool | Install |
|------|---------|
| macOS (Apple Silicon or Intel) | — |
| [Homebrew](https://brew.sh) | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Git | bundled with Xcode CLT or via `brew install git` |

All other tools (chezmoi, Ghostty, Claude Code, …) are declared in `Brewfile` and installed by the bootstrap script.

## Quick Start

```bash
# 1. Clone
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. Bootstrap (installs packages, applies dotfiles, registers Serena MCP)
bash scripts/bootstrap.sh
```

That's it. Open a new terminal session to pick up your zsh config.

## Verify

```bash
bash scripts/doctor.sh
```

Checks:
- `brew bundle` — all packages present
- `chezmoi diff` — no unapplied changes
- `ghostty +show-config` — config readable
- `claude --version` + `claude mcp list` — Claude Code + Serena

## Superpowers Plugin

After Claude Code is installed, enable Superpowers:

```bash
# In any Claude Code session:
/plugin install superpowers
```

## Rollback

Dotfiles are tracked in git. To undo any change:

```bash
git revert <commit>          # or: git checkout <commit> -- <file>
chezmoi apply                # re-sync to $HOME
```

For a full machine reset, re-run `scripts/bootstrap.sh` from the reverted commit.

## Structure

```
dotfiles/
├── .chezmoiroot              # tells chezmoi: source root is home/
├── Brewfile                  # declarative package list
├── home/                     # chezmoi source state (→ $HOME)
│   ├── dot_zshrc             # ~/.zshrc (entry point only)
│   ├── dot_claude/
│   │   └── settings.json     # Claude Code permissions + env
│   └── dot_config/
│       ├── ghostty/          # config.ghostty + core/ui/keybinds modules
│       ├── zsh/              # env / aliases / tools / completion modules
│       └── starship.toml
├── scripts/
│   ├── bootstrap.sh          # one-shot provisioning
│   └── doctor.sh             # health check
└── .github/workflows/
    └── ci.yml                # shellcheck + brew bundle on macOS
```

## Key Design Choices

- **chezmoi** — encrypted-safe, diff-aware dotfile management; no symlink mess.
- **Split configs** — each tool has an entry file that `config-file`/`source`s focused modules; easy to add/remove/override without editing the entry file.
- **Serena MCP** — installed at user scope so every project gets language-aware context in Claude Code automatically.
- **Permissions** — `settings.json` denies destructive shell commands and credential paths by default; `git push` and web fetches require explicit approval.
