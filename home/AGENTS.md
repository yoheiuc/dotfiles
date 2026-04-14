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
