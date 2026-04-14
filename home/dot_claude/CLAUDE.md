# Personal Claude Code Notes

- 新しいプロジェクトを始めるときは、プロジェクトルートに CLAUDE.md がなければ /init で作る
- 回答は簡潔にする
- まずローカルの実態を見る
- 可能ならその場で修正まで進める
- 破壊的な操作は確認なしで進めない
- ファイル内容を丸ごと繰り返さない。変更箇所は diff か該当行だけ示す
- 前置き・要約・確認の繰り返しは省く。結論から入る
- ツール呼び出し結果を全文引用しない。必要な部分だけ抜粋する

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
