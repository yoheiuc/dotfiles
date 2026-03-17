# dotfiles

Personal macOS dotfiles managed with [chezmoi](https://chezmoi.io).

---

## Prerequisites

| | |
|---|---|
| **macOS** (Apple Silicon or Intel) | |
| **Homebrew** | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| **Git** | Xcode CLT (`xcode-select --install`) or `brew install git` |

Everything else (chezmoi, Ghostty, Claude Code, zsh tools…) is in `home/dot_Brewfile` and installed by `bootstrap.sh`.

---

## Initial Setup (new Mac)

```bash
# 1. Clone
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. Bootstrap: installs packages + applies dotfiles
bash scripts/bootstrap.sh

# 3. Open a new terminal to load the zsh config, then run post-setup
bash scripts/post-setup.sh   # registers Serena MCP into Claude Code

# 4. Verify
bash scripts/doctor.sh
```

### bootstrap.sh vs post-setup.sh

| Script | What it does | Re-runnable? |
|--------|-------------|--------------|
| `bootstrap.sh` | brew check → install chezmoi → `brew bundle` → `chezmoi init --apply` | Yes (idempotent) |
| `post-setup.sh` | Registers Serena MCP into Claude Code | Yes (skips if already registered) |

`bootstrap.sh` is intentionally minimal — it only ensures the machine has the right packages and dotfiles applied.
`post-setup.sh` handles "post-dotfiles" configuration that runs after the environment is in place.

---

## Day-to-day: Updating dotfiles

After `bootstrap.sh` has been run once, chezmoi knows its source directory
(`~/.local/share/chezmoi` → `~/dotfiles`). No `--source` flag is needed.

```bash
cd ~/dotfiles
git pull
chezmoi apply             # apply changes to $HOME
brew bundle --global      # sync any new packages in ~/.Brewfile
```

---

## Health Check

```bash
bash scripts/doctor.sh
```

| Check | Type | Pass condition |
|-------|------|----------------|
| `brew --version` | Required | Homebrew is installed |
| `chezmoi --version` | Required | chezmoi is installed |
| `chezmoi doctor` | Required | chezmoi self-checks pass |
| `brew bundle check --global` | Required | All Brewfile packages present |
| `uv --version` | Optional | uv installed (needed by Serena MCP) |
| `ghostty --version` | Optional | Ghostty installed |
| `claude --version` | Optional | Claude Code CLI available |
| `claude mcp list` (Serena) | Optional | Serena MCP registered |

Exit code is 0 only when all **required** checks pass.

---

## Rollback

```bash
# Undo a specific file change
git checkout <commit> -- home/dot_config/zsh/tools.zsh
chezmoi apply

# Undo the last commit and re-apply
git revert HEAD
chezmoi apply
```

Full restore on a new machine: clone the reverted state and re-run `bootstrap.sh`.

---

## Brewfile

`home/dot_Brewfile` is managed by chezmoi and deploys to `~/.Brewfile`.
Homebrew natively reads `~/.Brewfile` via `brew bundle --global`.

| Context | Command |
|---------|---------|
| Initial install (before `chezmoi apply`) | `brew bundle --file=~/dotfiles/home/dot_Brewfile` |
| After first apply | `brew bundle --global` |
| Verify | `brew bundle check --global` |

---

## Ghostty Config

The config is split into focused modules under `~/.config/ghostty/`:

| File | Purpose |
|------|---------|
| `config.ghostty` | Entry point — loads the modules below |
| `core.ghostty` | Shell integration, scrollback, window behaviour |
| `ui.ghostty` | Font, Catppuccin Mocha theme, padding |
| `keybinds.ghostty` | Key overrides (defaults are macOS-standard) |
| `local.ghostty` | **Machine-local overrides — not tracked in git** |

### Local overrides

For per-machine settings (font size on an external display, an experimental colour scheme, etc.), create `~/.config/ghostty/local.ghostty`:

```
# ~/.config/ghostty/local.ghostty  (not tracked by git)
font-size = 16
theme = nord
```

`config.ghostty` always loads this file last, so values here win. If the file doesn't exist, Ghostty silently ignores the missing include.

> **Note:** Ghostty CLI may not be in `$PATH` when installed as a `.app` bundle.
> The binary is at `/Applications/Ghostty.app/Contents/MacOS/ghostty`.
> `doctor.sh` checks both locations.

---

## Claude Code & MCP

`~/.claude/settings.json` (managed by chezmoi) sets:
- Default deny for destructive shell commands (`curl`, `wget`, `rm`, `sudo`, `chmod`, `chown`)
- Default deny for credential paths (`.env`, `secrets/**`, `~/.ssh/**`)
- Ask-before-run for `git push` and `WebFetch`
- Auto-allow for read-only git commands and `--version`/`--help`

**Serena MCP** is registered at user scope, so it is active in every project:

```bash
bash scripts/post-setup.sh    # idempotent — safe to re-run
claude mcp list               # verify
```

**Superpowers plugin** (manual, inside a Claude Code session):
```
/plugin install superpowers
```

---

## Structure

```
dotfiles/
├── .chezmoiroot                    # "home" — chezmoi source root
├── .gitignore
├── home/                           # chezmoi source state → $HOME
│   ├── dot_Brewfile                # → ~/.Brewfile  (brew bundle --global)
│   ├── dot_zshrc                   # → ~/.zshrc     (entry point only)
│   ├── dot_claude/
│   │   └── settings.json           # → ~/.claude/settings.json
│   └── dot_config/
│       ├── ghostty/
│       │   ├── config.ghostty      # entry point (loads modules)
│       │   ├── core.ghostty        # shell integration, scrollback
│       │   ├── ui.ghostty          # fonts, Catppuccin Mocha
│       │   └── keybinds.ghostty    # key overrides
│       ├── zsh/
│       │   ├── env.zsh             # PATH, brew shellenv, exports
│       │   ├── aliases.zsh         # eza, bat, fd, rg shortcuts
│       │   ├── tools.zsh           # direnv / starship / fzf hooks
│       │   └── completion.zsh      # compinit (must load last)
│       └── starship.toml           # prompt config
├── scripts/
│   ├── bootstrap.sh                # brew + chezmoi + brew bundle + apply
│   ├── post-setup.sh               # Serena MCP registration (idempotent)
│   └── doctor.sh                   # health check
└── .github/workflows/
    └── ci.yml                      # shellcheck + brew bundle (macos-latest)
```
