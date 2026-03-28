# dotfiles

Personal macOS dotfiles managed with [chezmoi](https://chezmoi.io).

---

## Prerequisites

| | |
|---|---|
| **macOS** (Apple Silicon or Intel) | |
| **Homebrew** | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| **Git** | Xcode CLT (`xcode-select --install`) or `brew install git` |

Everything else is split into `home/dot_Brewfile.core`, `home/dot_Brewfile.work`, and `home/dot_Brewfile.personal`.
`bootstrap.sh` installs only the core profile.

---

## Initial Setup (new Mac)

```bash
# 1. Clone
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. Bootstrap: installs packages + applies dotfiles
bash scripts/bootstrap.sh

# 3. Optional: install extra app layers
bash scripts/brew-bundle.sh sync work
# or
bash scripts/brew-bundle.sh sync personal
# or
bash scripts/brew-bundle.sh sync all

# 4. Open a new terminal to load the zsh config, then run post-setup
bash scripts/post-setup.sh   # installs Codex CLI and registers Serena MCP

# 4.5 Authenticate Codex once
codex login

# 5. Verify
bash scripts/doctor.sh
```

### bootstrap.sh vs post-setup.sh

| Script | What it does | Re-runnable? |
|--------|-------------|--------------|
| `bootstrap.sh` | brew check → install chezmoi → sync `core` Brew profile → `chezmoi init --apply` | Yes (idempotent) |
| `brew-bundle.sh sync work` | Syncs `core + work` Brew profiles and cleans up against that combined set | Yes (idempotent) |
| `brew-bundle.sh sync personal` | Syncs `core + personal` Brew profiles and cleans up against that combined set | Yes (idempotent) |
| `brew-bundle.sh sync all` | Syncs `core + work + personal` Brew profiles and cleans up against the combined set | Yes (idempotent) |
| `post-setup.sh` | Installs Codex CLI and registers Serena MCP into Claude Code / Codex | Yes (idempotent) |

`bootstrap.sh` is intentionally minimal — it only ensures the machine has the right packages and dotfiles applied.
`brew-bundle.sh` is the supported way to keep Homebrew in strict sync after the split.
`post-setup.sh` handles "post-dotfiles" configuration that runs after the environment is in place.

---

## Day-to-day: Updating dotfiles

After `bootstrap.sh` has been run once, chezmoi knows its source directory
(`~/.local/share/chezmoi` → `~/dotfiles`). No `--source` flag is needed.

```bash
cd ~/dotfiles
git pull
chezmoi apply             # apply changes to $HOME
bash scripts/brew-bundle.sh sync core   # baseline machine
# or
bash scripts/brew-bundle.sh sync work   # baseline + work/dev apps
# or
bash scripts/brew-bundle.sh sync personal  # baseline + personal/local apps
# or
bash scripts/brew-bundle.sh sync all    # baseline + every optional layer
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
| `chezmoi doctor` | Required | Runs and prints built-in health results (`failed` rows are shown as warnings) |
| `bash scripts/brew-bundle.sh check core` | Required | All core Brew profile packages present |
| `node --version` | Optional | node/npm runtime available for Codex CLI installs |
| `uv --version` | Optional | uv installed (needed by Serena MCP) |
| `ghostty --version` | Optional | Ghostty CLI exists and returns a valid version |
| `claude --version` | Optional | Claude Code CLI available |
| `claude mcp list` (Serena) | Optional | Serena MCP registered |
| `codex --version` | Optional | Codex CLI available |
| `codex mcp list` (Serena) | Optional | Serena MCP registered for Codex |
| `ghq --version` | Optional | ghq installed |
| `zellij --version` | Optional | zellij installed |

Exit code is 0 only when all **required** checks pass.
Optional checks that are installed but unhealthy are reported as warnings instead of `OK`.

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

## Brew Profiles

`home/dot_Brewfile.core` is the minimal baseline used by `bootstrap.sh` and `doctor.sh`.
`home/dot_Brewfile.work` is an optional work/dev layer.
`home/dot_Brewfile.personal` is an optional personal/local layer.

Homebrew is still run in strict mode, but cleanup must happen against the effective combined profile.
Because of that, use `bash scripts/brew-bundle.sh ...` instead of raw `brew bundle --global` commands.

| Context | Command |
|---------|---------|
| Initial install (core only) | `bash ~/dotfiles/scripts/brew-bundle.sh sync core` |
| Add work apps too | `bash ~/dotfiles/scripts/brew-bundle.sh sync work` |
| Add personal apps too | `bash ~/dotfiles/scripts/brew-bundle.sh sync personal` |
| Add every optional layer | `bash ~/dotfiles/scripts/brew-bundle.sh sync all` |
| Verify core | `bash ~/dotfiles/scripts/brew-bundle.sh check core` |
| Verify core + work | `bash ~/dotfiles/scripts/brew-bundle.sh check work` |
| Verify core + personal | `bash ~/dotfiles/scripts/brew-bundle.sh check personal` |
| Verify core + work + personal | `bash ~/dotfiles/scripts/brew-bundle.sh check all` |

Use the same profile consistently on later runs. For example, running `sync core` after `sync work` will clean up work-only apps.

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

## Claude Code / Codex / MCP

`~/.claude/settings.json` (managed by chezmoi) sets:
- Default deny for destructive shell commands (`curl`, `wget`, `rm`, `sudo`, `chmod`, `chown`)
- Default deny for credential paths (`.env`, `secrets/**`, `~/.ssh/**`)
- Ask-before-run for `git push` and `WebFetch`
- Auto-allow for read-only git commands and `--version`/`--help`

`~/.codex/config.toml` (managed by chezmoi) sets:
- Default model / reasoning / personality
- OpenAI curated `github` and `google-calendar` plugins enabled
- `serena` as a shared Codex MCP server
- Existing local `projects.*` trust overrides are preserved on `chezmoi apply`

**Codex CLI** is installed by `post-setup.sh` using the official npm package. `node` is included in the core Brew profile so new machines have the runtime needed for that install path.

**Serena MCP** is configured for both tools, so it is active in every project. The launch args also disable Serena's browser auto-open behavior:

```bash
bash scripts/post-setup.sh    # idempotent — safe to re-run
codex login                   # one-time auth
claude mcp list               # verify for Claude Code
codex mcp list                # verify for Codex
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
│   ├── dot_Brewfile.core           # → ~/.Brewfile.core
│   ├── dot_Brewfile.work           # → ~/.Brewfile.work
│   ├── dot_Brewfile.personal       # → ~/.Brewfile.personal
│   ├── dot_zshrc                   # → ~/.zshrc     (entry point only)
│   ├── dot_claude/
│   │   └── settings.json           # → ~/.claude/settings.json
│   ├── dot_codex/
│   │   └── config.toml.tmpl        # → ~/.codex/config.toml
│   └── dot_config/
│       ├── ghostty/
│       │   ├── config.ghostty      # entry point (loads modules)
│       │   ├── core.ghostty        # shell integration, scrollback
│       │   ├── ui.ghostty          # fonts, Catppuccin Mocha
│       │   └── keybinds.ghostty    # key overrides
│       ├── zsh/
│       │   ├── env.zsh             # PATH, brew shellenv, exports
│       │   ├── aliases.zsh         # eza, bat, fd, rg shortcuts
│       │   ├── tools.zsh           # starship / zoxide / atuin / fzf hooks
│       │   └── completion.zsh      # compinit (must load last)
│       └── starship.toml           # prompt config
├── scripts/
│   ├── brew-bundle.sh              # effective Brew profile sync/check
│   ├── bootstrap.sh                # core brew + chezmoi + apply
│   ├── post-setup.sh               # Serena MCP registration (idempotent)
│   └── doctor.sh                   # health check
└── .github/workflows/
    └── ci.yml                      # shellcheck + core brew bundle (macos-latest)
```
