# dotfiles — Claude Code Notes

このリポジトリで作業する Claude / 自分が読むためのルール集。会話中の振る舞いルール（簡潔に答える、日本語で返す等）と subagent モデル振り分けは `~/.claude/CLAUDE.md`（L1）側にある。

このファイル（L2）が担当するのは「新ツールを足すか / 既存を直すか / 何も足さないか」の判断と、その判断を一貫させるための整合性ルール。

## このリポについて（30 秒）

macOS 開発環境（chezmoi で `~/` 以下を管理 + Brewfile + Claude Code 設定）。`home/` 以下が single source of truth。

- 状態確認: `make status` → `make ai-audit` → `make doctor`（深さの順）
- 修復: `make ai-repair`（AI 設定 drift） / `make sync`（実体寄せ + post-setup）
- 全テスト: `make test`

詳細・セットアップ手順は `README.md`。

## ツール採用基準

新ツールの追加・置換は以下のマトリクスで方式を決める。迷ったら削除が既定。

| 状況 | 採用方式 | 例 |
|---|---|---|
| 公式 CLI + 公式 skill が揃っている | **CLI + skill**（`scripts/post-setup.sh` で install） | `playwright-cli`、`ntn`、`gws` |
| 公式 CLI なし、公式 remote MCP がある（OAuth 認証） | **remote HTTP MCP**（`dot_mcp.json` に URL のみ） | Slack、Exa |
| Local stdio MCP に credential を渡す必要がある | `mcp-with-keychain-secret` wrapper 経由で Keychain から注入 | （現状 consumer なし、framework として残置） |
| agent context との tight integration が本質 | **MCP**（CLI 化すると価値が消える） | sequential-thinking |
| LSP ベースの symbol 解析 | **Claude Code native LSP tool + 公式 plugin** | `pyright-lsp` ほか（`claude-plugins-official`） |
| Claude Code の native tool（Read / Write / Edit / Grep / Glob）で代替できる | **削除 / 不採用** | filesystem MCP |
| text diff フレンドリーな代替がある | **代替に移行** | drawio MCP → Mermaid |
| 公式 CLI が既存 process への attach を持っている | **CLI の attach 機能**（MCP が throwaway を立てるなら避ける） | `pwattach` で実 Chrome |

優先順位の理由:

- **CLI + skill > MCP**: token 効率（CLI 出力は pipe / file へ流せる、tool schema は毎ターン context を食う）、scripted 用途（cron / CI でも呼べる）、長時間セッション（state をディスクに持てる）
- **remote MCP > local stdio MCP**: subprocess を起こさない、OAuth token 管理を agent 側に集約、Keychain 不要
- **MCP > CLI**: CLI 化で `mcp__*__*` の tool 単位 schema 配信が失われると価値が消える tight integration（symbol 解析、ライブ DOM 観測、CoT scaffolding 等）

### skill / plugin 配布の優先順位

Claude Code に skill / plugin を足したいときは上から順に検討する。

1. **`claude-plugins-official` marketplace の plugin**: `scripts/lib/claude-plugins.sh` の配列に追加 → `make install` で自動配置。SHA pin で再現性あり、upstream rolling update も marketplace 経由で取り込める
2. **upstream の公式 CLI が提供する skill 配布**（gws / playwright / notion 等）: `scripts/post-setup.sh` の `npx skills add ...` で `~/.claude/skills/` に install。dotfiles source には入れない
3. **vendor**（`home/dot_claude/skills/` に SKILL.md 直置き）: 上の 1 / 2 で配布されていない場合のみの最終手段。marketplace に対応 plugin が出たら都度 vendor を退避する（frontend-design = c606583 の前例）

理由: vendor すると upstream の rolling update から取り残されて drift するし、license / 更新責任が dotfiles 側に来る。可能な限り marketplace か公式 distributor に任せる。

## スクリプトの責務境界

ヘルスチェック・修復系の3スクリプトの境界:

| script | 種類 | 守備範囲 | 想定の使われ方 |
|---|---|---|---|
| `scripts/ai-repair.sh` | **write**（drift 修復） | Claude Code 設定 baseline / MCP 登録 / hooks / legacy 削除 | `make ai-repair`、`post-setup.sh` から自動呼び出し |
| `scripts/ai-audit.sh` | **read**（AI 設定 drift 検出） | 上と同じ範囲を予測値と突き合わせて diff 報告 | `make ai-audit`、CI / 通知 |
| `scripts/doctor.sh` | **read**（システム全体の健康診断） | OS tools / Brewfile / git identity / Claude / clasp / gcloud / SSL compat 等 22 セクション | `make doctor`、新環境 setup 後 |

検証ロジックは `scripts/lib/claude-checks.sh` の predicate に集約（`ai-audit` / `doctor` の両方が同じ関数を呼ぶ）。message format だけ各スクリプトが自分の調子で組み立てる。

### `scripts/lib/` の責務一覧

各 lib は単一責務。新しい共通処理を足すときはどれにも合わなければ新 lib を作る（既存 lib を肥大化させない）。

| lib | 責務 | 主な consumer |
|---|---|---|
| `ui.sh` | `section` / `ok` / `warn` / `info` の出力ヘルパー | `doctor` / `ai-audit` / `ai-repair` / `status` / `post-setup` / `ai-secrets` |
| `ai-config.sh` + `ai_config.py` | `~/.claude.json` / `settings.json` の安全な read / upsert / remove。JSON mutation は Python が tempfile + `os.replace` で原子的に行う | `ai-audit` / `ai-repair` |
| `claude-checks.sh` | Claude Code 設定の純粋 predicate（hook 登録 / MCP 登録 / autoupdate channel 等の有無を bool で返す） | `ai-audit` / `doctor` |
| `claude-plugins.sh` | 期待 plugin リスト（`CLAUDE_LSP_PLUGINS` / `CLAUDE_GENERAL_PLUGINS`）と marketplace 名 + 単一 plugin の installed 判定 | `post-setup` (install) / `doctor` (verify) |
| `brew-autoupdate.sh` | Homebrew autoupdate launchd job の path / 状態判定 / dotfiles baseline 一致判定 | `doctor` / `post-setup` |

責務分割の原則:

- **predicate（読み取り）と mutation（書き込み）を混ぜない**: `claude-checks.sh` は read-only。`ai-config.sh` の `*_upsert_*` / `*_remove_*` は write 専用
- **データ（リスト / 設定値）と処理を分ける**: `claude-plugins.sh` は配列定義が主目的。判定関数は 1 つだけ（`claude_plugin_is_installed`）
- **call site の UI 文言は lib に持たせない**: 各 script が自分のトーン（`ok` / `warn` / `attention` / `fail`）で出力する

## 個別判断ログ

マトリクスでは決まらないケース（同じ機能を提供する複数の経路がある等）の判断記録。同じ議論を繰り返さないため、新規エントリは表の下に追記する（古いものを上、新しいものを下）。

| 日付 | 判断 | 理由 | 関連 commit/issue |
|---|---|---|---|
| 2026-04 | `chrome-devtools-mcp` plugin を採用しない | 実 Chrome に attach せず throwaway Chromium を spawn する設計で、`pwattach` 運用と相反 | `2064181` (playwright-cli: adopt attach --cdp=chrome) |
| 2026-04-25 | Exa は HTTP MCP のまま、plugin 化しない | `claude-plugins-official` の `exa` plugin は stdio 版で API key と subprocess が要る → policy「remote MCP > local stdio MCP」と衝突。`web_search_exa` / `web_fetch_exa` の 2 tool で日常用途は足りる | `b21fdcd` (consolidate web search on Exa) |
| 2026-04-25 | `code-review` / `pr-review-toolkit` plugin を採用しない | `/review` `/ultrareview` `/security-review` で同等の用途をカバー済み | `b2ad19e` (install claude-plugins-official) |
| 2026-04-25 | `code-simplifier` plugin を採用しない | 同等の `simplify` skill を vendoring 済み | `b2ad19e` |
| 2026-04-25 | `commit-commands` plugin を採用しない | HEREDOC + Co-Authored-By 等の独自コミット規約と衝突しやすい | `b2ad19e` |
| 2026-04-25 | `superpowers` / `context7` plugin は dotfiles 管理外 | 必要時にセッション内 `/plugin install` で個別投入。dotfiles 必須セットには含めない | README.md に明文 |
| 2026-04-25 | `shfmt` を Brewfile に追加しない | `shellcheck` で実害は止まる。personal repo で style 揺れの実害なし。L2 policy「迷ったら削除」に該当 | （本セッションでの判断、commit なし） |
| 2026-04-25 | `ai-repair.sh` の hooks block は merge せず wholesale 置換のまま | Claude Code は `settings.json` と `settings.local.json` の hooks を append/concat で merge する（override ではない）ので、baseline を全置換しても user-added hook は失われない。user-added は `settings.local.json` 側に置く運用 | https://code.claude.com/docs/en/hooks.md |

## `~/.claude/` 配下の管理モード

同じディレクトリでも管理経路が混在する。新規パスを追加するときは下表のどれかに分類して、編集ルールに従う。分類できない新規パスを足すなら表を更新する。

| パス | 管理モード | 編集ルール |
|---|---|---|
| `~/.claude/CLAUDE.md` / `auto-save.sh` / `lsp-hint.sh` / `statusline.sh` / `commands/` / `.mcp.json` | chezmoi end-to-end | `home/dot_claude/` 側を編集 → `chezmoi apply`（または `make sync`） |
| `~/.claude/skills/{doc,jupyter-notebook,pdf,screenshot,security-best-practices,spreadsheet,ui-ux-pro-max}` | chezmoi end-to-end (vendored) | 同上。marketplace に対応 plugin が現れたら plugin 化を検討して vendor を退避 |
| `~/.claude/settings.json` の baseline 3 key（`autoUpdatesChannel` / `env.ENABLE_TOOL_SEARCH` / `hooks`） | dotfiles baseline | `scripts/ai-repair.sh` の upsert ロジックを編集。実体は Claude Code が rewrite する前提 |
| `~/.claude/settings.json` のそれ以外（`permissions` / `model` / `effortLevel` / `statusLine`） | local 自由 | 触らない（Claude Code が rewrite） |
| `~/.claude/skills/{gws-*,find-skills,playwright-cli,notion-cli}` | post-setup install (skill) | `scripts/post-setup.sh` の install 句を編集。`npx skills add` 経由 |
| `~/.claude/plugins/installed_plugins.json` | post-setup install (plugin) | `scripts/lib/claude-plugins.sh` の配列を編集。`claude plugin install` 経由 |
| `~/.claude/projects/` / `history.jsonl` / `sessions/` / `cache/` | 完全 local | 触らない |
| `~/.claude.json`（MCP 登録） | dotfiles baseline | `scripts/ai-repair.sh` の MCP 登録ブロックを編集 |
| `~/.claude/settings.local.json` | 完全 local | マシン固有 override。dotfiles では触らない |

## 整合性ルール

同じ情報が設定 / スクリプト / テスト / ドキュメントに散る構造なので、片側だけ更新すると必ず矛盾する。

- dotfiles ソース（`home/` 以下）が single source of truth。実体（`~/` 以下）だけ変えると次回の `chezmoi apply` で巻き戻る
- chezmoi の命名規則を守る: `dot_` / `executable_` / `.tmpl` / `private_` 等
- credential / token を含むファイル（`hosts.yml` / `auth.json` / `oauth_creds.json` / `.netrc`）は dotfiles に入れない。Keychain に置く
- 廃止時は `ai-repair.sh` で能動的に削除し、`ai-audit.sh` に legacy 警告を追加する。これをやらないと既存マシンが収束しない

## Commit message 規約

`<topic>: <動詞句>` の prefix style。topic は「変更箇所のスコープ」で、git log の前例を踏襲する。

- 既存 prefix の例: `docs` / `ai` / `ai-audit` / `mcp` / `skills` / `playwright-cli` / `pwattach` / `statusline` / `ghostty` / `tests` / `dotfiles`
- スコープが広い改善は repo 名 (`dotfiles:`) を使う
- 詳細・複数項目はコミット本文に bullet で書く（subject は 1 行で要約）
- 末尾に `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`（HEREDOC で渡す）

## 変更箇所の依存マップ

### MCP サーバーの追加・削除・変更

影響範囲が広い。以下をすべて更新する:

- `home/dot_claude/dot_mcp.json`（HTTP MCP 登録）
- `scripts/ai-repair.sh`（drift 修復 / 廃止 MCP の能動的削除）
- `scripts/ai-audit.sh`（legacy 警告）
- `scripts/ai-secrets.sh`（credential が必要な場合）
- `README.md` の「MCP の基本セット」
- 関連する `home/dot_claude/commands/*.md`
- `tests/` 配下の対応テスト

### CLI 系ツールの追加（npm global / brew 等）

- `scripts/post-setup.sh`（install）
- `scripts/doctor.sh`（存在確認）
- `home/dot_config/zsh/` の対応モジュール
- `home/dot_local/share/navi/cheats/dotfiles/` の cheat
- 関連する `home/dot_claude/commands/*.md`
- `README.md`
- `tests/` 配下の回帰テスト

### Claude Code の skill / plugin

- **公式 CLI で配布される** skill（gws / playwright / notion 等）: `scripts/post-setup.sh` が `~/.claude/skills/` に install。dotfiles source には vendor しない
- **plugin marketplace 経由で配布される** plugin（`claude-plugins-official` の `*-lsp` 群と general 群）:
  - 期待リストは `scripts/lib/claude-plugins.sh` の `CLAUDE_LSP_PLUGINS` / `CLAUDE_GENERAL_PLUGINS` に集約。新規追加・削除はここを編集
  - `scripts/post-setup.sh` が両リストを iterate して `claude plugin install <name>@claude-plugins-official` を冪等実行（per-user scope）
  - `scripts/doctor.sh` が同じリストを使って `~/.claude/plugins/installed_plugins.json` 上の有無を検証
  - dotfiles に SKILL.md を vendor しない。upstream が marketplace で rolling update するため、vendor すると drift する
  - README の該当節も同期して更新
