# dotfiles

[chezmoi](https://chezmoi.io) で管理している、macOS 向けの個人用 dotfiles です。

---

## 前提条件

| 項目 | 内容 |
|---|---|
| macOS | Apple Silicon / Intel のどちらでも可 |
| Homebrew | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Git | Xcode CLT (`xcode-select --install`) または `brew install git` |

Homebrew の構成は `home/dot_Brewfile.core`、`home/dot_Brewfile.work`、`home/dot_Brewfile.personal` に分かれています。  
`bootstrap.sh` が入れるのは `core` プロファイルだけです。

---

## 初期セットアップ

新しい Mac での基本手順です。

```bash
# 1. clone
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. 用途に応じてセットアップ
make install            # core のみ
make install-work       # core + work
make install-personal   # core + personal
make install-all        # すべて

# 3. 新しいターミナルを開いて zsh を読み直す

# 4. Codex の初回認証
codex login

# 5. 状態確認
make doctor
```

### make ターゲット一覧

```bash
make help
```

| ターゲット | 内容 | 再実行 |
|---|---|---|
| `make install` | core Brew + `chezmoi apply` | ✓ |
| `make install-work` | core + work + `post-setup` | ✓ |
| `make install-personal` | core + personal + `post-setup` | ✓ |
| `make install-all` | core + work + personal + `post-setup` | ✓ |
| `make update` | pull → `chezmoi apply` → brew sync core | ✓ |
| `make update-work` | pull → `chezmoi apply` → brew sync work | ✓ |
| `make update-personal` | pull → `chezmoi apply` → brew sync personal | ✓ |
| `make update-all` | pull → `chezmoi apply` → brew sync all | ✓ |
| `make doctor` | 設定と依存の健全性確認 | ✓ |
| `make uninstall` | dotfiles を削除 | ✓ |

---

## 日常の更新

```bash
cd ~/dotfiles
make update
make update-work
make update-personal
make update-all
```

---

## ヘルスチェック

```bash
make doctor
```

`doctor.sh` は次の項目を確認します。

| チェック | 種別 | 合格条件 |
|---|---|---|
| `brew --version` | Required | Homebrew が使える |
| `chezmoi --version` | Required | chezmoi が使える |
| `chezmoi doctor` | Required | 内蔵チェックが実行できる (`failed` 行は warning 扱い) |
| `./scripts/brew-bundle.sh check core` | Required | core Brew プロファイルが満たされている |
| `node --version` | Optional | Codex CLI 導入に必要な node/npm がある |
| `uv --version` | Optional | Serena MCP に必要な `uv` がある |
| `ghostty --version` | Optional | Ghostty CLI が存在し、バージョンが取得できる |
| `claude --version` | Optional | Claude Code CLI がある |
| `claude mcp list` | Optional | Claude Code 側で Serena MCP が見える |
| `codex --version` | Optional | Codex CLI がある |
| `codex mcp list` | Optional | Codex 側で Serena MCP が見える |
| `ghq --version` | Optional | `ghq` がある |
| `zellij --version` | Optional | `zellij` がある |
| `navi --version` | Optional | `navi` と cheatsheet がある |

終了コードが `0` になるのは Required がすべて通ったときだけです。  
Optional は失敗しても warning 扱いです。

### ghq の使い方

```bash
# 管理対象リポジトリへ移動
qcd

# ghq 経由で clone
ghq get git@github.com:owner/repo.git
```

---

## AI セッション

`zellij` 上で AI セッションを開くための最小構成です。

```bash
bash ~/.local/share/chezmoi/scripts/ai-session.sh
```

起動直後のイメージ:

```text
┌──────────────────────────────────────────────────────────────┐
│ zellij (single pane)                                        │
│                                                              │
│ ここから必要に応じて使い方を決める                            │
└──────────────────────────────────────────────────────────────┘
```

- レイアウトは固定しない
- キーバインドも追加で押し付けない
- まずは素の `zellij` セッションとして開く

---

## chezmoi の基本運用

基本は「`~/dotfiles` を編集して `chezmoi apply`」です。

```bash
# 1. repo 側を編集
cd ~/dotfiles
$EDITOR home/dot_config/zsh/aliases.zsh

# 2. HOME へ反映
chezmoi apply

# 3. 反映前に差分確認
chezmoi diff
chezmoi apply -n -v

# 4. HOME 側で直接編集した内容を取り込む
chezmoi add ~/.zshrc
```

---

## 巻き戻し

```bash
# 特定ファイルだけ戻す
git checkout <commit> -- home/dot_config/zsh/tools.zsh
chezmoi apply

# 直前のコミットを打ち消す
git revert HEAD
chezmoi apply
```

新しいマシンで完全に戻したい場合は、巻き戻した状態を clone し直して `bootstrap.sh` を再実行します。

---

## Brew プロファイル

| Brewfile | 用途 |
|---|---|
| `dot_Brewfile.core` | 全マシン共通のベース |
| `dot_Brewfile.work` | 仕事用・開発用の追加レイヤー |
| `dot_Brewfile.personal` | 個人用の追加レイヤー |

`cleanup` はプロファイル全体に対して実行されるため、`make` 経由で使う前提です。  
同じプロファイルを一貫して使ってください。たとえば `sync work` の後に `sync core` を実行すると、work 側の追加アプリが削除されます。

---

## Ghostty 設定

Ghostty の設定は `~/.config/ghostty/` 配下で分割管理しています。

| ファイル | 用途 |
|---|---|
| `config.ghostty` | エントリポイント |
| `core.ghostty` | shell integration、scrollback、終了挙動 |
| `ui.ghostty` | フォント、テーマ、padding |
| `keybinds.ghostty` | 追加キーバインド |
| `local.ghostty` | 任意のマシンローカル設定用。git 管理しない |

### GUI で設定を変えた場合

Ghostty の GUI から設定を変更すると、通常は `~/.config/ghostty/*.ghostty` が直接書き換わります。  
この変更は `chezmoi diff` で検出できます。

```bash
chezmoi diff
chezmoi diff ~/.config/ghostty/config.ghostty
```

運用は次の方針です。

- GUI での変更は一時的なローカル差分として扱う
- 残したい変更だけ dotfiles 側へ取り込む
- `chezmoi apply` をすると共通設定で上書きされることがある

### `local.ghostty` について

マシンごとの上書き設定を使いたい場合は、必要なマシンだけ `~/.config/ghostty/local.ghostty` を作成します。

```conf
# ~/.config/ghostty/local.ghostty
font-size = 16
theme = nord
```

Ghostty は存在しない `config-file` を無視せずエラーにするため、`local.ghostty` は共通設定からは自動で読み込みません。  
本当に使いたいマシンだけ、そのマシンの `~/.config/ghostty/config.ghostty` に次を手で追加してください。

```conf
config-file = local.ghostty
```

> 注意: この手修正は共通の chezmoi 管理対象ではないため、あとで `chezmoi apply` すると元に戻る可能性があります。恒久化したい場合は dotfiles 側へ取り込むこと。

> 補足: Ghostty CLI が `$PATH` に無い場合でも、`/Applications/Ghostty.app/Contents/MacOS/ghostty` から実行できます。`doctor.sh` は両方を確認します。

---

## Claude Code / Codex / MCP

`~/.claude/settings.json` は chezmoi 管理で、主に次を設定しています。

- 破壊的なシェルコマンド (`curl`, `wget`, `rm`, `sudo`, `chmod`, `chown`) は既定 deny
- 認証情報に近いパス (`.env`, `secrets/**`, `~/.ssh/**`) は既定 deny
- `git push` と `WebFetch` は確認つき
- 読み取り専用の git コマンドや `--version` / `--help` は自動許可

`~/.claude/CLAUDE.md` も chezmoi 管理にしており、個人用の共通メモと運用方針を置きます。

`~/.codex/config.toml` も chezmoi 管理で、主に次を設定しています。

- 既定モデル / reasoning / personality
- OpenAI curated の `github` と `google-calendar` プラグインを有効化
- `serena` を共有 MCP サーバーとして有効化
- `playwright`、`screenshot` などのローカル skill を利用可能にする
- 既存の `projects.*` trust override は `chezmoi apply` で壊さない

**Codex CLI** は `post-setup.sh` が公式 npm パッケージ経由で導入します。  
`node` は core Brew プロファイルに含めているので、新規マシンでもこの導線がそのまま使えます。

**Serena MCP** は Claude Code / Codex の両方で使う前提です。起動引数にはブラウザ自動起動の抑止も入れています。

**brew-autoupdate** は `post-setup.sh` が `domt4/autoupdate` tap 経由で導入し、24 時間ごとに `upgrade + cleanup` するよう起動します。

```bash
./scripts/post-setup.sh
codex login
claude mcp list
codex mcp list
```

セットアップ系のスクリプトは Bash 前提で書いているので、呼び出しは `bash` 明示です。日常利用は普段どおり `zsh` のままで問題ありません。

同梱している skill は `~/.codex/skills` に入り、`chezmoi apply` で反映されます。現在は `playwright`、`screenshot`、`doc`、`pdf`、`spreadsheet`、`jupyter-notebook`、`security-best-practices` を同梱しています。たとえば:

```zsh
~/.codex/skills/playwright/scripts/playwright_cli.sh open https://example.com
~/.codex/skills/playwright/scripts/playwright_cli.sh snapshot
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --mode temp --active-window
```

**Superpowers plugin** は Claude Code セッション内で手動インストールです。

```text
/plugin install superpowers
```

### Claude Code / Gemini CLI のローカル state

Claude Code と Gemini CLI は、共通設定とローカル state を分けて管理します。

- Claude Code は `~/.claude/settings.json` だけを dotfiles 管理する
- `~/.claude/CLAUDE.md` は共通メモとして dotfiles 管理する
- `~/.claude/history.jsonl`、`projects/`、`sessions/`、`cache/`、`plugins/` などの運用データは管理しない
- Gemini CLI は `~/.gemini/settings.json` だけを dotfiles 管理する
- `~/.gemini/oauth_creds.json`、`google_accounts.json`、`history/`、`projects.json`、`state.json`、`trustedFolders.json`、`tmp/` などは管理しない

Gemini の `settings.json` は chezmoi テンプレートで管理し、既存の認証方式 (`selectedAuthType`) だけはローカル値を温存します。これにより、UI 設定は揃えつつ認証状態は壊しません。

---

## ディレクトリ構成

```text
dotfiles/
├── Makefile                        # install / update / doctor / uninstall
├── .chezmoiroot                    # "home" を chezmoi source root として使う
├── .gitignore
├── home/                           # chezmoi source state -> $HOME
│   ├── dot_Brewfile.core           # -> ~/.Brewfile.core
│   ├── dot_Brewfile.work           # -> ~/.Brewfile.work
│   ├── dot_Brewfile.personal       # -> ~/.Brewfile.personal
│   ├── dot_zshrc                   # -> ~/.zshrc
│   ├── dot_claude/
│   │   ├── CLAUDE.md               # -> ~/.claude/CLAUDE.md
│   │   └── settings.json           # -> ~/.claude/settings.json
│   ├── dot_codex/
│   │   ├── config.toml.tmpl        # -> ~/.codex/config.toml
│   │   └── skills/                 # -> ~/.codex/skills/*
│   ├── dot_gemini/
│   │   └── settings.json.tmpl      # -> ~/.gemini/settings.json
│   ├── dot_local/share/navi/cheats/dotfiles/
│   │   ├── git.cheat
│   │   ├── shell.cheat
│   │   ├── files.cheat
│   │   └── terminal.cheat
│   └── dot_config/
│       ├── ghostty/
│       │   ├── config.ghostty      # エントリポイント
│       │   ├── core.ghostty        # shell integration / scrollback
│       │   ├── ui.ghostty          # font / theme / padding
│       │   └── keybinds.ghostty    # 追加キーバインド
│       ├── zsh/
│       │   ├── env.zsh             # PATH / export / brew shellenv
│       │   ├── aliases.zsh         # alias 群
│       │   ├── tools.zsh           # starship / zoxide / atuin / fzf / navi
│       │   └── completion.zsh      # compinit
│       └── starship.toml           # prompt 設定
├── scripts/
│   ├── brew-bundle.sh              # Brew profile の sync / install / check
│   ├── bootstrap.sh                # core brew + chezmoi + apply
│   ├── post-setup.sh               # Serena MCP + brew-autoupdate
│   ├── uninstall.sh                # dotfiles を削除
│   └── doctor.sh                   # 健全性チェック
└── .github/workflows/
    └── ci.yml                      # shellcheck + core brew bundle
```
