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
| 知らないこと・最新情報を調べる | `mcp__exa__web_search_exa` / `mcp__exa__web_fetch_exa`。「わかりません」の前にまず検索する |
| 図で説明した方が早い構成・フロー | `mcp__drawio__*` で図を生成する。テキストだけの説明で済ませない |
| UI の確認・操作・スクリーンショット | `mcp__playwright__*` でブラウザを実際に開く |
| GitHub の PR / Issue / コード検索 | `gh` CLI を使う（`gh pr`, `gh issue`, `gh api` 等） |
| パフォーマンス・ネットワーク問題 | `mcp__chrome-devtools__*` で実測する |
| コード構造の理解・リファクタ | Serena（下記） |

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
