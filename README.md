# dotfiles

macOS 向けの開発マシンを chezmoi で再現可能に管理するための dotfiles。Claude Code を中心にした AI 設定、情シス業務で触る SaaS 群の自動化、credential の Keychain 集約、drift の自己修復までを 1 本のリポジトリに閉じ込めている。

運用中の状態は [docs/notes/current-state.md](docs/notes/current-state.md)。ライセンスは [MIT](LICENSE)。

> 個人マシン用の opinionated な設定。`chezmoi apply` は `~/` 以下を上書きしうる。他人が使うなら fork して [fork して使うとき](#fork-して使うとき) の書き換え箇所を潰してから apply すること。

---

## 特徴

- **Claude Code + MCP baseline**: `settings.json` に model / sandbox / approval / hooks を揃え、MCP baseline（Exa / Slack / Vision、Claude 専用: sequential-thinking）を配る。コード解析は `claude-plugins-official` の per-language LSP plugin 群（Serena MCP からの乗り換え）。drift は `make ai-repair` で期待値に戻す
- **MCP / CLI / 削除の判定マトリクス**: 新ツール追加前に [採用基準](#ツール採用基準mcp--cli--削除) を通す。MCP を選ぶのは symbol 解析や CoT scaffolding など agent context と不可分なものだけ
- **credential は Keychain 一択**: stdio MCP の secret は `mcp-with-keychain-secret` wrapper 経由で注入、設定ファイルには参照だけ。`.env` / `hosts.yml` / `auth.json` は dotfiles に入れない
- **`pwattach` で実 Chrome を agent に露出**: `@playwright/cli` の `attach --cdp=chrome` を zsh helper 化。`PLAYWRIGHT_AI_CHROME_READY=1` で AI 専用プロファイル運用を強制。実 Chrome 特有のリスクは [pwattach のセキュリティ](#pwattach-のセキュリティ実-chrome-アタッチ特有のリスク) で分解
- **drift は自己修復**: `make ai-repair` が Claude `~/.claude.json` / hooks / channel を baseline に戻し、legacy MCP（`playwright` / `filesystem` / `drawio` / `notion` / `github` / `owlocr` / `chrome-devtools` / `brave-search` / `serena`）を能動削除
- **3 段の可観測性**: `make status` = 日常 sanity check、`make ai-audit` = AI 設定の監査、`make doctor` = required + optional の深掘り。すべて shell で中身が追える
- **single source of truth**: `home/` が正。`~/` だけ変更しても次の `chezmoi apply` で巻き戻る前提
- **git identity の privacy guard**: global `pre-commit` hook が author / committer を `git config --global` と照合し、ズレたら commit を止める
- **企業 CASB 対策**: Python 3.13 の `VERIFY_X509_STRICT` に弾かれる MITM 証明書を sitecustomize.py で 3.12 相当に戻す（[詳細](docs/setup-guides/gcloud-python-ssl.md)）
- **brew autoupdate は policy で disable**: silent upgrade で dev 環境を壊さないための意図的運用。`make doctor` が有効状態を warn

---

## 目次

- [前提条件](#前提条件)
- [初期セットアップ](#初期セットアップ)
- [日常の更新](#日常の更新) / [ヘルスチェック](#ヘルスチェック)
- [設計思想](#設計思想)（ツール採用基準 / 整合性 / セキュリティモデル）
- [MCP の基本セット（2026）](#mcp-の基本セット2026) / [Notion CLI](#notion-cli-ntn) / [Slack MCP](#slack-mcpremote--oauth) / [Playwright CLI](#playwright-cliブラウザ自動化)
- [AI セッション](#ai-セッション) / [chezmoi の基本運用](#chezmoi-の基本運用) / [巻き戻し](#巻き戻し)
- [Git の privacy guard](#git-の-privacy-guard) / [Brewfile](#brewfile)
- [マシン固有のセットアップガイド](#マシン固有のセットアップガイド)（gcloud Python SSL、Ghostty は `docs/setup-guides/`）
- [Claude Code / MCP](#claude-code--mcp)
- [ディレクトリ構成](#ディレクトリ構成) / [トラブルシューティング](#トラブルシューティング) / [fork して使うとき](#fork-して使うとき)

---

## 前提条件

| 項目 | 内容 |
|---|---|
| macOS | 13 Ventura 以降（Apple Silicon / Intel 両対応）。`vision` MCP が macOS 13+ の Apple Vision framework を使うため、下限はここ |
| Homebrew | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Git | Xcode CLT (`xcode-select --install`) または `brew install git` |

`~/.gitconfig` は chezmoi template（`home/dot_gitconfig.tmpl`）で生成する。bootstrap 時の `git config --global user.*` を優先的に読み、未設定時は `.chezmoidata.yaml` の `gitIdentity.*` にフォールバックする。global `pre-commit` hook が commit 時の author / committer を `git config --global` と照合して、ズレたら commit を止める。

git identity は以下のどちらかで決めておく。

```bash
# 既に global config がある場合はそのまま使える
git config --global user.name "Your Name"
git config --global user.email "your-github-id@users.noreply.github.com"

# もしくは chezmoidata 経由で上書き
cp docs/examples/chezmoidata.yaml .chezmoidata.yaml
$EDITOR .chezmoidata.yaml    # gitIdentity.name / gitIdentity.email
```

Brewfile は `home/dot_Brewfile`（実体: `~/.Brewfile`）に 1 本化してある。新規パッケージは source を直接編集し、`make sync` で `brew bundle` + `cleanup` を流して反映する。

---

## 初期セットアップ

```bash
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
cd ~/dotfiles

make install         # brew bundle + chezmoi apply + post-setup
exec zsh             # shell を reload して PATH を反映
make doctor          # required 項目がすべて pass することを確認
make preview         # 以降の変更は apply 前に必ず diff を確認
```

### make ターゲット一覧

```bash
make help
```

| ターゲット | 内容 |
|---|---|
| `make status` | 日常確認に必要な状態を短く表示 |
| `make ai-audit` | ローカル管理の AI 設定だけを詳しく確認 |
| `make ai-repair` | AI 周りの local drift を修復（MCP registration / hooks / legacy 掃除） |
| `make ai-secrets` | Claude Code の MCP credential を Keychain に保存（現状 consumer なし、framework として残置） |
| `make install` | Brew + `chezmoi apply` + `post-setup` |
| `make preview` | `chezmoi diff` + dry-run + brew preview |
| `make sync` | `chezmoi apply` + brew sync (cleanup あり) + `post-setup` |
| `make sync PULL=1` | `git pull` してから `sync` を実行 |
| `make tips` | よく使う dotfiles コマンドのヒント表示 |
| `make doctor` | セットアップ状態の深い確認 |
| `make test` | shell ベースの回帰テスト |
| `make uninstall` | dotfiles を削除 |

---

## 日常の更新

```bash
cd ~/dotfiles
make status
make ai-audit
make ai-repair
make preview
make sync
make sync PULL=1
make tips
```

ふだんは `make status` でざっと状態を見て、AI 設定を触ったあとは `make ai-audit`、MCP 登録や hooks が怪しいときは `make ai-repair` を使います。Homebrew 実体を定義どおりに寄せたいときは `make sync`（`chezmoi apply` + brew sync + cleanup + post-setup）で一発同期します。remote の更新も取り込むときは `make sync PULL=1`。
Claude Code の MCP credential（Keychain 経由で stdio MCP に注入）を安全に入れたいときは `ai-secrets` を使います。現状デフォルトで wiring している consumer はありませんが、将来 stdio MCP を足す想定で wrapper + 対話保存フローを残しています。`~/.local/bin` が PATH に入っている前提なので、どのリポジトリ上でも同じコマンドで実行できます。

新しい package をローカルで試したあとに repo へ取り込みたいときは、`home/dot_Brewfile` を直接編集して commit します。

```bash
brew install jq
$EDITOR home/dot_Brewfile   # brew "jq" を追記
make sync                    # 実体へ反映 + cleanup
```

コマンドを覚えなくてよいように、ヒント表示も用意しています。

```bash
make tips
dothelp
```

`dothelp` は zsh helper で、`make tips` と同じ案内を出します。

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
| `./scripts/brew-bundle.sh check` | Required | Brewfile の package がすべて入っている |
| `git user.name` / `user.email` / `core.hooksPath` | Required | git identity が設定され、global hook が有効 |
| `node --version` | Optional | playwright-cli 等に必要な node/npm がある |
| `uv --version` | Optional | Python 周りで使う `uv` が入っている（Serena retire 後は必須ではない） |
| `brew-autoupdate` | Optional | dotfiles 方針では無効化されている（有効なら warning） |
| `gcloud version` | Optional | gcloud CLI がある |
| Python SSL compat | Optional | `sitecustomize.py` で `VERIFY_X509_STRICT` を無効化済み |
| `ghostty --version` | Optional | Ghostty CLI が存在し、バージョンが取得できる |
| `zellij --version` | Optional | `zellij` がある |
| `ghq --version` | Optional | `ghq` がある |
| `navi --version` | Optional | `navi` と cheatsheet がある |
| `claude --version` | Optional | Claude Code CLI がある |
| `claude plugin list` | Optional | `claude-plugins-official` の per-language LSP plugin が揃っている（コード解析は Serena MCP から native LSP に移行済み） |
| `clasp --version` | Optional | clasp (Google Apps Script CLI) がある |

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

## 設計思想

「MCP を足すか CLI を足すか何もしないか」「既存の実体と source のどちらを正とするか」「credential をどこに置くか」を、後から迷わないようにマトリクスとルールで固定している。個別の判断は積み重ねると必ず矛盾するので、方針を先に凍結して例外を例外として扱うほうが長期的に安い。

### ツール採用基準（MCP / CLI / 削除）

新ツールの追加・置換は以下のマトリクスで方式を決める。迷ったら削除が既定。

| 状況 | 採用方式 | 例 |
|---|---|---|
| 公式 CLI + 公式 skill が揃っている | **CLI + skill**（`scripts/post-setup.sh` で install） | `playwright-cli` + `playwright-cli install --skills`、`ntn` + `makenotion/skills` |
| 公式 CLI なし、公式 remote MCP のみ（OAuth で認証） | **remote HTTP MCP**（`dot_mcp.json` に URL のみ） | Slack、Exa、（過去の）Notion remote |
| Local stdio MCP に credential を渡す必要がある | **`mcp-with-keychain-secret` wrapper 経由**で Keychain から注入 | （現状デフォルトの consumer なし、framework として残置） |
| agent context との tight integration が本質（CoT scaffolding など） | **MCP**（CLI 化すると価値が消える） | sequential-thinking |
| LSP ベースの symbol 解析（cross-file rename / find references / diagnostics） | **Claude Code の native LSP tool + 公式 per-language plugin**（`claude-plugins-official`） | `pyright-lsp`、`typescript-lsp`、`gopls-lsp` ほか |
| Claude Code の native tool（`Read` / `Write` / `Edit` / `Grep` / `Glob`）で代替できる | **削除**（追加せず、既存も外す） | filesystem MCP |
| text diff フレンドリーな代替がある | **代替に移行**（バイナリ依存の MCP は外す） | drawio MCP → Mermaid `.md` 直埋め + `mermaid-cli` |
| 公式 CLI が既存 process への attach を持っている（ライブブラウザ等） | **CLI の attach 機能**（MCP が throwaway プロセスを立ち上げるなら避ける） | `playwright-cli attach --cdp=chrome`（`pwattach` helper）で実 Chrome 操作 |

判断の根拠:

- **CLI + skill が remote MCP に勝る場面**: token 効率（CLI 出力は pipe / file にリダイレクトできるが、MCP tool schema は毎ターン context を消費する）、scripted 用途（cron / CI / agent を起動していない場面でも呼べる）、長時間セッション（state をディスクに持てる）。
- **remote MCP が CLI に勝る場面**: 公式 CLI が存在しない、あるいは用途が違う（Slack の `slack-cli` はアプリ開発向けで IT ops 用途に合わない）。OAuth token を agent 側の credential store に寄せられる。subprocess を立てない。
- **MCP を残す条件**: CLI 化すると `mcp__*__*` の tool 単位 schema 配信が失われ、agent の function calling 精度が落ちる種類の integration（symbol 解析、ライブ DOM 観測、CoT scaffolding）。
- **削除する条件**: 機能が Claude Code の native tool に吸収されている、または text-based で diff フレンドリーな代替がある。

### 整合性のルール

同じ情報が設定 / スクリプト / テスト / ドキュメントに散るので、片側だけ更新すると必ず矛盾する。以下を前提に編集する。

- `home/` 以下（dotfiles source）と `~/` 以下（実体）を両方更新する。片方だけ変えると次回の `chezmoi apply` で巻き戻る。source が正。
- chezmoi の命名規則を守る: `dot_`、`executable_`、`.tmpl`、`private_` 等。
- credential / token を含むファイル（`hosts.yml`、`auth.json`、`oauth_creds.json`、`.netrc`）は dotfiles に入れない。Keychain に置く。
- MCP の追加・削除は全部更新する: `dot_mcp.json`、`ai-repair.sh`、`ai-audit.sh`、`ai-secrets.sh`（credential が要る場合）、`README.md`、`CLAUDE.md`、`tests/`、routing table（`home/dot_claude/CLAUDE.md`）、関連する `home/dot_claude/commands/*.md`。
- MCP を廃止するときは `ai-repair.sh` で能動的に削除し（`ai_config_json_remove_mcp`）、`ai-audit.sh` にも legacy warning を追加する。これをやらないと既存マシンが収束しない。
- CLI 系ツール（npm global / brew など）を追加するときは、`post-setup.sh`、`doctor.sh`、`zsh/` の該当モジュール、`navi/cheats/dotfiles/` の cheat、該当する Claude command、README、`tests/` を同時に更新する。

詳細は [CLAUDE.md](CLAUDE.md)。

### セキュリティモデル

- **credential は Keychain にだけ置く**: stdio MCP に credential が必要な場合は `mcp-with-keychain-secret` wrapper 経由で注入し、設定ファイルには Keychain 参照だけが載る
- **AI に見せるアカウント / プロファイルは最小権限**: Playwright CLI の `pwattach` は **AI 専用 Chrome プロファイル強制**（`PLAYWRIGHT_AI_CHROME_READY=1` が無いと起動を拒否）。Notion / Slack / Google Workspace も管理者アカウントは AI セッションに使わない
- **OAuth token 管理は agent に寄せる**: Slack / Notion remote は Claude Code の OAuth フローに載せ、ローカルに stdio プロセスも token も持たない
- **git identity をハードコードしない**: `~/.config/git/hooks/pre-commit` が global config と author / committer を照合して commit を止める。`GIT_AUTHOR_*` 上書きや repo local config も検査対象
- **企業 CA 証明書の扱い**: `VERIFY_X509_STRICT` 回避は `sitecustomize.py` による最小限の patch で、原本 CA store は書き換えない。ローテーション時は `sitecustomize.py` を削除するだけで戻る

---

## MCP の基本セット（2026）

MCP baseline を `home/dot_claude/dot_mcp.json`（HTTP MCP）に反映しています。stdio MCP は `scripts/post-setup.sh` が `~/.claude.json` に直接 upsert するので、`dot_mcp.json` には載りません。

**HTTP MCP**（`dot_mcp.json`）

- `exa`
- `slack`（remote HTTP + OAuth、`https://mcp.slack.com/mcp`）
- `vision`（Apple Vision framework 経由の画像 OCR、`ja` / `en-US` / `zh-Hans` 等に対応、`npx -y @tuannvm/vision-mcp-server`。`mcp__vision__ocr_extract_text` で呼び出し。macOS 13+ / Node.js 18+ が前提。MCP connect に失敗したら `npx -y @tuannvm/vision-mcp-server --help` で直接確認。旧 `owlocr` MCP は upstream repo retirement に伴い 2026-04 に置換。）

**stdio MCP**（`post-setup.sh` が `~/.claude.json` に登録）

- `sequential-thinking`（`@modelcontextprotocol/server-sequential-thinking`）

**Claude Code plugin**（`claude plugin install ...@claude-plugins-official`、per-user scope）

- `clangd-lsp` / `csharp-lsp` / `gopls-lsp` / `jdtls-lsp` / `kotlin-lsp` / `lua-lsp` / `php-lsp` / `pyright-lsp` / `ruby-lsp` / `rust-analyzer-lsp` / `swift-lsp` / `typescript-lsp`（Anthropic 公式 marketplace の per-language LSP plugin 群。Claude Code 2.0.74 で入った native LSP tool 上に乗り、go-to-definition / find-references / rename / diagnostics を担う。2026-04-24 に `serena` MCP を retire してここへ移行済み）

Notion は MCP ではなく公式 CLI (`ntn`) + skill の組み合わせを採用しています（下の「Notion CLI (ntn)」節参照）。token 効率と scripted 用途の両立を優先しました。

ブラウザ自動化は `@playwright/cli` + skill 方式に寄せているので、`@playwright/mcp` は含めていません（下の「Playwright CLI」節参照）。`chrome-devtools` MCP も 2026-04 に外しました：自分の Chrome を AI に触らせたいケースで MCP が毎回 throwaway Chromium を spawn してしまい、`@playwright/cli` v0.1.8 の `attach --cdp=chrome`（`pwattach` helper）で実 Chrome に接続する運用に一本化したほうが素直なためです。ファイル操作は Claude Code の native `Read` / `Write` / `Edit` / `Grep` / `Glob` で代替できるため、`filesystem` MCP も外しました。図は Mermaid（`.md` 直埋め）か `mermaid-cli` の `mmdc` で text diff フレンドリーに扱えるため、`@drawio/mcp` も外しています。

検索系は `Exa MCP`（`https://mcp.exa.ai/mcp`、API key 不要）に一本化しています。以前入れていた `brave-search`（`@modelcontextprotocol/server-brave-search`、Keychain 経由 API key）は Exa で十分カバーできたため 2026-04 に retire しました。`make ai-repair` が legacy 削除対象に入れているので、旧マシンでも自動で剥がれます。

同じ baseline は `make ai-repair` 実行時に Claude Code の `~/.claude.json` に再生成されます。`make ai-audit` は MCP 登録が壊れている場合に warning を出します。旧 dotfiles の `playwright` / `filesystem` / `drawio` / `notion` / `github` / `owlocr` / `chrome-devtools` / `brave-search` / `serena` MCP 登録が残っている場合も `make ai-repair` で自動的に削除されます。

```bash
make ai-audit
make ai-repair
```

## Notion CLI (`ntn`)

Notion 公式の CLI + skill 方式を採用しています。Playwright CLI と同じ「CLI + skill の方が token 効率が良く、scripted 用途にも使える」というパターンです。

### なぜ MCP ではなく CLI か

- **公式 CLI が存在する**（`https://ntn.dev`、Notion 配布）。Notion 公式 MCP が hosted で Markdown 変換を行うのと同じ品質を、CLI の `ntn block list --md` で出せる
- **token 効率**：CLI 出力は pipe できるので agent context を圧迫しない
- **scripted 用途**：shell pipeline / cron / CI から触れる。MCP だと Claude Code を起動していないと使えない
- **公式 skill** が `~/.claude/skills/notion-cli/` に配布されるので、agent は自動で使い方を理解する

### インストール

`make install` が走ると `scripts/post-setup.sh` が idempotent に以下を実行します。

```bash
curl -fsSL https://ntn.dev | bash                                  # ntn CLI
npx -y skills add https://github.com/makenotion/skills -a claude-code --skill notion-cli
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

情シス業務の自動化（SaaS 管理画面の巡回、チケットの一括処理など）向けに、`@playwright/cli` を CLI + Skill 方式で導入しています。Claude Code から長時間のブラウザセッションを回すのが目的です。

### MCP ではなく CLI を選んでいる理由

- **トークン効率が高い**：snapshot をディスクに書き出すので、agent の context を食わない
- **長時間セッションに強い**：`--persistent` で Cookie / localStorage を保持し、ログインを使い回せる
- **Claude Code が自動で理解する**：`playwright-cli install --skills` が `~/.claude/skills/playwright/` を配置し、skill として認識される

### インストール

`make install` が走ると `scripts/post-setup.sh` が自動で以下を流します（idempotent）。

```bash
npm install -g @playwright/cli@latest
playwright-cli install-browser        # Chromium
playwright-cli install --skills       # Claude Code skill
```

前提は Node.js / npm（`brew "node"` で入る）。

### zsh ヘルパー

`home/dot_config/zsh/playwright.zsh` で 8 関数を提供しています。

| コマンド | 用途 |
|---|---|
| `pwsession <name>` | セッション名を `PLAYWRIGHT_CLI_SESSION` に export |
| `pwattach` | 起動中の実 Chrome に CDP attach し、`PLAYWRIGHT_CLI_SESSION=chrome` を export |
| `pwdetach` | 実 Chrome との attach を切り `PLAYWRIGHT_CLI_SESSION` を unset（Chrome 本体は殺さない） |
| `pwlogin <name> <url>` | `--headed --persistent` で起動し、手動ログイン用に可視ブラウザを開く |
| `pwlist` | `playwright-cli list`：永続セッション一覧 |
| `pwshow` | `playwright-cli show`：ダッシュボードを起動して実行中セッションを監視 |
| `pwkill <name>` | 指定セッションの永続データを削除 |
| `pwkillall` | 全 playwright-cli プロセスを強制終了 |

プロジェクト単位で `.envrc` に `export PLAYWRIGHT_CLI_SESSION=<name>` を置けば、`cd` だけで切り替わります。テンプレは `docs/examples/envrc.playwright.example` にあります。

### 自分のログイン済み Chrome を AI に触らせる（`pwattach`）

`@playwright/cli` v0.1.8+ の `attach --cdp=chrome` を使うと、サンドボックス Chromium を起動せず、**いま動いている自分の Chrome に CDP 接続**できます。ログイン状態・拡張機能・開いているタブをそのまま AI が操作するモードです。

> **⚠️ ポリシー：`pwattach` は必ず AI 専用の Chrome プロファイルで使う**
>
> 普段使いプロファイルに attach すると、Gmail / 銀行 / 個人 / 業務 admin 等 **全ログインセッション**が agent の操作対象になります。prompt injection や CDP 経由の Cookie 窃取で漏洩する blast radius が実生活まで及ぶため、dotfiles 側ではこれを**ソフトに強制**しています：
>
> - `pwattach` は `PLAYWRIGHT_AI_CHROME_READY=1` が export されていないと **拒否して停止**（`home/dot_config/zsh/playwright.zsh`）
> - セットアップ完了済みというユーザー自身の宣言としてこの env var を扱う
>
> `pwlogin`（別 persistent profile）はこの強制の対象外。`pwattach` 固有のリスクが `pwlogin` より高いための差です。詳細は下の「pwattach のセキュリティ」参照。

#### 初回セットアップ（マシン単位で 1 回）

1. **AI 専用 Chrome プロファイルを作る**：Chrome 右上のプロフィール アイコン → "他のプロフィールを追加" → 名前は `AI` など
2. **その AI 用プロファイルでだけ** `chrome://inspect/#remote-debugging` を開いて **"Allow remote debugging for this browser instance"** を ON（Chrome 144+ 必須）。**普段使いプロファイルでは絶対にこの toggle を ON にしない**（Chrome 136+ が `--remote-debugging-port` をプロファイルに対して無視する設計の意図が、これで無効化される）
3. AI に触らせたい SaaS にはこの AI 用プロファイルで **閲覧権限 / 読み取り専用 / 非特権アカウント** でログイン（普段使いアカウントは持ち込まない）
4. `~/.zshenv` に `export PLAYWRIGHT_AI_CHROME_READY=1` を追加 → 新しいシェルを開く

`make sync` / `make install` 実行後の onboarding メッセージ（`scripts/post-setup.sh`）にもこの 4 ステップを表示します。

#### 日常の使い方

1. **AI 用プロファイルの Chrome ウィンドウを手前にしてから**、シェルで `pwattach` → `PLAYWRIGHT_CLI_SESSION=chrome` が export される
2. そのまま Claude Code を起動して作業を依頼。routing は `PLAYWRIGHT_CLI_SESSION=chrome` を見て「実 Chrome を操作する」モードで動く
3. 終わったら `pwdetach`（CDP セッションを閉じる）。機微な作業後は、AI 用プロファイルを閉じるか `chrome://inspect` の toggle を一時的に OFF に戻すのを推奨

#### AI への指示例

- 環境変数方式：`pwattach` してから Claude Code を起動。routing の時点で実 Chrome が選ばれる
- 明示方式：「自分の Chrome でログイン状態のまま見て」「今開いてるタブで作業して」と伝えると、agent は `pwattach` 前提のフローに切り替える。未 attach（`PLAYWRIGHT_CLI_SESSION` 未設定）なら、セットアップ手順を案内してから止まる

#### `pwlogin` との使い分け

| 観点 | `pwattach`（実 Chrome） | `pwlogin`（persistent profile） |
|---|---|---|
| プロファイル | **AI 専用プロファイル必須**（強制） | playwright 管理の別プロファイル |
| Cookie / 拡張 / 履歴 | AI 用プロファイルの状態 | playwright が名前付きで管理 |
| ログイン | ユーザーが AI 用 Chrome で普通にログイン | 初回に可視ブラウザで手動ログイン（2FA 含む） |
| 残り方 | AI 用 Chrome を閉じるまで残る | `pwkill <name>` するまでディスクに残る |
| 向く用途 | 「今見てる画面のこれ、AI にやらせたい」 | SaaS 単位で isolation した長期運用 |

### `pwattach` のセキュリティ（実 Chrome アタッチ特有のリスク）

`pwlogin` は `--persistent` のディスク暗号化が焦点だが、`pwattach` は **live session を丸ごと agent に渡す**性質なので、リスクの種類がまったく違う。上の「必ず AI 専用プロファイル」の運用は、下の 4 リスクのうち最も深刻な 1 と 3 を同時に抑えるために存在する。

| リスク | 深刻度 | 内容 | 対策 |
|---|---|---|---|
| **1. Prompt injection → 資格情報窃取** | 高 | attach 中の Chrome に agent はフル権限でアクセスできる。ログイン済みの全セッションに touch 可能。agent が読むコンテキスト（Web / Notion / メール / Slack）に隠し指示があれば `playwright-cli` 経由で Cookie / localStorage を外部に流せる。CDP 経由のアクセスには Same-Origin Policy が効かない | AI 用プロファイルに機微アカウントを入れない。外部コンテキストを信頼しきらない。機微タスクを `pwattach` 中に並行させない |
| **2. toggle の永続化** | 中 | `chrome://inspect/#remote-debugging` の toggle はプロファイル属性として保持され、`pwdetach` しても OFF にならない。localhost に接続できる任意のプロセスが以後も attach できる。Lumma Stealer / RedLine 系情報窃取マルウェアは localhost CDP を探すのが既知パターン | AI 用プロファイルでだけ toggle ON（普段使いは OFF のまま）。常用しないマシンでは使い終わったら toggle 自体を OFF に戻す。`pwdetach` は toggle を OFF にしない |
| **3. scope 分離が効かない** | 中 | `pwlogin <name>` は SaaS 単位でプロファイルを分けられるが、`pwattach` はプロファイル丸ごと渡す。同じプロファイル内の全タブに agent が飛べる | **AI 専用プロファイル必須**（dotfiles 側で強制）。そのプロファイルには非特権・読み取り系アカウントだけを入れる |
| **4. 拡張機能による副作用** | 低 | attach 中の Chrome の拡張機能（パスワードマネージャ / Autofill 等）は agent の操作にも反映される。意図しない送信欄にクレデンシャルが埋まることがある | AI 用プロファイルは最小構成。パスワードマネージャ系を入れない |

### セーフガード（pwattach / pwlogin 共通）

- **admin / root 級アカウントを AI 用プロファイルに入れない**。read-only / 閲覧権限アカウントで運用する
- 機微データ（PII / 財務 / 健康 / 規制対象）を表示したタブは置かない
- `pwshow` のダッシュボードを可視で回して agent の操作を監視する
- 作業終了時は `pwdetach` + AI 用 Chrome を閉じる。長期放置マシンでは `chrome://inspect` の toggle も OFF に戻す
- agent が外部コンテキスト（Slack / Notion / メール / GitHub Issue）を読み込んだ直後に `pwattach` 下でブラウザ操作を依頼しない（prompt injection の窓口）
- `pwlogin` は SaaS 単位で名前を分けて isolation（`-s=freshservice`、`-s=intune-admin` 等）、不要になったら `pwkill <name>`
- IdP 側で session lifetime を絞り、EDR / XProtect を常時有効にする

`--persistent` で保存されるプロファイル（Cookie / localStorage / IndexedDB）は macOS の Keychain Safe Storage で暗号化されるが、**ユーザー権限で動くマルウェアからは読める**（Lumma Stealer / RedLine 等の主要標的）。FileVault は起動中マルウェアに対しては無力（盗難時のオフライン対策のみ）。設計原則は「漏洩を防ぐ」ではなく「**blast radius を最小化する**」。

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

コマンドのヒントは次で表示できます。

```bash
dothelp
make tips
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

## Brewfile

Homebrew 管理は `home/dot_Brewfile`（実体: `~/.Brewfile`）1 本です。`make sync` が `brew bundle` + `cleanup` をまとめて実行し、宣言していない package は自動で外します。新しいパッケージを入れたいときは Brewfile を直接編集してから `make sync` してください。

保存済み Brewfile と Homebrew の実体がズレているか見たいときは次で確認します。

```bash
make doctor
./scripts/brew-bundle.sh preview
```

---

## マシン固有のセットアップガイド

- [gcloud と企業プロキシ（Python 3.13 問題）](docs/setup-guides/gcloud-python-ssl.md) — Netskope / Zscaler 経由で `VERIFY_X509_STRICT` に弾かれる場合の sitecustomize.py workaround
- [Ghostty 設定](docs/setup-guides/ghostty.md) — `~/.config/ghostty/` の分割構成、GUI 変更の取り込み方、`local.ghostty`

---

## Claude Code / MCP

### 管理方針

Claude Code は `settings.json` を自身で頻繁に書き換えるため、dotfiles が全体を所有すると必ず drift する。そこで **baseline キーだけ** を `make ai-repair` が upsert し、残りはローカル管理にしている。

| 項目 | 管理 |
|---|---|
| `~/.claude/settings.json` の baseline キー（`autoUpdatesChannel` / `env.ENABLE_TOOL_SEARCH` / `hooks`） | dotfiles（ai-repair が upsert） |
| `~/.claude/settings.json` のそれ以外（`permissions` / `model` / `effortLevel` / `statusLine`） | ローカル |
| `~/.claude/settings.local.json` | ローカル（マシン固有 override） |
| `~/.claude/CLAUDE.md` / `statusline.sh` / `auto-save.sh` / `lsp-hint.sh` / `commands/` / `.mcp.json` | dotfiles |
| `~/.claude/skills/frontend-design/` | dotfiles（plugin を vendor） |
| `~/.claude/skills/*`（それ以外） | `post-setup.sh` が外部 CLI 経由で配置 |
| `~/.claude/history.jsonl` / `projects/` / `sessions/` / `cache/` / `plugins/` | 管理しない |
| `~/.config/gh/config.yml`（HTTPS、`co = pr checkout` alias） | dotfiles |
| `~/.config/gh/hosts.yml`（token） | 管理しない |

### Claude Code の baseline

`make ai-repair` が保証するキー:

- `autoUpdatesChannel: "latest"`
- `env.ENABLE_TOOL_SEARCH: "auto:5"`
- `hooks.PreToolUse` Grep → `lsp-hint.sh`（native LSP tool 推奨を stderr で提示、block はしない）
- `hooks.Stop` → `auto-save.sh`（コンテキスト使用率が高ければメモリ保存）
- `hooks.Notification` → macOS 通知（osascript）

`make ai-audit` は baseline キーの存在だけを検査する。

### コード解析: Claude Code native LSP plugin

LSP ベースの symbol 解析は Anthropic 公式 marketplace (`claude-plugins-official`) の per-language plugin に一本化している。`claude plugin list` で `clangd-lsp` / `csharp-lsp` / `gopls-lsp` / `jdtls-lsp` / `kotlin-lsp` / `lua-lsp` / `php-lsp` / `pyright-lsp` / `ruby-lsp` / `rust-analyzer-lsp` / `swift-lsp` / `typescript-lsp` が並んでいれば OK。Claude Code の native LSP tool が go-to-definition / find-references / rename / hover / diagnostics をまとめて担う。

以前の `serena` MCP（`~/.local/bin/serena-mcp` wrapper + `~/.serena/serena_config.yml`）は 2026-04-24 に retire。`make ai-repair` の legacy 掃除で `~/.claude.json` から剥がれる。`~/.serena/` や `~/.local/bin/serena-mcp` が残っていたら `make ai-audit` が warning を出すので手で rm して構わない。

### MCP credential は Keychain 一択

`ai-secrets`（または `make ai-secrets`）が hidden 入力で受け取った credential を macOS Keychain（service `dotfiles.ai.mcp`）に保存し、`ai-repair.sh` を自動で流す。設定ファイルには平文 token を書かず、Keychain 読み出し wrapper 経由の参照だけを書く。現状は `brave-search` を retire した関係でデフォルト consumer が無く、framework のみ future stdio MCP 用に温存してある。

- Enter で現状維持、`-` で削除
- 旧 `~/.config/dotfiles/ai-secrets.env` があれば保存後に削除
- 実 Chrome を agent に触らせる用途では MCP ではなく `@playwright/cli` の `attach --cdp=chrome`（Playwright CLI 節の `pwattach` 参照）

### `make ai-audit` の確認項目

- `~/.claude.json` の baseline（model / hooks）
- exa / slack / vision の登録有無（legacy MCP: `playwright` / `filesystem` / `drawio` / `notion` / `github` / `owlocr` / `chrome-devtools` / `brave-search` / `serena` が残っていれば warning）
- Serena retire 後の leftover（`~/.serena` / `~/.local/bin/serena-mcp`）
- 古い bridge 設定や危険な approval 設定、バックアップファイル（`.bak`）の残存

よくある詰まりどころ:

- 旧 dotfiles から移行して legacy MCP が残る → `make ai-repair` が自動削除、`ai-audit` が warning で知らせる
- `ai-secrets` が古い wrapper を掴んで失敗 → `chezmoi apply ~/.local/bin/ai-secrets`

### Slash commands（`~/.claude/commands/`）

`home/dot_claude/commands/` に 18 本のワークフローガイドを同梱。`/<name>` で起動する。各ファイルは 50–130 行のプロセス定義で、対応する skill（ある場合）を呼び出す段取りが書いてある。

| コマンド | 用途 |
|---|---|
| `/debug` | 体系的なデバッグ（reproduce → isolate → fix → verify） |
| `/refactor` | 振る舞いを変えずに構造を整える |
| `/test` | プロジェクトのテスト枠組みに沿ってテストを追加 |
| `/security-review` | Python / JS / TS / Go の security best-practices レビュー |
| `/api-design` | REST / GraphQL API 設計（OpenAPI spec 生成） |
| `/ci` | CI/CD パイプライン作成・改善（デフォルト GitHub Actions） |
| `/docker` | Dockerfile / docker-compose の作成・最適化・デバッグ |
| `/perf` | パフォーマンス監査（Lighthouse / playwright-cli trace） |
| `/diagram` | Mermaid / PlantUML で図を生成（text diff フレンドリー優先） |
| `/doc` | `.docx` の読み書き（python-docx） |
| `/pdf` | PDF の読み書き（reportlab / pdfplumber / pypdf） |
| `/spreadsheet` | `.xlsx` / `.csv` / `.tsv` の作成・編集・分析 |
| `/presentation` | `.pptx` の作成・編集（python-pptx） |
| `/notebook` | Jupyter notebook の作成 |
| `/screenshot` | デスクトップ / ウィンドウ / 領域キャプチャ |
| `/playwright` | ブラウザ自動化（playwright-cli） |
| `/research` | Exa MCP ベースの技術リサーチ |
| `/ui-ux` | UI/UX デザイン（React / Next.js / Vue / SwiftUI / Flutter 等 10 スタック対応） |

### CLI / skill / plugin の配布方針

- **Claude Code CLI** は native install を正とし `post-setup.sh` が `latest` チャンネルで導入（Homebrew cask では管理しない、background 自動更新あり）
- **clasp** は `post-setup.sh` が `npm install -g @google/clasp`。初回 `clasp login` が必要
- **Sequential Thinking MCP** / **gws skills** / **find-skills**（`vercel-labs/skills`）は `post-setup.sh` が Claude Code に配置
- **同梱 skill**（`home/dot_claude/skills/`）: `screenshot` / `doc` / `pdf` / `spreadsheet` / `jupyter-notebook` / `security-best-practices` / `ui-ux-pro-max`
- **frontend-design skill** は `anthropics/claude-plugins-official` の plugin（Apache-2.0）を `home/dot_claude/skills/frontend-design/` に vendor。upstream 更新は `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/frontend-design/skills/frontend-design/SKILL.md` からコピーし直す
- **Superpowers** / **Context7** plugin は Claude Code セッション内で `/plugin install` 手動（dotfiles 管理外）
- **brew-autoupdate** は方針で無効化、`post-setup.sh` が既存 launch agent を削除する

### aider（補助）

`aider` は Brewfile 同梱、端末から直接コードを編集させたい時の補助用途。

セットアップ系スクリプトは Bash 前提で書いているので呼び出しは `bash` 明示、日常利用は `zsh` のままで問題ない。

---

## ディレクトリ構成

```text
dotfiles/
├── CLAUDE.md                       # このリポジトリ固有の整合性ルール
├── Makefile                        # install / sync / doctor / ai-* / test / uninstall
├── .chezmoiroot                    # "home" を chezmoi source root として指す
├── home/                           # chezmoi source → $HOME
│   ├── dot_Brewfile / dot_zshrc / dot_gitconfig.tmpl / dot_python-version
│   ├── dot_claude/
│   │   ├── CLAUDE.md               # → ~/.claude/CLAUDE.md (ツール採用・native LSP plugin 運用)
│   │   ├── executable_{statusline,auto-save,lsp-hint}.sh  # hooks 配下
│   │   ├── dot_mcp.json            # → ~/.claude/.mcp.json (HTTP MCP baseline)
│   │   ├── commands/               # → ~/.claude/commands/*.md (18 slash commands, 下表参照)
│   │   └── skills/                 # frontend-design vendor + 同梱 skill 7 個（screenshot / doc / pdf / spreadsheet / jupyter-notebook / security-best-practices / ui-ux-pro-max）
│   ├── dot_local/
│   │   ├── bin/                    # ai-secrets / mcp-with-keychain-secret
│   │   ├── lib/python-ssl-compat/  # Python 3.13 VERIFY_X509_STRICT 無効化（docs/setup-guides/gcloud-python-ssl.md）
│   │   └── share/navi/cheats/dotfiles/  # ai / git / shell / files / terminal cheats
│   └── dot_config/
│       ├── atuin/ gh/ ghostty/ zellij/ starship.toml
│       ├── git/hooks/pre-commit    # global git privacy guard
│       └── zsh/                    # env / aliases / tools / completion / playwright
├── scripts/
│   ├── bootstrap.sh                # SSL compat + brew + chezmoi + apply
│   ├── post-setup.sh               # CLI / skill / stdio MCP 登録、brew-autoupdate 無効化
│   ├── doctor.sh / status.sh / preview.sh / uninstall.sh / dotfiles-help.sh
│   ├── ai-audit.sh / ai-repair.sh / ai-secrets.sh / brew-bundle.sh
│   └── lib/{ai-config,brew-autoupdate}.sh
├── tests/                          # シェルベースの回帰テスト (lib/testlib.sh + 16 本)
└── docs/
    ├── notes/current-state.md      # 運用メモ
    ├── examples/                   # chezmoidata.yaml / envrc.playwright.example
    └── setup-guides/               # gcloud-python-ssl.md / ghostty.md
```

---

## トラブルシューティング

### `chezmoi apply` が source を見つけられない

```
chezmoi: no config file, and no source directory
```

`bootstrap.sh` は `~/.local/share/chezmoi` をこの repo への symlink にします。手動で clone した場合は symlink を自分で作るか、`chezmoi init --source=<path>` を実行してください。

```bash
ln -s ~/dotfiles ~/.local/share/chezmoi
```

### `make install` 後に `playwright-cli` / `ntn` が見つからない

`post-setup.sh` は npm global へインストールしますが、新しいシェルを開くまで `PATH` に反映されません。新しいターミナルを開き直すか、次を実行します。

```bash
hash -r
exec zsh
```

### `pwattach` が "PLAYWRIGHT_AI_CHROME_READY=1 が必要" で止まる

これは意図的な安全策です。`pwattach` は AI 専用 Chrome プロファイルの運用を強制しており、ユーザーが明示的に環境変数を設定することで「セットアップ完了済み」を宣言する設計です。初回セットアップ手順は [自分のログイン済み Chrome を AI に触らせる](#自分のログイン済み-chrome-を-ai-に触らせるpwattach) を参照してください。

### `gcloud` が SSL エラーで動かない（`CERTIFICATE_VERIFY_FAILED`）

企業 CASB/プロキシの MITM 証明書が Python 3.13 の `VERIFY_X509_STRICT` で拒否されています。`make install` で `sitecustomize.py` が配置されているはずなので、次で確認します。

```bash
make doctor                     # "VERIFY_X509_STRICT bypass: active" を確認
ls ~/.local/lib/python-ssl-compat/sitecustomize.py
echo $PYTHONPATH                # python-ssl-compat が含まれていること
```

詳細と対策は [gcloud と企業プロキシ（Python 3.13 問題）](#gcloud-と企業プロキシpython-313-問題) を参照。

### `make ai-audit` が legacy MCP を警告する

旧 dotfiles から移行した場合、古い MCP 登録（`playwright` / `filesystem` / `drawio` / `notion` / `github` / `owlocr` / `chrome-devtools` / `brave-search`）が残っていることがあります。`make ai-repair` が自動で削除します。

```bash
make ai-repair
make ai-audit     # clean になるはず
```

### Claude Code で MCP が繋がらない

`make ai-audit` で `missing` / `wrong-url` が出る場合は `make ai-repair` で再登録できます。それでも直らない場合は Claude Code を再起動してください。

```bash
make ai-audit
make ai-repair
# Claude Code を終了して再起動
```

### Brewfile に入れてない package が `brew leaves` に出る

`make sync` が `brew bundle cleanup --force` で Brewfile 外の package を削除します。意図的に残したいものは Brewfile に追記してください。

---

## fork して使うとき

fork して自分のマシンに合わせる想定。apply 前に以下の決定を自分で下す。

1. **git identity**: `cp docs/examples/chezmoidata.yaml .chezmoidata.yaml` して `gitIdentity.name` / `gitIdentity.email` を差し替える。pre-commit guard が `git config --global` と照合するので、global 設定もこの値と一致させる。
2. **Brewfile**: `home/dot_Brewfile` は IT 業務 + AI agent 運用前提で組んである。そのまま使うと IME（`google-japanese-ime`）、password manager（`bitwarden`）、clipboard manager（`maccy`）、2FA（`ente-auth`）、browser（`google-chrome`）、文書変換（`basictex` / `pandoc` / `mermaid-cli`）が全部入る。不要なものは cask ごと削除する。
3. **AI agent の取捨**: Claude Code を使わないなら、該当の brew cask、`home/dot_claude/`、`scripts/ai-repair.sh` / `ai-audit.sh` / `post-setup.sh` の対応ブロックを落とす。`make test` が失敗しなければ consistent。
4. **MCP セット**: 使わない MCP は `dot_mcp.json` から消し、`ai-repair.sh` の baseline と `ai-audit.sh` の legacy 削除対象を対応させる。新規追加は [ツール採用基準](#ツール採用基準mcp--cli--削除) を先に通す。
5. **terminal / multiplexer / shell**: `home/dot_config/ghostty/`、`home/dot_config/zellij/`、`home/dot_config/zsh/` は嗜好が強い領域。fork 先で丸ごと書き換える前提で読むこと。
6. **routing table**: `home/dot_claude/CLAUDE.md` は agent が毎回読む指示書。この repo の内容をそのまま採用する技術的理由はない。自分の運用に合わせて書き換える。
7. **CI**: public 化時点で `.github/workflows/` は外した。`make test` が自前で全テスト走らせるので、fork 先でそれを GHA から叩く 1 行の workflow を追加すれば済む。

apply は必ず dry-run から。

```bash
make preview          # chezmoi diff + brew bundle check + cleanup preview
chezmoi apply -n -v   # chezmoi 単体で dry-run
```

---

## 貢献 / フィードバック

個人の opinionated な設定なので feature request には応えない。scope 外。以下は歓迎する。

- **typo / ドキュメントの事実誤認 / 壊れたリンク**: PR。
- **セキュリティ問題**（credential 漏洩、過剰な permission、sandbox 逸脱、reachable な MITM 等）: Issue。repro 手順つきで。
- **設計判断に対する反論**: [ツール採用基準](#ツール採用基準mcp--cli--削除) の枠組みで書かれた反論は読む。「好み」ベースは読まない。

ライセンスは [MIT](LICENSE)。
