# dotfiles — Claude Code Notes

- dotfiles は再現性を優先し、ローカル state は混ぜない
- 設定ファイルの編集は dotfiles ソース（`home/` 以下）と実体（`~/` 以下）の両方を更新する。片方だけ変えると chezmoi apply で巻き戻る
- dotfiles ソースが正（single source of truth）。実体だけ変えて終わりにしない
- chezmoi のファイル名規則に従う（`dot_` プレフィックス、`executable_` プレフィックス、`.tmpl` サフィックス等）
- 認証情報・トークンを含むファイル（`hosts.yml`, `auth.json`, `oauth_creds.json` 等）は dotfiles に入れない
- 何かを追加・削除・修正するときは、常にリポジトリ全体の整合性を考える。設定・スクリプト・テスト・ドキュメントに同じ情報が散在しているため、片方だけ変えると不整合が残る
- MCP サーバーの追加・削除は特に影響範囲が広い。`dot_mcp.json`、`config.toml.tmpl`、`ai-repair.sh`、`ai-audit.sh`、`ai-secrets.sh`（credential が必要な場合）、`README.md`、`CLAUDE.md`、および `tests/` 配下の対応テストをすべて更新する。さらに routing table も同時に直す（Claude: `home/dot_claude/CLAUDE.md`、Codex: `home/AGENTS.md`）。関連する `home/dot_claude/commands/*.md` の記述も揃える
- MCP を廃止するときは `ai-repair.sh` 側で残存エントリを `ai_config_json_remove_mcp` / `ai_config_toml_remove_mcp_section` で能動的に削除し、`ai-audit.sh` にも legacy 警告を追加する。こうしないと既存マシンが収束しない
- CLI 系ツール（`playwright-cli` のような npm global / brew など）を追加するときは、`scripts/post-setup.sh`、`scripts/doctor.sh`、`home/dot_config/zsh/` の対応モジュール、`home/dot_local/share/navi/cheats/dotfiles/` の cheat、該当する `home/dot_claude/commands/*.md`、`README.md`、および `tests/` 配下の回帰テストを同時に更新する
