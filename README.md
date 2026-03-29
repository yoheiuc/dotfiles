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

# 2. セットアップ（用途に合わせて1つ選ぶ）
make install            # core のみ
make install-work       # core + work アプリ
make install-personal   # core + personal アプリ
make install-all        # すべて

# 3. 新しいターミナルを開いて zsh 設定を読み込む

# 4. Codex の認証（初回のみ）
codex login

# 5. 状態確認
make doctor
```

### make ターゲット一覧

```
make help
```

| ターゲット | 何をするか | 再実行 |
|---|---|---|
| `make install` | core Brew + chezmoi apply | ✓ |
| `make install-work` | core + work + post-setup | ✓ |
| `make install-personal` | core + personal + post-setup | ✓ |
| `make install-all` | core + work + personal + post-setup | ✓ |
| `make update` | pull → chezmoi apply → brew sync core | ✓ |
| `make update-work` | pull → chezmoi apply → brew sync work | ✓ |
| `make update-personal` | pull → chezmoi apply → brew sync personal | ✓ |
| `make update-all` | pull → chezmoi apply → brew sync all | ✓ |
| `make doctor` | セットアップの状態確認 | ✓ |
| `make uninstall` | dotfiles を削除 | ✓ |

---

## Day-to-day: Updating dotfiles

```bash
cd ~/dotfiles
make update             # core のみ
make update-work        # core + work
make update-personal    # core + personal
make update-all         # すべて
```

---

## Health Check

```bash
make doctor
```

| Check | Type | Pass condition |
|-------|------|----------------|
| `brew --version` | Required | Homebrew is installed |
| `chezmoi --version` | Required | chezmoi is installed |
| `chezmoi doctor` | Required | Runs and prints built-in health results (`failed` rows are shown as warnings) |
| `./scripts/brew-bundle.sh check core` | Required | All core Brew profile packages present |
| `node --version` | Optional | node/npm runtime available for Codex CLI installs |
| `uv --version` | Optional | uv installed (needed by Serena MCP) |
| `ghostty --version` | Optional | Ghostty CLI exists and returns a valid version |
| `claude --version` | Optional | Claude Code CLI available |
| `claude mcp list` (Serena) | Optional | Serena MCP registered |
| `codex --version` | Optional | Codex CLI available |
| `codex mcp list` (Serena) | Optional | Serena MCP registered for Codex |
| `ghq --version` | Optional | ghq installed |
| `zellij --version` | Optional | zellij installed |
| `navi --version` | Optional | navi installed + cheatsheets present |

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

| Brewfile | 用途 |
|---|---|
| `dot_Brewfile.core` | 全マシン共通のベースライン |
| `dot_Brewfile.work` | work/dev 追加レイヤー |
| `dot_Brewfile.personal` | personal 追加レイヤー |

cleanup はプロファイル全体に対して行われるため、`make` コマンド経由で実行すること。同じプロファイルを一貫して使うこと（例: `sync work` の後に `sync core` を実行すると work アプリが削除される）。

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
- Curated local skills such as `playwright` and `screenshot`
- Existing local `projects.*` trust overrides are preserved on `chezmoi apply`

**Codex CLI** is installed by `post-setup.sh` using the official npm package. `node` is included in the core Brew profile so new machines have the runtime needed for that install path.

**Serena MCP** is configured for both tools, so it is active in every project. The launch args also disable Serena's browser auto-open behavior.

**brew-autoupdate** は `post-setup.sh` が `domt4/autoupdate` tap 経由でインストール・起動する（24時間ごとに自動 upgrade + cleanup）。

```bash
./scripts/post-setup.sh       # idempotent — safe to re-run
codex login                   # one-time auth
claude mcp list               # verify for Claude Code
codex mcp list                # verify for Codex
```

Setup scripts are invoked with `bash` explicitly because the repository scripts are written for Bash. Day-to-day usage can stay in your normal `zsh` shell.

Bundled Codex skills are available under `~/.codex/skills`. For example, from `zsh`:

```zsh
~/.codex/skills/playwright/scripts/playwright_cli.sh open https://example.com
~/.codex/skills/playwright/scripts/playwright_cli.sh snapshot
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --mode temp --active-window
```

**Superpowers plugin** (manual, inside a Claude Code session):
```
/plugin install superpowers
```

---

## Structure

```
dotfiles/
├── Makefile                        # install / update / doctor / uninstall
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
│   │   ├── config.toml.tmpl        # → ~/.codex/config.toml
│   │   └── skills/                 # → ~/.codex/skills/*
│   ├── dot_local/share/navi/cheats/dotfiles/
│   │   ├── git.cheat               # lazygit, ghq, git-delta, gh
│   │   ├── shell.cheat             # atuin, zoxide, fzf, navi
│   │   ├── files.cheat             # eza, bat, yazi, ripgrep, fd
│   │   └── terminal.cheat          # zellij, jq, yq
│   └── dot_config/
│       ├── ghostty/
│       │   ├── config.ghostty      # entry point (loads modules)
│       │   ├── core.ghostty        # shell integration, scrollback
│       │   ├── ui.ghostty          # fonts, Catppuccin Mocha
│       │   └── keybinds.ghostty    # key overrides
│       ├── zsh/
│       │   ├── env.zsh             # PATH, brew shellenv, exports
│       │   ├── aliases.zsh         # eza, bat, fd, rg shortcuts
│       │   ├── tools.zsh           # starship / zoxide / atuin / fzf / navi hooks
│       │   └── completion.zsh      # compinit (must load last)
│       └── starship.toml           # prompt config
├── scripts/
│   ├── brew-bundle.sh              # effective Brew profile sync/check
│   ├── bootstrap.sh                # core brew + chezmoi + apply
│   ├── post-setup.sh               # Serena MCP + brew-autoupdate (idempotent)
│   ├── uninstall.sh                # dotfiles を削除
│   └── doctor.sh                   # health check
└── .github/workflows/
    └── ci.yml                      # shellcheck + core brew bundle (macos-latest)
```
