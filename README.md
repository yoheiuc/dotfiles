# dotfiles

[chezmoi](https://chezmoi.io) で管理している、macOS 向けの個人用 dotfiles です。

現在の運用メモは [docs/notes/current-state.md](docs/notes/current-state.md) に置いています。

---

## 前提条件

| 項目 | 内容 |
|---|---|
| macOS | Apple Silicon / Intel のどちらでも可 |
| Homebrew | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Git | Xcode CLT (`xcode-select --install`) または `brew install git` |

Git identity (`~/.gitconfig`) も chezmoi 管理です。既存の global git config を引き継ぎ、global `pre-commit` hook で author / committer がその値とずれていないかを確認します。public に clone した人向けには、[docs/examples/chezmoidata.yaml](docs/examples/chezmoidata.yaml) を `.chezmoidata.yaml` にコピーして `gitIdentity.name` / `gitIdentity.email` を上書きする方法も用意しています。

初回に git identity が未設定なら、先に次のどちらかを行ってください。

```bash
git config --global user.name "Your Name"
git config --global user.email "your-github-id@users.noreply.github.com"
```

または:

```bash
cp docs/examples/chezmoidata.yaml .chezmoidata.yaml
$EDITOR .chezmoidata.yaml
```

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
| `make status` | 日常確認に必要な状態を短く表示 | ✓ |
| `make ai-audit` | ローカル管理の AI 設定だけを詳しく確認 | ✓ |
| `make ai-repair` | AI 周りの local drift を修復 (`Serena config` / MCP registration) | ✓ |
| `make ai-secrets` | Claude Code / Codex 共通の MCP credential を Keychain に保存 | ✓ |
| `make install` | core Brew + `chezmoi apply` | ✓ |
| `make install-home` | core + home + `post-setup` | ✓ |
| `make preview` | `chezmoi diff` + dry-run + brew preview (現在のプロファイル) | ✓ |
| `make preview-home` | `chezmoi diff` + dry-run + brew preview (home) | ✓ |
| `make update` | pull → `chezmoi apply` → brew install 現在のプロファイル | ✓ |
| `make update-home` | pull → `chezmoi apply` → brew install home | ✓ |
| `make sync` | `chezmoi apply` → brew sync 現在のプロファイル (cleanup あり) | ✓ |
| `make sync-core` | `chezmoi apply` → brew sync core (cleanup あり) | ✓ |
| `make sync-home` | `chezmoi apply` → brew sync home (cleanup あり) | ✓ |
| `make brew-diff` | 現在のプロファイルとローカル Brew 実体の差分確認 | ✓ |
| `make brew-diff-core` | core とローカル Brew 実体の差分確認 | ✓ |
| `make brew-diff-home` | home とローカル Brew 実体の差分確認 | ✓ |
| `make brew-add-core KIND=... NAME=...` | core Brewfile に 1 件追加 | ✓ |
| `make brew-add-home KIND=... NAME=...` | home Brewfile に 1 件追加 | ✓ |
| `make tips` | よく使う dotfiles コマンドのヒント表示 | ✓ |
| `make doctor` | 現在のプロファイルで設定と依存の健全性確認 | ✓ |
| `make test` | shell ベースの回帰テスト | ✓ |
| `make uninstall` | dotfiles を削除 | ✓ |

---

## 日常の更新

```bash
cd ~/dotfiles
make status
make ai-audit
make ai-repair
make preview
make update
make update-home
make sync
make sync-core
make sync-home
make brew-diff
make tips
```

ふだんは `make status` でざっと状態を見て、AI 設定を触ったあとは `make ai-audit`、Serena や MCP 登録が怪しいときは `make ai-repair` を使いながら、`make preview` / `make update` で現在のプロファイルに追従します。  
別プロファイルを一時的に見たいときだけ `make preview-home` を使います。
cleanup まで含めて Homebrew 実体を定義どおりに寄せたいときは `make sync` / `make sync-home` を使います。
会社 PC で明示的に `core` へ寄せたいときは `make sync-core` を使います。
Claude Code / Codex 共通の MCP credential（Brave API key など）を安全に入れたいときは `ai-secrets` を使います。`~/.local/bin` が PATH に入っている前提なので、どのリポジトリ上でも同じコマンドで実行できます。

新しい package をローカルで試したあとに repo へ取り込みたいときは、`brew bundle dump` ではなく 1 件ずつ追記します。

```bash
brew install jq
make brew-add-core KIND=brew NAME=jq

brew install --cask google-chrome
make brew-add-home KIND=cask NAME=google-chrome

make brew-diff-home
make test
```

`make brew-diff*` は、現在の Brewfile とローカル Brew 実体の差分を見ます。formula は `brew leaves` 基準なので、依存ではなくトップレベルで入れたものだけが差分に出ます。

コマンドを覚えなくてよいように、ヒント表示も用意しています。

```bash
make tips
dothelp
```

`dothelp` は zsh helper で、`make tips` と同じ案内を出します。現在の profile に応じた日常コマンド、`sync-core` / `sync-home`、`brew-diff` / `brew-add-*` の例をまとめて見られます。

まだ `~/.config/dotfiles/profile` が無い既存マシンでは、`make preview` / `make update` / `make doctor` は一時的に `core` を既定として使います。  
その場合は一度だけ、意図する役割に合わせて `make install-home` または `make update-home` を実行してプロファイルを保存してください。

---

## ヘルスチェック

```bash
make doctor
```

`make doctor` は深い確認用です。日常確認は `make status`、AI 設定確認は `make ai-audit`、修復は `make ai-repair` を先に使う想定です。

`doctor.sh` は次の項目を確認します。

| チェック | 種別 | 合格条件 |
|---|---|---|
| `brew --version` | Required | Homebrew が使える |
| `chezmoi --version` | Required | chezmoi が使える |
| `chezmoi doctor` | Required | 内蔵チェックが実行できる (`failed` 行は warning 扱い) |
| `./scripts/brew-bundle.sh check <active-profile>` | Required | 現在の Brew プロファイルが満たされている |
| `git user.name` / `user.email` / `core.hooksPath` | Required | git identity が設定され、global hook が有効 |
| `node --version` | Optional | Codex CLI 導入に必要な node/npm がある |
| `uv --version` | Optional | Serena MCP に必要な `uv` がある |
| `brew-autoupdate` | Optional | dotfiles 方針では無効化されている（有効なら warning） |
| `gcloud version` | Optional | gcloud CLI がある |
| Python SSL compat | Optional | `sitecustomize.py` で `VERIFY_X509_STRICT` を無効化済み |
| `ghostty --version` | Optional | Ghostty CLI が存在し、バージョンが取得できる |
| `cmux --version` | Optional | cmux CLI が存在し、バージョンが取得できる |
| `claude --version` | Optional | Claude Code CLI がある |
| `~/.claude.json` serena | Optional | Claude Code 側で Serena MCP が登録されている |
| `codex --version` | Optional | Codex CLI がある |
| `~/.codex/config.toml` serena | Optional | Codex 側で Serena MCP が登録されている |
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

## MCP の基本セット（2026）

`home/dot_claude/dot_mcp.json` に、記事ベースの「とりあえずこれ入れておけ」構成を反映しています。

- `filesystem`
- `exa`
- `brave-search`
- `drawio`
- `serena`
- `playwright`
- `chrome-devtools`

検索系は `Exa MCP`（`https://mcp.exa.ai/mcp`、API key 不要）と `brave-search`（`@modelcontextprotocol/server-brave-search`、`BRAVE_API_KEY` を `mcp-with-keychain-secret` wrapper 経由で macOS Keychain から注入）の両方を入れています。

同じ baseline は `make ai-repair` 実行時に Claude Code の `~/.claude.json` と Codex の `~/.codex/config.toml` に再生成されます。`filesystem` は `"$HOME"` のみを root にし、存在しない optional directory は起動引数へ入れません。`make ai-audit` は MCP 登録が壊れている場合に warning を出します。

```bash
ai-secrets
make ai-audit
make ai-repair
```

## AI セッション

AI エージェントを並行運用するためのターミナル構成です。

### cmux（推奨）

`cmux` は libghostty ベースの AI エージェント特化ターミナルです。Ghostty の `~/.config/ghostty/` をそのまま読むため、テーマ・フォント設定を共有できます。

- タブに git branch / PR ステータス / 作業ディレクトリ / listening port を表示
- AI エージェントが入力待ちになるとタブ・ペインがハイライト（Claude Code hooks 対応）
- ターミナル横にスクリプタブルなブラウザペインを並べられる
- セッション復元（ワークスペースがアプリ再起動後も残る）
- Unix socket API / CLI で自動化可能

### zellij（併用可）

`zellij` は汎用のターミナルマルチプレクサとして引き続き使えます。

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
dothelp
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

`~/.gitconfig` は次を管理します。

- `user.name = <your configured identity>`
- `user.email = <your configured identity>`
- `core.hooksPath = ~/.config/git/hooks`

`~/.config/git/hooks/pre-commit` は、実際に commit に入る author / committer が global git config の値と一致しない場合に commit を止めます。`GIT_AUTHOR_*` や repo local config で上書きしても検査対象です。

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

## gcloud と企業プロキシ（Python 3.13 問題）

gcloud CLI は内部で Python を使います。Python 3.13 以降では `VERIFY_X509_STRICT` がデフォルトで有効になり、RFC 5280 に厳密に準拠した証明書チェーンを要求します。企業の CASB/プロキシ（Netskope, Zscaler 等）が SSL インスペクション（MITM）で使う CA 証明書は、`basicConstraints` に `critical` フラグが無い、Authority Key Identifier (AKI) が欠落している等の理由で拒否されることがあります。

参考: [Netskope 環境での Python 3.13 SSL 問題](https://blog.cloudnative.co.jp/28436/)

### 症状

`brew install --cask gcloud-cli` の postflight やその後の `gcloud` コマンドで SSL エラーが発生します。

```
ssl.SSLCertVerificationError: [SSL: CERTIFICATE_VERIFY_FAILED]
  certificate verify failed: Basic Constraints of CA cert not marked critical
```

### 対策: sitecustomize.py で VERIFY_X509_STRICT を無効化

Python 3.13+ の全プロセスに対して、起動時に `VERIFY_X509_STRICT` フラグを除去するモンキーパッチを適用します。gcloud だけでなく、awscli, aider, poetry 等の Python 3.13 製ツールもまとめて対応できます。

仕組み:
1. `~/.local/lib/python-ssl-compat/sitecustomize.py` が chezmoi で配置される
2. `env.zsh` がこのディレクトリを `PYTHONPATH` に追加
3. Python 3.13+ プロセスは起動時に `sitecustomize.py` を読み、SSL 検証を 3.12 相当に戻す
4. Python 3.12 以前には `hasattr` ガードで影響なし

`bootstrap.sh` は `brew bundle` の前にこのファイルをコピーするため、`gcloud-cli` cask の postflight も安全に動作します。

`make doctor` は SSL compat の有効/無効状態を表示します。

### 証明書ローテート後の無効化

Netskope 等のベンダーが RFC 5280 準拠の CA 証明書にローテートしたら、ワークアラウンドを無効化します。

```bash
# 即座に無効化（ファイルを消すだけ）
rm ~/.local/lib/python-ssl-compat/sitecustomize.py

# 新しいターミナルを開いて gcloud が動くことを確認
gcloud version

# 恒久化する場合は repo からも削除
rm ~/dotfiles/home/dot_local/lib/python-ssl-compat/sitecustomize.py
cd ~/dotfiles && git add -A && git commit -m "Remove SSL compat (Netskope cert rotated)"
chezmoi apply
```

### カスタム CA 証明書が必要な場合

プロキシ経由で `gcloud` を使う際にカスタム CA バンドルも必要な場合は、マシンローカルで設定します。

```bash
gcloud config set core/custom_ca_certs_file /path/to/corporate-ca-bundle.pem
export REQUESTS_CA_BUNDLE=/path/to/corporate-ca-bundle.pem
```

これらはマシン固有の認証情報に依存するため、dotfiles には含めず `.envrc`（direnv）等でローカル管理します。

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

`~/.claude/settings.json` は chezmoi 管理にしています。`defaultMode: "auto"` で AI 分類器による自動許可を有効にし、`WebFetch` / `WebSearch` も auto-allow しています。危険な操作は deny リストでブロックし、`git push` 等は ask で確認を挟みます。

`~/.claude/CLAUDE.md` も chezmoi 管理にしており、個人用の共通メモと運用方針を置きます。

`~/.claude/statusline.py` と `~/.claude/auto-save.sh` も chezmoi 管理です。`statusline.py` はステータスラインにモデル名・コスト・使用率を表示し、`auto-save.sh` は Stop フックからコンテキスト使用率が高い場合にメモリを自動保存します。

`~/.codex/config.toml` は chezmoi テンプレート管理にしています。`approval_policy = "on-request"` + `sandbox_mode = "workspace-write"`（`--full-auto` 相当）で auto モードを有効にしています。マシン固有のパスは `{{ .chezmoi.homeDir }}` で展開します。

`~/AGENTS.md` も chezmoi 管理にしており、Codex が参照する個人用の共通メモとして使います。

- `dotprofile` = 現在の dotfiles プロファイルを表示

Gemini は補助用途の one-shot コマンドを用意しています。

- `gr "<prompt>"` = `gemini -p "<prompt>"`
- `gmr [追加指示]` = 現在の git diff を Gemini にレビューさせる
- `gms [追加指示]` = 現在の git diff を Gemini に要約させる

`aider` も core Brew profile に含めています。git 管理下のコードを端末から直接編集させたいときの補助用途として使えます。

**Codex CLI** は `post-setup.sh` が公式 npm パッケージ経由で導入します。  
`node` は core Brew プロファイルに含めているので、新規マシンでもこの導線がそのまま使えます。

**Serena MCP** は Claude Code / Codex の両方で使う前提です。`~/.local/bin/serena-mcp` wrapper 経由で起動し、Homebrew の `uvx` とブラウザ自動起動抑止を明示しています。

`~/.serena/serena_config.yml` 自体は local state として各マシンに残しますが、`make status` / `make ai-audit` / `make doctor` で主要キー（`language_backend: LSP`、dashboard 設定、`project_serena_folder_location`）は監査するようにしています。

`make ai-repair` は `~/.serena/serena_config.yml` の期待値を再生成し、`~/.claude.json` と `~/.codex/config.toml` の Serena MCP 登録を wrapper に書き込みます。あわせて Codex の baseline として `model = "gpt-5.4"`、`model_reasoning_effort = "medium"`、`sandbox_mode = "workspace-write"`、`approval_policy = "on-request"`、`OpenAI Docs MCP` をそろえ、Claude Code 側は `~/.claude/settings.json` の `autoUpdatesChannel=latest` を保証します。CLI（`claude mcp add` 等）は使わず JSON / TOML を直接操作するため、MCP サーバーの起動やヘルスチェックによるタイムアウトが起きません。修復後は Claude Code / Codex を再起動してください。

MCP credential（Brave API key など）を Claude Code と Codex で共有したい場合は、`ai-secrets` を使います。対話入力は terminal 上で hidden に処理し、値は shell history に残さず macOS Keychain に保存します。その後 `make ai-repair` 相当を自動で流し、設定ファイルには平文 token を書かず、Keychain 読み出し wrapper 経由の設定だけを書き込みます。以前の `~/.config/dotfiles/ai-secrets.env` があれば、保存後に削除します。

```bash
ai-secrets
make ai-secrets
make ai-audit
```

`ai-secrets` の挙動は次のとおりです。

- Brave Search API Key を hidden 入力で受け取る
- 保存先は Keychain service `dotfiles.ai.mcp`
- account 名は `brave-api-key`
- Enter で現状維持、`-` で削除
- 保存後に `scripts/ai-repair.sh` を自動実行する

`chrome-devtools` は `chrome-devtools-mcp@latest` を標準の起動形で入れます。live Chrome を DevTools 経由で見に行けるので便利ですが、ブラウザ上の内容を agent に渡す前提になる点だけは意識してください。

`make ai-audit` は次の観点をまとめて確認します。

- `~/.claude.json` / `~/.codex/config.toml` の baseline
- Serena wrapper / OpenAI Docs MCP / filesystem/exa/brave-search/drawio/playwright/chrome-devtools の登録有無
- Brave API key が Keychain に存在するか
- 古い bridge 設定や危険な approval 設定が残っていないか

よくあるトラブルは次の 3 つです。

1. `filesystem` MCP が `initialize` で落ちる  
   原因の多くは存在しないディレクトリを root に渡していることです。この repo の baseline は `"$HOME"` だけを使います。`make ai-repair` で戻せます。
2. `ai-secrets` が古い wrapper を掴んで失敗する  
   `chezmoi apply ~/.local/bin/ai-secrets` で wrapper を再展開してください。
3. `brave-search` MCP が起動しない  
   `make ai-audit` で Keychain の有無を見て、足りなければ `ai-secrets` を再実行します。

**Claude Code CLI** は native install を正とし、`post-setup.sh` が `latest` チャンネルで導入します。Claude Code docs どおり native install はバックグラウンド自動更新に対応しているため、Homebrew cask では管理しません。

**brew-autoupdate** は dotfiles 方針で無効化しています。`post-setup.sh` は既存の launch agent / runner があれば削除し、`make status` / `make doctor` でも「無効が正常」として監査します。

```bash
./scripts/post-setup.sh
codex login
make doctor
```

セットアップ系のスクリプトは Bash 前提で書いているので、呼び出しは `bash` 明示です。日常利用は普段どおり `zsh` のままで問題ありません。

同梱している skill は `~/.codex/skills` に入り、`chezmoi apply` で反映されます。現在は `playwright`、`screenshot`、`doc`、`pdf`、`spreadsheet`、`jupyter-notebook`、`security-best-practices`、`ui-ux-pro-max` を同梱しています。`ui-ux-pro-max` は `nextlevelbuilder/ui-ux-pro-max-skill` の Codex 向け構成を repo 同梱化したものです。たとえば:

```zsh
~/.codex/skills/playwright/scripts/playwright_cli.sh open https://example.com
~/.codex/skills/playwright/scripts/playwright_cli.sh snapshot
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --mode temp --active-window
python3 ~/.codex/skills/ui-ux-pro-max/scripts/search.py "SaaS B2B analytics" --design-system -f markdown
```

**Superpowers plugin** は Claude Code セッション内で手動インストールです。

```text
/plugin install superpowers
```

### Claude Code / Gemini CLI のローカル state

Claude Code、Codex、Gemini CLI は、共通設定とローカル state を分けて管理します。

- Claude Code は `~/.claude/CLAUDE.md`、`~/.claude/settings.json`、`~/.claude/statusline.py`、`~/.claude/auto-save.sh`、`commands/`、`.mcp.json`、`statusline.sh` を dotfiles 管理する
- `~/.claude/settings.local.json` はマシン固有のオーバーライド用でローカル管理
- `~/.claude/history.jsonl`、`projects/`、`sessions/`、`cache/`、`plugins/`、`skills/`（プラグイン自動生成）などの運用データは管理しない
- Codex は `~/AGENTS.md`、`~/.codex/config.toml`（テンプレート）、`~/.codex/hooks.json`、`~/.codex/skills/` を dotfiles 管理する
- `~/.codex/auth.json`、`sessions/`、`history.jsonl`、`cache/`、`log/`、`sqlite` 系、`tmp/`、`rules/`（自動学習）、`memories/` などの運用データは管理しない
- Gemini CLI は `~/.gemini/settings.json` を dotfiles 管理する
- `~/.gemini/oauth_creds.json`、`google_accounts.json`、`history/`、`projects.json`、`state.json`、`trustedFolders.json`、`tmp/` などは管理しない
- GitHub CLI は `~/.config/gh/config.yml` を dotfiles 管理する
- `~/.config/gh/hosts.yml`（認証トークン）は管理しない

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
│   ├── dot_gitconfig.tmpl          # -> ~/.gitconfig
│   ├── dot_zshrc                   # -> ~/.zshrc
│   ├── dot_claude/
│   │   ├── CLAUDE.md               # -> ~/.claude/CLAUDE.md
│   │   ├── settings.json           # -> ~/.claude/settings.json (auto mode + permissions)
│   │   ├── executable_statusline.sh # -> ~/.claude/statusline.sh
│   │   ├── executable_statusline.py # -> ~/.claude/statusline.py
│   │   ├── executable_auto-save.sh # -> ~/.claude/auto-save.sh
│   │   ├── dot_mcp.json            # -> ~/.claude/.mcp.json
│   │   └── commands/               # -> ~/.claude/commands/*
│   ├── dot_codex/
│   │   ├── config.toml.tmpl        # -> ~/.codex/config.toml (chezmoi template)
│   │   ├── hooks.json              # -> ~/.codex/hooks.json
│   │   └── skills/                 # -> ~/.codex/skills/*
│   ├── dot_gemini/
│   │   └── settings.json           # -> ~/.gemini/settings.json
│   ├── dot_local/bin/
│   │   ├── ai-secrets              # -> ~/.local/bin/ai-secrets
│   │   ├── mcp-with-keychain-secret # -> ~/.local/bin/mcp-with-keychain-secret
│   │   └── serena-mcp              # -> ~/.local/bin/serena-mcp
│   ├── dot_local/lib/python-ssl-compat/
│   │   └── sitecustomize.py        # Python 3.13 VERIFY_X509_STRICT 無効化 (企業プロキシ対策)
│   ├── dot_local/share/navi/cheats/dotfiles/
│   │   ├── git.cheat
│   │   ├── shell.cheat
│   │   ├── files.cheat
│   │   └── terminal.cheat
│   └── dot_config/
│       ├── gh/config.yml           # -> ~/.config/gh/config.yml
│       ├── git/hooks/pre-commit    # global Git privacy guard
│       ├── ghostty/
│       │   ├── config.ghostty      # エントリポイント
│       │   ├── core.ghostty        # shell integration / scrollback
│       │   ├── ui.ghostty          # font / theme / padding
│       │   └── keybinds.ghostty    # 追加キーバインド
│       ├── dotfiles/profile        # ローカルの active profile (runtime state)
│       ├── zsh/
│       │   ├── env.zsh             # PATH / export / brew shellenv / PYTHONPATH (SSL compat)
│       │   ├── aliases.zsh         # alias 群
│       │   ├── tools.zsh           # starship / zoxide / atuin / fzf / navi / gcloud
│       │   └── completion.zsh      # compinit
│       └── starship.toml           # prompt 設定
├── scripts/
│   ├── ai-audit.sh                 # AI local config / MCP baseline の監査
│   ├── ai-repair.sh                # Serena / Claude / Codex の local drift 修復
│   ├── ai-secrets.sh               # Keychain へ MCP credential を対話保存
│   ├── brew-bundle.sh              # Brew profile の sync / install / check
│   ├── bootstrap.sh                # SSL compat + core brew + chezmoi + apply
│   ├── profile.sh                  # active profile の保存 / 参照
│   ├── preview.sh                  # chezmoi/Brew の変更予定を確認
│   ├── post-setup.sh               # Serena MCP + brew-autoupdate disable
│   ├── uninstall.sh                # dotfiles を削除
│   └── doctor.sh                   # 健全性チェック
└── .github/workflows/
    └── ci.yml                      # shellcheck + core brew bundle
```

---

## 今後の予定

- **APM (Agent Package Manager) によるチーム共有**: `microsoft/apm` は core Brewfile に導入済み。今後、Claude Code commands や Codex skills のうちチームで共有したいものを別リポジトリの APM パッケージとして切り出す予定。dotfiles はマシン単位の設定管理（chezmoi）、APM パッケージはプロジェクト単位のエージェント設定共有（`apm install`）という棲み分けで運用する
