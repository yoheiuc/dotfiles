# dotfiles — Claude Code Notes

- dotfiles は再現性を優先し、ローカル state は混ぜない
- 設定ファイルの編集は dotfiles ソース（`home/` 以下）と実体（`~/` 以下）の両方を更新する。片方だけ変えると chezmoi apply で巻き戻る
- dotfiles ソースが正（single source of truth）。実体だけ変えて終わりにしない
- chezmoi のファイル名規則に従う（`dot_` プレフィックス、`executable_` プレフィックス、`.tmpl` サフィックス等）
- 認証情報・トークンを含むファイル（`hosts.yml`, `auth.json`, `oauth_creds.json` 等）は dotfiles に入れない
- 何かを追加・削除・修正するときは、常にリポジトリ全体の整合性を考える。設定・スクリプト・テスト・ドキュメントに同じ情報が散在しているため、片方だけ変えると不整合が残る
- MCP サーバーの追加・削除は特に影響範囲が広い。`dot_mcp.json`、`config.toml.tmpl`、`ai-repair.sh`、`ai-audit.sh`、`ai-secrets.sh`（credential が必要な場合）、`README.md`、`CLAUDE.md`、および `tests/` 配下の対応テストをすべて更新する
