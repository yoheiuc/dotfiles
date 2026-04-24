# Current State

- Ghostty は共通設定を控えめに維持し、未対応キーは入れない。
- Ghostty の GUI 変更は `chezmoi diff` で確認し、必要なものだけ dotfiles に取り込む。
- `local.ghostty` は共通設定から自動読込しない。使うマシンだけ手で有効化する。
- `doctor.sh` は誤検知とハングしやすい箇所を修正済みで、required は通る。
- 2026-04 に Codex / Gemini を廃止し、AI agent は Claude Code 単独運用に一本化した。`home/dot_codex/` と `home/dot_gemini/`、root `AGENTS.md` と `home/AGENTS.md` は削除済み。以前 `home/dot_codex/skills/` にあった同梱 skill（screenshot / doc / pdf / spreadsheet / jupyter-notebook / security-best-practices / ui-ux-pro-max）は `home/dot_claude/skills/` に移した。`codex-auto-save-memory` は Codex 専用だったため削除した。
- `make ai-repair` で Claude Code の MCP registration と hooks を期待値へ戻せる。旧 dotfiles が持っていた `playwright` / `filesystem` / `drawio` / `notion` / `github` / `owlocr` / `chrome-devtools` / `brave-search` / `serena` MCP は再実行で自動的に削除される。
- MCP baseline は `exa` / `slack` / `vision` / `sequential-thinking`。`slack` は公式 remote（HTTP + OAuth）、`notion` は MCP を外して公式 CLI (`ntn`) + `makenotion/skills` 配置に移行した。`vision` は Apple Vision framework 経由の画像 OCR（`@tuannvm/vision-mcp-server`、`ja` / `en-US` / `zh-Hans` 等）。2026-04 に旧 `owlocr` から置き換え（upstream `jangisaac-dev/owlocr-mcp` が retire されたため）。ブラウザ操作は `@playwright/cli` + skill、ファイル操作は Claude Code の native tools、図は Mermaid（`.md` 直埋め or `mermaid-cli`）に寄せた。同じ 2026-04 に `chrome-devtools` MCP と `brave-search` MCP を外し、2026-04-24 にはコード解析用の `serena` MCP も retire して公式 marketplace の per-language LSP plugin（`pyright-lsp` / `typescript-lsp` / `gopls-lsp` / `rust-analyzer-lsp` / `clangd-lsp` / `csharp-lsp` / `jdtls-lsp` / `kotlin-lsp` / `lua-lsp` / `php-lsp` / `ruby-lsp` / `swift-lsp`）に一本化した：Claude Code の native LSP tool が findReferences / rename / diagnostics を含めてカバーし、MCP schema のオーバーヘッドと uvx 依存が不要になったため。
- 同梱 skill は `screenshot`, `doc`, `pdf`, `spreadsheet`, `jupyter-notebook`, `security-best-practices`, `ui-ux-pro-max`。`playwright` skill は `post-setup.sh` が `playwright-cli install --skills` で配置するため dotfiles 本体では管理しない。
- Claude Code は `~/.claude/CLAUDE.md` だけ管理し、`~/.claude/settings.json` はローカル管理にする。履歴や cache も管理しない。
- dotfiles のマシン profile 抽象も廃止済み。Brewfile は `home/dot_Brewfile` 1 本で、`make sync` が単一フローで同期する。
- `make status` は日常確認用、`make ai-audit` はローカル管理の AI 設定確認用に使い分ける。
- `make doctor` は深い確認用として残し、日常確認は `status` / `ai-audit` を先に使う。
- README は全面的に日本語化済みで、今の運用方針に合わせて更新済み。
