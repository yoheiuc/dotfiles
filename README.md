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
| `bootstrap.sh` | brew check → install chezmoi → `brew bundle` + `brew bundle cleanup --force` → `chezmoi init --apply` | Yes (idempotent) |
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
brew bundle --global      # install/update to match ~/.Brewfile
brew bundle cleanup --global --force  # remove packages not in ~/.Brewfile
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
| `ghq --version` | Optional | ghq installed |
| `zellij --version` | Optional | zellij installed |

Exit code is 0 only when all **required** checks pass.

### ghq (repository management)

```bash
# Find and jump to a managed repository
qcd

# Clone through ghq (stored under $(ghq root))
ghq get git@github.com:owner/repo.git
```


---


## AI Session (zellij) — 使い方イメージ

```bash
# AI セッション起動（レイアウトは固定しない）
bash ~/.local/share/chezmoi/scripts/ai-session.sh
```

起動直後（プレーン）イメージ:

```text
┌──────────────────────────────────────────────────────────────┐
│ zellij (single pane)                                        │
│                                                              │
│ ここから必要に応じて使い方を決める                            │
└──────────────────────────────────────────────────────────────┘
```

- レイアウトやキーバインドを固定しない、プレーンな起動のみ

---

## chezmoi の基本的な使い方

```bash
# 1) dotfiles リポジトリ側を編集
cd ~/dotfiles
$EDITOR home/dot_config/zsh/aliases.zsh

# 2) 変更を自分の HOME に反映
chezmoi apply

# 3) 反映前に差分だけ見たいとき
chezmoi diff
chezmoi apply -n -v

# 4) すでに HOME 側で編集したファイルを管理下に取り込むとき
chezmoi add ~/.zshrc
```

よく使う流れは「`~/dotfiles` を編集 → `chezmoi apply` で反映」です。

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

Homebrew is run in strict mode in this repo: after install/update, `brew bundle cleanup --force` is also run to remove packages not in the Brewfile.

| Context | Command |
|---------|---------|
| Initial install (before `chezmoi apply`) | `brew bundle --file=~/dotfiles/home/dot_Brewfile` |
| After first apply | `brew bundle --global` + `brew bundle cleanup --global --force` |
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
│   ├── dot_Brewfile                # → ~/.Brewfile  (bundle + cleanup)
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
