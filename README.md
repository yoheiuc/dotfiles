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
| `make sync-all` | pull → `chezmoi apply` → brew install → `post-setup` → `doctor`（フル同期：新マシン導入後の drift 全部まとめて直す） | ✓ |
| `make sync` | `chezmoi apply` → brew sync 現在のプロファイル (cleanup あり) | ✓ |
| `make sync-core` | `chezmoi apply` → brew sync core (cleanup あり) | ✓ |
| `make sync-home` | `chezmoi apply` → brew sync home (cleanup あり) | ✓ |
| `make brew-diff` | 現在のプロファイルとローカル Brew 実体の差分確認 | ✓ |
| `make brew-diff-core` | core とローカル Brew 実体の差分確認 | ✓ |
| `make brew-diff-home` | home とローカル Brew 実体の差分確認 | ✓ |
| `make brew-add KIND=... NAME=...` | 現在のプロファイルの Brewfile に 1 件追加 | ✓ |
| `make brew-add-core KIND=... NAME=...` | core Brewfile に 1 件追加 | ✓ |
| `make brew-add-home KIND=... NAME=...` | home Brewfile に 1 件追加 | ✓ |
| `make tips` | よく使う dotfiles コマンドのヒント表示 | ✓ |
| `make doctor` | 現在のプロファイルで設定と依存の健全性確認 | ✓ |
| `make test` | shell ベースの回帰テスト | ✓ |
| `make test-scripts` | scripts/ 配下のシェルスクリプト回帰テスト | ✓ |
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
| `xcode-select -p` | Required | Xcode Command Line Tools がインストールされている |
| `brew --version` | Required | Homebrew が使える |
| `chezmoi --version` | Required | chezmoi が使える |
| `chezmoi doctor` | Required | 内蔵チェックが実行できる (`failed` 行は warning 扱い) |
| `./scripts/brew-bundle.sh check <active-profile>` | Required | 現在の Brew プロファイルが満たされている |
| `git user.name` / `user.email` / `core.hooksPath` | Required | git identity が設定され、global hook が有効 |
| `node --version` | Optional | Codex CLI 導入に必要な node/npm がある |
| `uv --version` | Optional | Serena MCP に必要な `uv` がある |
| `brew-autoupdate` | Optional | dotfiles 方針では無効化されている（有効なら warning） |
| Serena config | Optional | `~/.serena/serena_config.yml` の主要キーが期待値と一致する |
| `gcloud version` | Optional | gcloud CLI がある |
| Python SSL compat | Optional | `sitecustomize.py` で `VERIFY_X509_STRICT` を無効化済み |
| `ghostty --version` | Optional | Ghostty CLI が存在し、バージョンが取得できる |
| `zellij --version` | Optional | `zellij` がある |
| `ghq --version` | Optional | `ghq` がある |
| `navi --version` | Optional | `navi` と cheatsheet がある |
| `claude --version` | Optional | Claude Code CLI がある |
| `~/.claude.json` serena | Optional | Claude Code 側で Serena MCP が登録されている |
| `gemini --version` | Optional | Gemini CLI がある |
| `clasp --version` | Optional | clasp (Google Apps Script CLI) がある |
| `codex --version` | Optional | Codex CLI がある |
| `~/.codex/config.toml` serena | Optional | Codex 側で Serena MCP が登録されている |
| `codex hooks` / `hooks.json` | Optional | Codex hooks が有効で hooks.json が存在する |
| `OpenAI Docs MCP` | Optional | Codex 側で OpenAI Docs MCP が登録されている |
| `codex auto-save memory skill` | Optional | auto-save memory skill が配置されている |

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

- `exa`
- `brave-search`
- `slack`（remote HTTP + OAuth、`https://mcp.slack.com/mcp`）
- `serena`
- `chrome-devtools`
- `vision`（Apple Vision framework 経由の画像 OCR、`ja` / `en-US` / `zh-Hans` 等に対応、`npx -y @tuannvm/vision-mcp-server`。`mcp__vision__ocr_extract_text` で呼び出し。macOS 13+ / Node.js 18+ が前提。MCP connect に失敗したら `npx -y @tuannvm/vision-mcp-server --help` で直接確認。旧 `owlocr` MCP は upstream repo retirement に伴い 2026-04 に置換。）
- `sequential-thinking`（`post-setup.sh` で Claude Code に登録）

Notion は MCP ではなく公式 CLI (`ntn`) + skill の組み合わせを採用しています（下の「Notion CLI (ntn)」節参照）。token 効率と scripted 用途の両立を優先しました。

ブラウザ自動化は `@playwright/cli` + skill 方式に寄せているので、`@playwright/mcp` は含めていません（下の「Playwright CLI」節参照）。ファイル操作は Claude Code の native `Read` / `Write` / `Edit` / `Grep` / `Glob` で代替できるため、`filesystem` MCP も外しました。図は Mermaid（`.md` 直埋め）か `mermaid-cli` の `mmdc` で text diff フレンドリーに扱えるため、`@drawio/mcp` も外しています。

検索系は `Exa MCP`（`https://mcp.exa.ai/mcp`、API key 不要）と `brave-search`（`@modelcontextprotocol/server-brave-search`、`BRAVE_API_KEY` を `mcp-with-keychain-secret` wrapper 経由で macOS Keychain から注入）の両方を入れています。

同じ baseline は `make ai-repair` 実行時に Claude Code の `~/.claude.json` と Codex の `~/.codex/config.toml` に再生成されます。`make ai-audit` は MCP 登録が壊れている場合に warning を出します。旧 dotfiles の `playwright` / `filesystem` / `drawio` / `notion` / `github` / `owlocr` MCP 登録が残っている場合も `make ai-repair` で自動的に削除されます。

```bash
ai-secrets
make ai-audit
make ai-repair
```

## Notion CLI (`ntn`)

Notion 公式の CLI + skill 方式を採用しています。Playwright CLI と同じ「CLI + skill の方が token 効率が良く、scripted 用途にも使える」というパターンです。

### なぜ MCP ではなく CLI か

- **公式 CLI が存在する**（`https://ntn.dev`、Notion 配布）。Notion 公式 MCP が hosted で Markdown 変換を行うのと同じ品質を、CLI の `ntn block list --md` で出せる
- **token 効率**：CLI 出力は pipe できるので agent context を圧迫しない
- **scripted 用途**：shell pipeline / cron / CI から触れる。MCP だと Claude Code を起動していないと使えない
- **公式 skill** が `~/.claude/skills/notion-cli/` と `~/.codex/skills/notion-cli/` に配布されるので、agent は自動で使い方を理解する

### インストール

`make install-home` が走ると `scripts/post-setup.sh` が idempotent に以下を実行します。

```bash
curl -fsSL https://ntn.dev | bash                                  # ntn CLI
npx -y skills add https://github.com/makenotion/skills -a claude-code --skill notion-cli
npx -y skills add https://github.com/makenotion/skills -a codex --skill notion-cli
```

### 認証

初回だけ手動で実行：

```bash
ntn login    # ブラウザ OAuth フロー
```

あるいは CI 等では `NOTION_API_TOKEN` env var に integration token を入れて使います（推奨は OAuth）。

### よく使うコマンド

```bash
ntn api pages/<page-id>          # ページ情報
ntn block list <page-id> --md    # ページ本文を Markdown で読む
ntn block append <page-id> --file doc.md   # Markdown をページに追記
ntn files upload ./screenshot.png          # ファイルアップロード
ntn workers deploy               # Notion workers 管理
```

### Blast radius の方針

- **AI セッション用には admin workspace を接続しない**。閲覧 / 限定書き込み用の integration を別に作る
- `NOTION_API_TOKEN` を使う場合は Keychain 経由で注入（`mcp-with-keychain-secret` wrapper と同じパターン）。plaintext で `.env` に書かない
- 権限を持つアカウントのセッションは AI 用に作らない（Playwright CLI と同じ方針）

## Slack MCP（remote + OAuth）

Slack は remote HTTP MCP + OAuth 方式を採用しています。ローカルに stdio プロセスを生やさず、token も Keychain に置かない（OAuth token は Claude Code 側が管理）のが設計上のポイントです。

### 初回認証

Claude Code では `/mcp` コマンドからブラウザが開いて OAuth フローが走ります。認証承認後は `make ai-audit` で `registered` が出ます。

### スコープの方針（blast radius 最小化）

| 推奨スコープ | 避けるスコープ |
|---|---|
| `channels:history` / `groups:history` / `search:read` / `chat:write`（通知用）まで | `admin.*` 系、`files:write`、全 workspace 管理系トークン |

AI セッション用のスコープは **読み取り中心 + 必要最低限の書き込み** に絞り、管理系権限は別の運用アカウントに分けるのが Playwright CLI / Notion CLI でも採用している方針と同じです。

### なぜ CLI ではなく MCP か（Slack の場合）

Slack 公式 MCP が OAuth フロー込みで配布されており、公式 CLI（`slack-cli`）は Slack アプリ開発用途向けで IT ops の読み書きには合いません。Notion は CLI が筋、Slack は MCP が筋、と分岐しています。

## Playwright CLI（ブラウザ自動化）

情シス業務の自動化（SaaS 管理画面の巡回、チケットの一括処理など）向けに、`@playwright/cli` を CLI + Skill 方式で導入しています。Claude Code / Codex から長時間のブラウザセッションを回すのが目的です。

### MCP ではなく CLI を選んでいる理由

- **トークン効率が高い**：snapshot をディスクに書き出すので、agent の context を食わない
- **長時間セッションに強い**：`--persistent` で Cookie / localStorage を保持し、ログインを使い回せる
- **Claude Code が自動で理解する**：`playwright-cli install --skills` が `~/.claude/skills/playwright/` と `~/.codex/skills/playwright/` を配置し、両 agent から skill として認識される

### インストール

`make install-home` が走ると `scripts/post-setup.sh` が自動で以下を流します（idempotent）。

```bash
npm install -g @playwright/cli@latest
playwright-cli install-browser        # Chromium
playwright-cli install --skills       # Claude Code / Codex skill
```

前提は Node.js / npm（core Brewfile の `brew "node"` で入る）。

### zsh ヘルパー

`home/dot_config/zsh/playwright.zsh` で 6 関数を提供しています。

| コマンド | 用途 |
|---|---|
| `pwsession <name>` | セッション名を `PLAYWRIGHT_CLI_SESSION` に export |
| `pwlogin <name> <url>` | `--headed --persistent` で起動し、手動ログイン用に可視ブラウザを開く |
| `pwlist` | `playwright-cli list`：永続セッション一覧 |
| `pwshow` | `playwright-cli show`：ダッシュボードを起動して実行中セッションを監視 |
| `pwkill <name>` | 指定セッションの永続データを削除 |
| `pwkillall` | 全 playwright-cli プロセスを強制終了 |

プロジェクト単位で `.envrc` に `export PLAYWRIGHT_CLI_SESSION=<name>` を置けば、`cd` だけで切り替わります。テンプレは `docs/examples/envrc.playwright.example` にあります。

### セッション運用ルール

- **タスク / SaaS 単位で分離する**：`-s=freshservice`、`-s=intune-admin` のように名前で境界を引く
- **管理者権限アカウントでは AI 用セッションを作らない**。read-only / 閲覧権限の別アカウントでログインする
- **初回ログインフロー**：`pwlogin <name> <url>` で可視起動 → 手動ログイン（2FA 含む）→ 閉じる → 以降は Claude Code から headless で利用可能
- **セッション切れ時**：同じ名前で `pwlogin` を再実行するだけで上書き再ログインできる
- **不要になったセッションは `pwkill <name>` で削除**

### セキュリティ上の注意

`--persistent` で保存されるプロファイル（Cookie / localStorage / IndexedDB）は macOS の Keychain Safe Storage で暗号化されますが、**ユーザー権限で動くマルウェアからは読めます**。特に Cookie 窃取は 2FA もパスワードも迂回されるため、情報窃取型マルウェア（Lumma Stealer、RedLine など）の主要な標的です。FileVault は起動中マルウェアに対しては無力（盗難時のオフライン読み出し対策のみ）。

設計原則：

- AI 用セッションを分ける意義は「漏洩を防ぐ」ではなく「**blast radius を最小化する**」
- 権限を持つアカウント（全社管理者など）のセッションは AI 用に作らない
- IdP 側 session lifetime を絞って Cookie の寿命を短くする
- `pwshow` のダッシュボードを可視運用で回し、想定外の操作が走っていないか監視する
- EDR / XProtect は常時有効にする
- 機微データ・規制対象データ（PII、財務情報など）を扱うセッションでは使わない

## AI セッション

AI エージェントを並行運用するためのターミナル構成です。`zellij` をマルチプレクサとして使います。

`~/.config/zellij/config.kdl` は discoverability を少しだけ強めています。

- `F1`: `about` を開いてキーバインドやヘルプを確認
- `F2`: `session-manager` を開いてセッション一覧/復帰/切替
- `F3`: `configuration` を開いて UI とキーバインド設定を確認
- マウス hover で pane frame の補助表示を出し、pane 境界の drag で resize
- `Ctrl` を押しながら floating pane の境界を drag、またはホイールで resize

`compact` レイアウトを使う場合でも、下部 `compact-bar` のヒントは `F1` で表示できます。

AI 作業用のカスタムレイアウト `layouts/ai.kdl` も同梱しています。メイン pane（65%）+ 右側に実行・参照 pane を縦分割した構成です。

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

`~/.claude/settings.json` 本体はローカル管理です（Claude Code 自身が `permissions` / `model` / `effortLevel` / `statusLine` を随時書き込むため、dotfiles が全体を所有すると必ず drift する）。dotfiles は **baseline キーだけ** を `make ai-repair` で upsert し、それ以外のキーは触りません。

baseline として保証されるのは以下:

- `autoUpdatesChannel: "latest"`
- `env.ENABLE_TOOL_SEARCH: "auto:5"` でツール検索を自動化
- `hooks.PreToolUse` Grep → `lsp-hint.sh`（Serena 推奨を stderr で提示、block はしない）
- `hooks.Stop` → `auto-save.sh`（コンテキスト使用率が高い場合にメモリを自動保存）
- `hooks.Notification` → macOS 通知（osascript）

`permissions` / `model` / `effortLevel` / `statusLine` は各マシンで自由に変えられます。`make ai-audit` は baseline キーの存在だけを検査します。

`~/.claude/CLAUDE.md` も chezmoi 管理にしており、個人用の共通メモ・MCP ツール選択ルール・Serena の使い方を置きます。

`~/.claude/statusline.sh` と `~/.claude/auto-save.sh`、`~/.claude/lsp-hint.sh` も chezmoi 管理です。`statusline.sh` はステータスラインにモデル名・コスト・使用率を表示し、`auto-save.sh` は Stop フックからコンテキスト使用率が高い場合にメモリを自動保存します。`lsp-hint.sh` は PreToolUse フックから呼ばれる advisory で、Grep が明らかなコードシンボル検索っぽい時に Serena の LSP tool 推奨を stderr に出します（block はしない）。

`~/.codex/config.toml` は chezmoi テンプレート管理にしています。主な設定:

- `model = "gpt-5.4"`、`model_reasoning_effort = "medium"`
- `approval_policy = "on-request"` + `sandbox_mode = "workspace-write"`（`--full-auto` 相当）
- `[features]`: `multi_agent = true`、`codex_hooks = true`
- `[plugins]`: Google Calendar, GitHub, Gmail, Google Drive, build-macos-apps, build-ios-apps（Notion は `ntn` CLI + `makenotion/skills` に移行済み、curated plugin も無効化）
- MCP サーバー: Serena, chrome-devtools, vision, exa, brave-search, slack, OpenAI Developer Docs
- マシン固有のパスは `{{ .chezmoi.homeDir }}` で展開

`~/.codex/hooks.json` も chezmoi 管理にしています。Stop フックで `codex-auto-save-memory` skill を実行し、セッション終了時にメモリを自動保存します。

`~/AGENTS.md` も chezmoi 管理にしており、Codex が参照する個人用の共通メモとして使います。

- `dotprofile` = 現在の dotfiles プロファイルを表示

Gemini は補助用途の one-shot コマンドを用意しています。

- `gr "<prompt>"` = `gemini -p "<prompt>"`
- `gmr [追加指示]` = 現在の git diff を Gemini にレビューさせる
- `gms [追加指示]` = 現在の git diff を Gemini に要約させる
- `gmd [追加指示]` = 現在の git diff の意図・影響・リスクを Gemini に説明させる

`aider` も core Brew profile に含めています。git 管理下のコードを端末から直接編集させたいときの補助用途として使えます。

**clasp** (Google Apps Script CLI) は `post-setup.sh` が `npm install -g @google/clasp` で導入します。初回は `clasp login` で Google アカウント認証が必要です。

**Codex CLI** は `post-setup.sh` が公式 npm パッケージ経由で導入します。  
`node` は core Brew プロファイルに含めているので、新規マシンでもこの導線がそのまま使えます。  
`post-setup.sh` は併せて **Sequential Thinking MCP** を Claude Code に登録し、**Google Workspace CLI (gws) skills** を Claude Code / Codex 両方にインストールします。

**Serena MCP** は Claude Code / Codex の両方で使う前提です。`~/.local/bin/serena-mcp` wrapper 経由で起動し、Homebrew の `uvx` とブラウザ自動起動抑止を明示しています。

`~/.serena/serena_config.yml` 自体は local state として各マシンに残しますが、`make status` / `make ai-audit` / `make doctor` で主要キー（`language_backend: LSP`、dashboard 設定、`project_serena_folder_location`）は監査するようにしています。

`make ai-repair` は `~/.serena/serena_config.yml` の期待値を再生成し、`~/.claude.json` と `~/.codex/config.toml` の Serena MCP 登録を wrapper に書き込みます。あわせて Codex の baseline として `model = "gpt-5.4"`、`model_reasoning_effort = "medium"`、`personality = "pragmatic"`、`sandbox_mode = "workspace-write"`、`approval_policy = "on-request"`、`OpenAI Docs MCP` をそろえ、Claude Code 側は `~/.claude/settings.json` の `autoUpdatesChannel=latest` を保証します。CLI（`claude mcp add` 等）は使わず JSON / TOML を直接操作するため、MCP サーバーの起動やヘルスチェックによるタイムアウトが起きません。修復後は Claude Code / Codex を再起動してください。

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

- `~/.claude.json` / `~/.codex/config.toml` の baseline（model, sandbox, approval, features, hooks）
- Serena wrapper / OpenAI Docs MCP / exa/slack/brave-search/chrome-devtools/vision の登録有無（レガシーな `playwright` / `filesystem` / `drawio` / `notion` / `github` / `owlocr` MCP が残っていれば warning）
- Brave API key が Keychain に存在するか
- Serena config の主要キー（`language_backend`, `web_dashboard`, `project_serena_folder_location`）
- 古い bridge 設定や危険な approval 設定が残っていないか
- バックアップファイル（`.bak`）の残存

よくあるトラブルは次の 3 つです。

1. 旧 dotfiles から移行したら `playwright` / `filesystem` / `drawio` / `notion` MCP が残っている  
   `make ai-repair` が自動的に削除します。残っていれば `make ai-audit` が warning を出すので、それを目印に repair を走らせてください。
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

同梱している skill は `~/.codex/skills` に入り、`chezmoi apply` で反映されます。現在は `screenshot`、`doc`、`pdf`、`spreadsheet`、`jupyter-notebook`、`security-best-practices`、`ui-ux-pro-max`、`codex-auto-save-memory` を同梱しています。`ui-ux-pro-max` は `nextlevelbuilder/ui-ux-pro-max-skill` の Codex 向け構成を repo 同梱化したものです。`playwright` skill は `post-setup.sh` が `playwright-cli install --skills` で配置するため dotfiles 本体では管理しません（gws skills と同じ扱い）。たとえば:

```zsh
playwright-cli open https://example.com
playwright-cli snapshot
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --mode temp --active-window
python3 ~/.codex/skills/ui-ux-pro-max/scripts/search.py "SaaS B2B analytics" --design-system -f markdown
```

**Superpowers plugin** / **Context7 plugin** は Claude Code セッション内で手動インストールです（Anthropic 公式 marketplace 経由、dotfiles 管理外）。

```text
/plugin install superpowers
/plugin install context7@claude-plugins-official
```

Superpowers は 14 skill の agent discipline framework（clarify → design → plan → code → verify）、Context7 は最新ライブラリドキュメントを context に注入して API 幻覚を抑える plugin。どちらも tool surface を持たないので context 消費は最小。

**frontend-design skill** は `anthropics/claude-plugins-official` の `frontend-design` plugin（Apache-2.0）を `home/dot_claude/skills/frontend-design/` に vendor してあります。`/plugin install` を各マシンで打つ代わりに `chezmoi apply` で配布する方針で、`doctor.sh` が SKILL.md の存在を検査します。upstream 更新に追従するときは `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/frontend-design/skills/frontend-design/SKILL.md` を source にコピーし直してください。

### Claude Code / Gemini CLI のローカル state

Claude Code、Codex、Gemini CLI は、共通設定とローカル state を分けて管理します。

- Claude Code は `~/.claude/CLAUDE.md`、`~/.claude/statusline.sh`、`~/.claude/auto-save.sh`、`~/.claude/lsp-hint.sh`、`commands/`、`.mcp.json` を dotfiles 管理する
- `~/.claude/settings.json` 本体はローカル管理（Claude Code が `permissions` / `model` / `effortLevel` / `statusLine` を随時書き込むため）。baseline キー（`autoUpdatesChannel` / `env.ENABLE_TOOL_SEARCH` / `hooks`）だけ `make ai-repair` が upsert する
- `~/.claude/settings.local.json` はマシン固有のオーバーライド用でローカル管理
- `~/.claude/skills/` のうち `frontend-design` は dotfiles 管理（`home/dot_claude/skills/frontend-design/`、Apache-2.0 で Anthropic 公式 marketplace から vendor）。gws / playwright / notion など外部 CLI で配布される skill は `post-setup.sh` が配置するので dotfiles 本体では管理しない
- `~/.claude/history.jsonl`、`projects/`、`sessions/`、`cache/`、`plugins/` などの運用データは管理しない
- Codex は `~/AGENTS.md`、`~/.codex/config.toml`（テンプレート）、`~/.codex/hooks.json`、`~/.codex/skills/`（chezmoi 同梱 + gws skills）を dotfiles 管理する
- `~/.codex/auth.json`、`sessions/`、`history.jsonl`、`cache/`、`log/`、`sqlite` 系、`tmp/`、`rules/`（自動学習）、`memories/` などの運用データは管理しない
- Gemini CLI は `~/.gemini/settings.json`（OAuth personal 認証、UI 設定）を dotfiles 管理する
- `~/.gemini/oauth_creds.json`、`google_accounts.json`、`history/`、`projects.json`、`state.json`、`trustedFolders.json`、`tmp/` などは管理しない
- GitHub CLI は `~/.config/gh/config.yml`（HTTPS プロトコル、`co` = `pr checkout` alias）を dotfiles 管理する
- `~/.config/gh/hosts.yml`（認証トークン）は管理しない

---

## ディレクトリ構成

```text
dotfiles/
├── AGENTS.md                        # dotfiles リポジトリ用の Codex ガイド
├── Makefile                        # install / update / doctor / uninstall
├── .chezmoiroot                    # "home" を chezmoi source root として使う
├── .gitignore
├── home/                           # chezmoi source state -> $HOME
│   ├── AGENTS.md                   # -> ~/AGENTS.md (Codex 用共通メモ)
│   ├── dot_Brewfile.core           # -> ~/.Brewfile.core
│   ├── dot_Brewfile.home           # -> ~/.Brewfile.home
│   ├── dot_gitconfig.tmpl          # -> ~/.gitconfig
│   ├── dot_zshrc                   # -> ~/.zshrc
│   ├── dot_python-version          # -> ~/.python-version
│   ├── dot_claude/
│   │   ├── CLAUDE.md               # -> ~/.claude/CLAUDE.md (MCP 選択ルール・Serena 運用)
│   │   ├── executable_statusline.sh # -> ~/.claude/statusline.sh
│   │   ├── executable_auto-save.sh # -> ~/.claude/auto-save.sh
│   │   ├── executable_lsp-hint.sh  # -> ~/.claude/lsp-hint.sh (PreToolUse advisory)
│   │   ├── dot_mcp.json            # -> ~/.claude/.mcp.json
│   │   ├── commands/               # -> ~/.claude/commands/* (18 コマンドガイド)
│   │   └── skills/
│   │       └── frontend-design/    # -> ~/.claude/skills/frontend-design (Apache-2.0 vendor from claude-plugins-official)
│   ├── dot_codex/
│   │   ├── config.toml.tmpl        # -> ~/.codex/config.toml (chezmoi template)
│   │   ├── hooks.json              # -> ~/.codex/hooks.json (auto-save memory)
│   │   └── skills/                 # -> ~/.codex/skills/* (8 skills; playwright は post-setup が CLI 配置)
│   │       ├── screenshot/
│   │       ├── doc/
│   │       ├── pdf/
│   │       ├── spreadsheet/
│   │       ├── jupyter-notebook/
│   │       ├── security-best-practices/
│   │       ├── ui-ux-pro-max/
│   │       └── codex-auto-save-memory/
│   ├── dot_gemini/
│   │   └── settings.json           # -> ~/.gemini/settings.json
│   ├── dot_local/bin/
│   │   ├── ai-secrets              # -> ~/.local/bin/ai-secrets
│   │   ├── mcp-with-keychain-secret # -> ~/.local/bin/mcp-with-keychain-secret
│   │   └── serena-mcp              # -> ~/.local/bin/serena-mcp
│   ├── dot_local/lib/python-ssl-compat/
│   │   └── sitecustomize.py        # Python 3.13 VERIFY_X509_STRICT 無効化 (企業プロキシ対策)
│   ├── dot_local/share/navi/cheats/dotfiles/
│   │   ├── ai.cheat                # AI ツール (Claude / Gemini / Aider)
│   │   ├── git.cheat
│   │   ├── shell.cheat
│   │   ├── files.cheat
│   │   └── terminal.cheat
│   └── dot_config/
│       ├── atuin/config.toml       # -> ~/.config/atuin/config.toml
│       ├── gh/config.yml           # -> ~/.config/gh/config.yml
│       ├── git/hooks/pre-commit    # global Git privacy guard
│       ├── ghostty/
│       │   ├── config.ghostty      # エントリポイント
│       │   ├── core.ghostty        # shell integration / scrollback
│       │   ├── ui.ghostty          # font / theme / padding
│       │   └── keybinds.ghostty    # 追加キーバインド
│       ├── zellij/
│       │   ├── config.kdl          # zellij 設定 (catppuccin-mocha / mouse / keybinds)
│       │   └── layouts/ai.kdl      # AI 作業用レイアウト
│       ├── dotfiles/profile        # ローカルの active profile (runtime state)
│       ├── zsh/
│       │   ├── env.zsh             # PATH / export / brew shellenv / PYTHONPATH (SSL compat)
│       │   ├── aliases.zsh         # alias 群
│       │   ├── tools.zsh           # starship / zoxide / atuin / fzf / navi / gcloud / Gemini helpers
│       │   └── completion.zsh      # compinit
│       └── starship.toml           # prompt 設定
├── scripts/
│   ├── ai-audit.sh                 # AI local config / MCP baseline の監査
│   ├── ai-repair.sh                # Serena / Claude / Codex の local drift 修復
│   ├── ai-secrets.sh               # Keychain へ MCP credential を対話保存
│   ├── brew-add.sh                 # Brewfile への 1 件追加
│   ├── brew-bundle.sh              # Brew profile の sync / install / check
│   ├── brew-diff.sh                # Brewfile とローカル Brew 実体の差分表示
│   ├── bootstrap.sh                # SSL compat + core brew + chezmoi + apply
│   ├── doctor.sh                   # 健全性チェック
│   ├── dotfiles-help.sh            # コマンドヒント表示
│   ├── post-setup.sh               # Claude/Codex CLI + MCP 登録 + gws skills + brew-autoupdate disable
│   ├── preview.sh                  # chezmoi/Brew の変更予定を確認
│   ├── profile.sh                  # active profile の保存 / 参照
│   ├── status.sh                   # 日常確認用の簡易ステータス
│   ├── uninstall.sh                # dotfiles を削除
│   └── lib/                        # 共有ライブラリ
│       ├── ai-config.sh            # JSON/TOML 操作・Keychain・MCP 登録ヘルパー
│       ├── brew-autoupdate.sh      # brew-autoupdate の管理ヘルパー
│       └── brew-profile.sh         # Brew profile drift 検出ヘルパー
├── tests/                          # シェルベースの回帰テスト
│   ├── lib/testlib.sh
│   ├── profile.sh
│   ├── status.sh
│   ├── serena-wrapper.sh
│   ├── dothelp.sh
│   ├── brew-tools.sh
│   ├── ai-audit.sh
│   ├── ai-secrets.sh
│   ├── ai-secrets-wrapper.sh
│   ├── ai-repair.sh
│   └── doctor.sh
├── docs/
│   ├── notes/current-state.md      # 運用メモ
│   └── examples/chezmoidata.yaml   # chezmoi data のサンプル
└── .github/workflows/
    └── ci.yml                      # shellcheck + bundle validation + 回帰テスト
```

---

## 今後の予定

- **APM (Agent Package Manager) によるチーム共有**: `microsoft/apm` は core Brewfile に導入済み。今後、Claude Code commands や Codex skills のうちチームで共有したいものを別リポジトリの APM パッケージとして切り出す予定。dotfiles はマシン単位の設定管理（chezmoi）、APM パッケージはプロジェクト単位のエージェント設定共有（`apm install`）という棲み分けで運用する
