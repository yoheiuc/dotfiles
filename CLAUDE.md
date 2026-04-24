# dotfiles — Claude Code Notes

個人のツール採用ポリシー（MCP / CLI / 削除の判定マトリクス、タスク別ツール選択）は `~/.claude/CLAUDE.md`（= `home/dot_claude/CLAUDE.md`）に寄せた。ここにはこのリポジトリ固有の整合性ルールだけ置く。

## dotfiles 固有の整合性ルール

- dotfiles は再現性を優先し、ローカル state は混ぜない
- 設定ファイルの編集は dotfiles ソース（`home/` 以下）と実体（`~/` 以下）の両方を更新する。片方だけ変えると chezmoi apply で巻き戻る
- dotfiles ソースが正（single source of truth）。実体だけ変えて終わりにしない
- chezmoi のファイル名規則に従う（`dot_` プレフィックス、`executable_` プレフィックス、`.tmpl` サフィックス等）
- 認証情報・トークンを含むファイル（`hosts.yml`, `auth.json`, `oauth_creds.json` 等）は dotfiles に入れない
- 設定・スクリプト・テスト・ドキュメントに同じ情報が散在しているため、**片方だけ変えると不整合が残る**。変更時は常に下の依存マップに沿って横断更新する

## 変更箇所の依存マップ

### MCP サーバーの追加・削除・変更

影響範囲が広い。以下をすべて更新する:

- `home/dot_claude/dot_mcp.json`（Claude 側 HTTP MCP 登録）
- `scripts/ai-repair.sh`（drift 修復）
- `scripts/ai-audit.sh`（legacy 警告）
- `scripts/ai-secrets.sh`（credential が必要な場合）
- `README.md` の「MCP の基本セット」セクション
- routing table: `home/dot_claude/CLAUDE.md`
- 関連する `home/dot_claude/commands/*.md`
- `tests/` 配下の対応テスト

廃止時は `ai-repair.sh` で `ai_config_json_remove_mcp` を能動的に呼び、`ai-audit.sh` に legacy 警告を追加する。これを忘れると既存マシンが収束しない。

### CLI 系ツールの追加（npm global / brew 等）

- `scripts/post-setup.sh`（install）
- `scripts/doctor.sh`（存在確認）
- `home/dot_config/zsh/` の対応モジュール
- `home/dot_local/share/navi/cheats/dotfiles/` の cheat
- 関連する `home/dot_claude/commands/*.md`
- `README.md`
- `tests/` 配下の回帰テスト

### Claude Code の skill / plugin

- **公式 CLI で配布される** skill（gws / playwright / notion 等）: `scripts/post-setup.sh` が `~/.claude/skills/` に install。dotfiles source には入れない
- **plugin marketplace 経由で配布される** skill / plugin（`claude-plugins-official` の `frontend-design` / `*-lsp` 群）:
  - `claude plugin install <name>@claude-plugins-official` で install（per-user scope）
  - `scripts/doctor.sh` の `Claude Code (optional)` セクションで `~/.claude/plugins/installed_plugins.json` を jq で検証
  - dotfiles に SKILL.md を vendor しない。upstream が marketplace で rolling update するため、vendor すると drift する
  - README の該当節と `~/.claude/skills/` tree 図を更新
