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

## ツール採用基準（MCP / CLI / 削除）

新しいツールを追加する、または既存のものを置換するときは、まず以下のマトリクスで方式を決める。決まったら上の整合性ルールに従って横断更新する。

| 状況 | 採用方式 | 例 |
|---|---|---|
| 公式 CLI + 公式 skill が揃っている | **CLI + skill**（`scripts/post-setup.sh` で install） | `playwright-cli` + `playwright-cli install --skills`、`ntn` + `makenotion/skills` |
| 公式 CLI なし、公式 remote MCP のみ（OAuth で認証） | **remote HTTP MCP**（`dot_mcp.json` / `config.toml.tmpl` に URL のみ） | Slack、Exa、（過去の）Notion remote |
| Local stdio MCP に credential を渡す必要がある | **`mcp-with-keychain-secret` wrapper 経由**で Keychain から注入 | Brave Search |
| agent context との tight integration が本質（symbol 解析・ライブブラウザ観測など） | **MCP**（CLI 化すると価値が消える） | Serena、chrome-devtools、sequential-thinking |
| Claude Code の native tool（`Read` / `Write` / `Edit` / `Grep` / `Glob`）で代替できる | **削除**（追加せず、既存も外す） | filesystem MCP |
| text diff フレンドリーな代替がある | **代替に移行**（バイナリ依存の MCP は外す） | drawio MCP → Mermaid `.md` 直埋め + `mermaid-cli` |

判断の根拠：
- **CLI + skill が remote MCP に勝る場面**：token 効率（CLI 出力は pipe / file へ流せる、MCP tool schema は毎ターン context を食う）、scripted 用途（cron / CI / Claude Code を起動していない場面でも使える）、長時間セッション（CLI なら state をディスクに持てる）
- **remote MCP が CLI に勝る場面**：公式 CLI が無い or 用途違い、OAuth token 管理を agent 側に寄せられる、subprocess を起こさない
- **MCP を残すべき場面**：CLI 化で `mcp__*__*` の tool 単位 schema 配信が失われると価値が消える tight integration（symbol 解析、ライブ DOM 観測、CoT scaffolding 等）
- **削除すべき場面**：機能が既に native に吸収されている、または text diff フレンドリーな text-based 代替がある

迷ったら過去の判断（PR #26 = Playwright、#28 = Notion、その他 commit log）を見る。同じ理由で再度議論しないように。
