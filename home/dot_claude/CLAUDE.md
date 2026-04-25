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
- **編集後は実体で動作検証する**。typecheck / test / 実コマンド実行で「動いた」まで確認してから完了宣言する。文書 diff だけで OK としない
- **テスト中の副作用を避ける**。投稿 / 送信 / 外部 API への実書き込みは事前に user 確認を取り、stub / dry-run / mock で代替できないかまず検討
- **未インストール依存は最初に解決する**。workaround で進めず、まず install / config を提案して実行
- **方向性が分かれる提案は A / B / C で並べてデフォルトを示す**。user が選択を redirect しやすい
- 作業前に **skill を確認する**:
  1. `~/.claude/skills/` 配下に合致しそうな skill があれば使う
  2. 思い当たらなければ `find-skills` skill（`~/.claude/skills/find-skills/`）で英語キーワード検索 — `npx skills find "<keyword>"` / `npx skills list` / `npx skills check` も同等
  3. 見つかったら SKILL.md の手順に従う

## ツール選択ルール

テキストで説明するだけで終わらせず、ツールで実行する。

| やりたいこと | 使うツール |
|---|---|
| Web 検索 / 最新情報調査 | `mcp__exa__web_search_exa` / `mcp__exa__web_fetch_exa` |
| Notion 操作 | `ntn` CLI（`~/.claude/skills/notion-cli/`） |
| Slack 操作 | `mcp__slack__*` |
| 図 | Mermaid（`.md` 直埋め）。PNG/SVG は `mmdc` |
| ブラウザ操作 | `playwright-cli`。`PLAYWRIGHT_CLI_SESSION=chrome` なら detach しない |
| GitHub | `gh` CLI |
| OCR（日本語含む） | `mcp__vision__ocr_extract_text` |
| コード構造の理解・リファクタ | Claude Code native LSP tool（下記） |

setup 手順 / 認証 / 採用基準は `~/dotfiles/CLAUDE.md` と `README.md` 側。

新ツールの採用基準・dotfiles 編集時の依存マップ・過去の個別判断ログは `~/dotfiles/CLAUDE.md`（L2）に集約してある。dotfiles 配下で作業するときに自動で読み込まれる。

## Subagent のモデル振り分け

`Agent` tool を呼ぶときは、タスクの性質に合わせて `model` を明示する。デフォルト（親と同じモデル）に任せるとコスト 2-3 倍になる場面がある。

| タスクの性質 | 推奨モデル |
|---|---|
| 探索 / 検索 / ファイル一覧 / 単純な情報集約 / 横断 grep | `haiku` |
| コードベース全体の俯瞰 / アーキテクチャ要約 | `haiku`（要約が主目的なら） |
| 実装 / refactor / API 設計 / セキュリティレビュー | `sonnet` or `opus`（親モデル） |
| 複雑な Web 調査 / 裏取りが必要な事実確認 | `sonnet`（haiku では裏取り精度が足りない場面がある） |
| 大規模変更の独立レビュー（この repo でやる `general-purpose` レビュー agent 等） | `sonnet` or 親モデル |

Escalation rule：haiku で投げて品質不足（根拠が薄い / 事実誤認）だった場合は、同じプロンプトを `sonnet` で再試行する。最初から opus を投げるのはコスト効率が悪い。

コスト目安：haiku は sonnet の 1/5〜1/10、opus の 1/20。探索系で haiku が使えるなら全体コストが 40-50% 下がる報告あり。

## Claude Code native LSP plugin

Anthropic 公式 marketplace (`claude-plugins-official`) の per-language LSP plugin 群を導入済み。期待リストは `~/dotfiles/scripts/lib/claude-plugins.sh` で管理。

以下は Grep より native LSP tool を優先する場面:
- シンボルの定義箇所を探す（go-to-definition）
- 呼び出し元・参照箇所を網羅的に探す（find references）
- シンボルの型・docstring（hover）
- ファイル内シンボル一覧（document symbols）
- クロスファイル rename
- edit 前後の LSP diagnostics

旧 `mcp__serena__*` tool は廃止されたので呼ばない（alias が残っているだけ）。

## コミット規約（全リポ共通）

- prefix style: `<topic>: <動詞句>`（topic は変更箇所のスコープ、git log の前例を踏襲する。スコープが広いときは repo 名）
- subject は 1 行要約、詳細は body の bullet
- HEREDOC で渡し、末尾に `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
- `git push` は remote に visible になる action なので、必ず user に明示確認を取ってから実行
- destructive な flag (`--force`, `--no-verify`, `reset --hard` 等) は user が明示要求しない限り使わない
