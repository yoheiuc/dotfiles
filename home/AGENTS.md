# Personal Codex Notes

- 新しいプロジェクトを始めるときは、プロジェクトルートに AGENTS.md がなければ作る
- 回答は簡潔にする
- まずローカルの実態を確認する
- 可能なら調査で止めず修正まで進める
- 破壊的な操作や外部影響のある操作は確認を取る
- 会話圧縮の前に、次回も役立つ要点があれば Codex のメモリーへ短く保存してから終える
- ファイル内容を丸ごと繰り返さない。変更箇所は diff か該当行だけ示す
- 前置き・要約・確認の繰り返しは省く。結論から入る
- ツール呼び出し結果を全文引用しない。必要な部分だけ抜粋する

## MCP ツール選択ルール

テキストで説明するだけで終わらせず、ツールで実行する。

| やりたいこと | 使うツール |
|---|---|
| 知らないこと・最新情報を調べる | `exa__web_search_exa` / `exa__web_fetch_exa`。「わかりません」の前にまず検索する |
| 図で説明した方が早い構成・フロー | Mermaid を使う。`.md` に ```mermaid ブロックで直接埋める。PNG / SVG が要るときは `mmdc -i in.mmd -o out.svg`（`mermaid-cli`） |
| ブラウザ操作・自動化・UI 確認 | `playwright-cli`（ターミナルから CLI で起動）。`PLAYWRIGHT_CLI_SESSION` が set されていればそれを使う。skill は `~/.codex/skills/playwright/` |
| GitHub の PR / Issue / コード検索 | `gh` CLI を使う（`gh pr`, `gh issue`, `gh api` 等） |
| パフォーマンス・ネットワーク問題 | `chrome-devtools__*` で実測する |
| コード構造の理解・リファクタ | Serena（下記） |

## Skills

`~/.codex/skills/` にインストール済みの skill がある。該当場面では積極的に使う。

| skill | 場面 |
|---|---|
| `security-best-practices` | コードレビュー・新規コード作成時に `references/` のガイドを参照する |
| `playwright` | `playwright-cli` ラッパー経由でブラウザ自動操作。`PLAYWRIGHT_CLI_SESSION` で永続セッションを指定 |
| `screenshot` | macOS のデスクトップ / ウィンドウキャプチャ |
| `doc` | Word (.docx) ドキュメント生成 |
| `pdf` | PDF の読み取り・解析 |
| `spreadsheet` | Excel (.xlsx) の生成・読み取り |
| `jupyter-notebook` | ノートブックの作成・実行 |
| `ui-ux-pro-max` | UI/UX デザインパターンの検索・参照 |

## Serena MCP

Serena は LSP ベースのコード解析ツール。Grep/テキスト検索より正確な結果が得られる場面では積極的に使う。

### セッション開始時
- `serena__initial_instructions` を呼んで利用可能なツールを確認する

### Grep より Serena を優先する場面
- シンボルの定義箇所を探す → `serena__find_symbol`
- シンボルの詳細（型、引数、docstring）を見る → `serena__get_symbol_detail`
- 呼び出し元・参照箇所を網羅的に探す → `serena__find_references`
- ファイルの構造（クラス、関数一覧）を把握する → `serena__get_file_overview`

### 変更時
- クロスファイルのリネーム → `serena__rename_symbol`（テキスト置換ではなく必ずこれを使う）
- 変更後の LSP エラー確認 → `serena__get_diagnostics`
