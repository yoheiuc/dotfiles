# Current State

- Ghostty は共通設定を控えめに維持し、未対応キーは入れない。
- Ghostty の GUI 変更は `chezmoi diff` で確認し、必要なものだけ dotfiles に取り込む。
- `local.ghostty` は共通設定から自動読込しない。使うマシンだけ手で有効化する。
- `doctor.sh` は誤検知とハングしやすい箇所を修正済みで、required は通る。
- Codex skill は repo 同梱方式に統一済みで、`post-setup.sh` で外部 clone しない。
- `make ai-repair` で Serena config と Claude Code / Codex の MCP registration を期待値へ戻せる。旧 dotfiles が持っていた `playwright` / `filesystem` / `drawio` / `notion` / `github` / `owlocr` / `chrome-devtools` / `brave-search` MCP は再実行で自動的に削除される。
- MCP baseline は `exa` / `slack` / `serena` / `vision` / `sequential-thinking`。`slack` は公式 remote（HTTP + OAuth）、`notion` は MCP を外して公式 CLI (`ntn`) + `makenotion/skills` 配置に移行した。`vision` は Apple Vision framework 経由の画像 OCR（`@tuannvm/vision-mcp-server`、`ja` / `en-US` / `zh-Hans` 等）。2026-04 に旧 `owlocr` から置き換え（upstream `jangisaac-dev/owlocr-mcp` が retire されたため）。ブラウザ操作は `@playwright/cli` + skill、ファイル操作は Claude Code の native tools、図は Mermaid（`.md` 直埋め or `mermaid-cli`）に寄せた。2026-04 に `chrome-devtools` MCP も外した：AI にユーザーの Chrome を操作させたい時に MCP が毎回 throwaway Chromium を立ち上げていたため、`@playwright/cli` v0.1.8 の `attach --cdp=chrome`（`pwattach` helper）で実 Chrome に接続する運用へ一本化。同じ 2026-04 に `brave-search` MCP も外した：検索系は Exa 一本で十分カバーでき、Keychain 経由 API key を維持するコストに見合わなくなったため。
- 同梱 skill は `screenshot`, `doc`, `pdf`, `spreadsheet`, `jupyter-notebook`, `security-best-practices`, `ui-ux-pro-max`, `codex-auto-save-memory`。`playwright` skill は `post-setup.sh` が `playwright-cli install --skills` で配置するため dotfiles 本体では管理しない。
- Claude Code は `~/.claude/CLAUDE.md` だけ管理し、`~/.claude/settings.json` はローカル管理にする。履歴や cache も管理しない。
- Gemini CLI は `~/.gemini/settings.json` をローカル管理にし、認証・履歴・state も管理しない。
- Codex は `~/AGENTS.md` と skill/alias を管理し、`~/.codex/config.toml` はローカル管理にする。auth や sessions も管理しない。
- Codex の `model_reasoning_effort` デフォルトは `medium`。プロファイルは廃止済み。
- dotfiles のマシン profile 抽象も廃止済み。Brewfile は `home/dot_Brewfile` 1 本で、`make sync` が単一フローで同期する。
- `make status` は日常確認用、`make ai-audit` はローカル管理の AI 設定確認用に使い分ける。
- `make doctor` は深い確認用として残し、日常確認は `status` / `ai-audit` を先に使う。
- README は全面的に日本語化済みで、今の運用方針に合わせて更新済み。
