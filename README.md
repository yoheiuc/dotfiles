# dotfiles

[chezmoi](https://chezmoi.io) で管理している、macOS 向けの個人用 dotfiles です。

現在の運用メモは [docs/notes/current-state.md](/Users/y.uchiyama/dotfiles/docs/notes/current-state.md) に置いています。

---

## 前提条件

| 項目 | 内容 |
|---|---|
| macOS | Apple Silicon / Intel のどちらでも可 |
| Homebrew | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Git | Xcode CLT (`xcode-select --install`) または `brew install git` |

Git identity (`~/.gitconfig`) も chezmoi 管理です。既定では `yoheiuc <16657439+yoheiuc@users.noreply.github.com>` を使い、global `pre-commit` hook でそれ以外の author/committer を止めます。

Homebrew の構成は `home/dot_Brewfile.core` と `home/dot_Brewfile.home` に分かれています。  
`bootstrap.sh` が入れるのは `core` プロファイルだけです。

境界は「仕事でも使うか / プライベートか」だけではなく、`その仕事用ツールを自分で配る必要があるか` です。

- `core`: 自分で手動インストールして全マシンに揃えたい共通基盤。仕事で使うツールでも、会社 PC に自動配布されないならここに入れます。
- `home`: 私用のもの、自宅マシン固有のもの、または仕事でも使うが会社 PC には自動配布されるものを入れます。

アクティブなマシンプロファイルは `~/.config/dotfiles/profile` に保存します。  
`make install-home`、`make update-home` などの明示的なターゲットを実行すると、この値も切り替わります。
`make install` は profile 未設定の初回だけ `core` を保存し、既存の `home` は上書きしません。
旧 `personal` profile は自動で `home` に、旧 `work` profile は自動で `core` に移行します。旧 `all` profile は非対応です。

---

## 初期セットアップ

新しい Mac での基本手順です。

```bash
# 1. clone
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. 用途に応じてセットアップ
make install            # core のみ
make install-home       # core + home

# 3. 新しいターミナルを開いて zsh を読み直す

# 4. Codex の初回認証
codex login

# 5. 状態確認
make doctor

# 6. 変更前の確認
make preview
```

### make ターゲット一覧

```bash
make help
```

| ターゲット | 内容 | 再実行 |
|---|---|---|
| `make install` | core Brew + `chezmoi apply` | ✓ |
| `make install-home` | core + home + `post-setup` | ✓ |
| `make preview` | `chezmoi diff` + dry-run + brew preview (現在のプロファイル) | ✓ |
| `make preview-home` | `chezmoi diff` + dry-run + brew preview (home) | ✓ |
| `make update` | pull → `chezmoi apply` → brew install 現在のプロファイル | ✓ |
| `make update-home` | pull → `chezmoi apply` → brew install home | ✓ |
| `make doctor` | 現在のプロファイルで設定と依存の健全性確認 | ✓ |
| `make test` | shell ベースの回帰テスト | ✓ |
| `make uninstall` | dotfiles を削除 | ✓ |

---

## 日常の更新

```bash
cd ~/dotfiles
make preview
make update
make update-home
```

ふだんは `make preview` / `make update` で、現在のプロファイルに追従します。  
別プロファイルを一時的に見たいときだけ `make preview-home` を使います。

まだ `~/.config/dotfiles/profile` が無い既存マシンでは、`make preview` / `make update` / `make doctor` は一時的に `core` を既定として使います。  
その場合は一度だけ、意図する役割に合わせて `make install-home` または `make update-home` を実行してプロファイルを保存してください。

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
| `./scripts/brew-bundle.sh check <active-profile>` | Required | 現在の Brew プロファイルが満たされている |
| `git user.name` / `user.email` / `core.hooksPath` | Required | privacy-safe な Git identity/hook が有効 |
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

`doctor.sh` は、保存済み profile と実際に入っている Brew package も照合します。  
たとえば `core` なのに `home` 専用の formula や cask が入っている場合は warning を出します。

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
- 通常の pane / tab 操作は upstream の流儀を維持する
- まずはほぼ素の `zellij` セッションとして開く

`~/.config/zellij/config.kdl` は discoverability を少しだけ強めています。

- `F1`: `about` を開いてキーバインドやヘルプを確認
- `F2`: `session-manager` を開いてセッション一覧/復帰/切替
- `F3`: `configuration` を開いて UI とキーバインド設定を確認
- マウス hover で pane frame の補助表示を出し、pane 境界の drag で resize
- `Ctrl` を押しながら floating pane の境界を drag、またはホイールで resize

`compact` レイアウトを使う場合でも、下部 `compact-bar` のヒントは `F1` で表示できます。

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

現在のマシンプロファイルは次で確認できます。

```bash
dotprofile
cat ~/.config/dotfiles/profile
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

## Git の privacy guard

`~/.gitconfig` は次を固定します。

- `user.name = yoheiuc`
- `user.email = 16657439+yoheiuc@users.noreply.github.com`
- `core.hooksPath = ~/.config/git/hooks`

`~/.config/git/hooks/pre-commit` は、実際に commit に入る author / committer がこの値と一致しない場合に commit を止めます。`GIT_AUTHOR_*` や repo local config で上書きしても検査対象です。

---

## Brew プロファイル

| Brewfile | 用途 |
|---|---|
| `dot_Brewfile.core` | 自分で配る共通基盤。仕事で使い、会社 PC に自動配布されないものも含む |
| `dot_Brewfile.home` | 私用 / 自宅用レイヤー。仕事でも会社 PC に自動配布されるものはここに置く |

`cleanup` はプロファイル全体に対して実行されるため、`make` 経由で使う前提です。  
`make install-*` / `make update-*` は `~/.config/dotfiles/profile` を更新し、その値を日常運用の既定にします。  
たとえば `make install-home` の後は `make preview` / `make update` / `make doctor` が home を前提に動きます。

保存済み profile と Homebrew の実体がズレているか見たいときは、まず次を見ます。

```bash
make doctor
./scripts/brew-bundle.sh preview "$(dotprofile)"
```

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
- `fast` / `review` / `deep` の profile
- OpenAI curated の `github` と `google-calendar` プラグインを有効化
- `serena` を共有 MCP サーバーとして有効化
- `playwright`、`screenshot` などのローカル skill を利用可能にする
- 既存の `projects.*` trust override は `chezmoi apply` で壊さない

`~/AGENTS.md` も chezmoi 管理にしており、Codex が参照する個人用の共通メモとして使います。

日常運用向けに、Codex では profile と shell alias をあらかじめ用意しています。

- `cx` = `codex`
- `cxf` = `codex -p fast`
- `cxr` = `codex -p review`
- `cxd` = `codex -p deep`
- `cxl` = `codex resume --last`
- `dotprofile` = 現在の dotfiles プロファイルを表示

Gemini は補助用途の one-shot コマンドを用意しています。

- `gr "<prompt>"` = `gemini -p "<prompt>"`
- `gmr [追加指示]` = 現在の git diff を Gemini にレビューさせる
- `gms [追加指示]` = 現在の git diff を Gemini に要約させる

`fast` は軽い確認や小修正向け、`review` は読解やレビュー向け、`deep` は長めの実装や整理向けです。

**Codex CLI** は `post-setup.sh` が公式 npm パッケージ経由で導入します。  
`node` は core Brew プロファイルに含めているので、新規マシンでもこの導線がそのまま使えます。

**Serena MCP** は Claude Code / Codex の両方で使う前提です。`~/.local/bin/serena-mcp` wrapper 経由で起動し、Homebrew の `uvx` とブラウザ自動起動抑止を明示しています。

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
- Codex は `~/.codex/config.toml` と `~/AGENTS.md` を dotfiles 管理する
- Codex の zsh alias / completion も dotfiles 管理する
- `~/.codex/auth.json`、`sessions/`、`history.jsonl`、`cache/`、`log/`、`sqlite` 系、`tmp/` などの運用データは管理しない
- Gemini CLI は `~/.gemini/settings.json` だけを dotfiles 管理する
- `~/.gemini/oauth_creds.json`、`google_accounts.json`、`history/`、`projects.json`、`state.json`、`trustedFolders.json`、`tmp/` などは管理しない

Gemini の `settings.json` は chezmoi テンプレートで管理し、既存の認証方式 (`selectedAuthType`) だけはローカル値を温存します。これにより、UI 設定は揃えつつ認証状態は壊しません。

---

## ディレクトリ構成

```text
dotfiles/
├── AGENTS.md                        # -> ~/AGENTS.md
├── Makefile                        # install / update / doctor / uninstall
├── .chezmoiroot                    # "home" を chezmoi source root として使う
├── .gitignore
├── home/                           # chezmoi source state -> $HOME
│   ├── dot_Brewfile.core           # -> ~/.Brewfile.core
│   ├── dot_Brewfile.home           # -> ~/.Brewfile.home
│   ├── dot_gitconfig               # -> ~/.gitconfig
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
│       ├── git/hooks/pre-commit    # global Git privacy guard
│       ├── ghostty/
│       │   ├── config.ghostty      # エントリポイント
│       │   ├── core.ghostty        # shell integration / scrollback
│       │   ├── ui.ghostty          # font / theme / padding
│       │   └── keybinds.ghostty    # 追加キーバインド
│       ├── dotfiles/profile        # ローカルの active profile (runtime state)
│       ├── zsh/
│       │   ├── env.zsh             # PATH / export / brew shellenv
│       │   ├── aliases.zsh         # alias 群
│       │   ├── tools.zsh           # starship / zoxide / atuin / fzf / navi
│       │   └── completion.zsh      # compinit
│       └── starship.toml           # prompt 設定
├── scripts/
│   ├── brew-bundle.sh              # Brew profile の sync / install / check
│   ├── bootstrap.sh                # core brew + chezmoi + apply
│   ├── profile.sh                  # active profile の保存 / 参照
│   ├── preview.sh                  # chezmoi/Brew の変更予定を確認
│   ├── post-setup.sh               # Serena MCP + brew-autoupdate
│   ├── uninstall.sh                # dotfiles を削除
│   └── doctor.sh                   # 健全性チェック
└── .github/workflows/
    └── ci.yml                      # shellcheck + core brew bundle
```
