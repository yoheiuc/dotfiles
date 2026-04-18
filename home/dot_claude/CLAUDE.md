# Personal Claude Code Notes

- 新しいプロジェクトを始めるときは、プロジェクトルートに CLAUDE.md がなければ /init で作る
- 回答は簡潔にする
- まずローカルの実態を見る
- 可能ならその場で修正まで進める
- 破壊的な操作は確認なしで進めない
- ファイル内容を丸ごと繰り返さない。変更箇所は diff か該当行だけ示す
- 前置き・要約・確認の繰り返しは省く。結論から入る
- ツール呼び出し結果を全文引用しない。必要な部分だけ抜粋する
- 設定キーやオプション名が正しいか自信がないときは、ユーザーに確認を取らず自分で公式ドキュメントやソースを fetch して裏取りしてから回答する

## MCP ツール選択ルール

テキストで説明するだけで終わらせず、ツールで実行する。

| やりたいこと | 使うツール |
|---|---|
| 知らないこと・最新情報を調べる | `mcp__exa__web_search_exa` / `mcp__exa__web_fetch_exa` または `mcp__brave-search__brave_web_search`。Exa は技術系・構造化検索向き、Brave は汎用 Web 検索向き。「わかりません」の前にまず検索する |
| Notion の情報検索・参照・更新 | `ntn` CLI（Notion 公式）。`ntn api ...` で API 叩き、`ntn files ...` / `ntn workers ...` も。skill は `~/.claude/skills/notion-cli/`。認証は `ntn login`（browser OAuth）または `NOTION_API_TOKEN` env var |
| Slack のメッセージ検索・投稿・チャンネル操作 | `mcp__slack__*`（remote + OAuth）。インシデント対応の履歴調査、チャンネルの要約、通知投稿に使う |
| 図で説明した方が早い構成・フロー | Mermaid を使う。`.md` に ```mermaid ブロックで直接埋める（GitHub / VS Code / Obsidian が自動レンダリング）。PNG / SVG が要るときは `mmdc -i in.mmd -o out.svg`（`mermaid-cli`） |
| ブラウザ操作・自動化・UI 確認 | `playwright-cli`（ターミナルから CLI で起動）。`PLAYWRIGHT_CLI_SESSION` が set されていればそれを使う。skill は `~/.claude/skills/playwright/` |
| GitHub の PR / Issue / コード検索 | `gh` CLI を使う（`gh pr`, `gh issue`, `gh api` 等） |
| パフォーマンス・ネットワーク問題 | `mcp__chrome-devtools__*` で実測する |
| コード構造の理解・リファクタ | Serena（下記） |

## ツール選択の基準（MCP / CLI / 削除）

新しいツールを足すか迷ったら、以下のマトリクスで判断する。dotfiles リポジトリ内の運用チェックリスト（更新すべきファイル一覧など）は `~/dotfiles/CLAUDE.md` 側にある。

| 状況 | 採用方式 |
|---|---|
| 公式 CLI + 公式 skill が揃っている | **CLI + skill**（例：`playwright-cli`、`ntn`） |
| 公式 CLI なし、公式 remote MCP がある（OAuth 認証） | **remote HTTP MCP**（例：Slack、Exa） |
| Local stdio MCP に credential を渡す必要がある | `mcp-with-keychain-secret` wrapper 経由（例：Brave Search） |
| agent context との tight integration が本質 | **MCP**（例：Serena、chrome-devtools、sequential-thinking） |
| Claude Code の native tool（Read / Write / Edit / Grep / Glob）で代替できる | **削除 / 不採用** |
| text diff フレンドリーな代替がある | **代替に移行**（例：drawio MCP → Mermaid） |

優先順位の理由：
- **CLI + skill > MCP**：token 効率（CLI 出力は pipe / file へ流せる、tool schema は毎ターン context を食う）、scripted 用途（cron / CI / Claude Code 起動外でも使える）、長時間セッション（state をディスクに持てる）
- **remote MCP > local stdio MCP**：subprocess を起こさない、OAuth token 管理を agent 側に集約、Keychain 不要
- **MCP > CLI**：CLI 化で `mcp__*__*` の tool 単位 schema 配信が失われると価値が消える tight integration（symbol 解析、ライブ DOM 観測等）

迷ったら dotfiles の commit log（PR #26 = Playwright、#28 = Notion）を見る。同じ議論を繰り返さない。

## Serena MCP

Serena は LSP ベースのコード解析ツール。Grep/テキスト検索より正確な結果が得られる場面では積極的に使う。

### セッション開始時
- `mcp__serena__initial_instructions` を呼んで利用可能なツールを確認する

### Grep より Serena を優先する場面
- シンボルの定義箇所を探す → `mcp__serena__find_symbol`
- シンボルの詳細（型、引数、docstring）を見る → `mcp__serena__get_symbol_detail`
- 呼び出し元・参照箇所を網羅的に探す → `mcp__serena__find_references`
- ファイルの構造（クラス、関数一覧）を把握する → `mcp__serena__get_file_overview`

### 変更時
- クロスファイルのリネーム → `mcp__serena__rename_symbol`（テキスト置換ではなく必ずこれを使う）
- 変更後の LSP エラー確認 → `mcp__serena__get_diagnostics`
