# `~/.claude/` 配下の管理モード

`~/.claude/` 以下は同じディレクトリでも管理経路が混在する。新規パスを追加するとき、または既存パスの管理モードを変更するときに、下表のどれかに分類して編集ルールに従う。分類できない新規パスを足すなら表を更新する。

| パス | 管理モード | 編集ルール |
|---|---|---|
| `~/.claude/CLAUDE.md` / `~/.claude/auto-save.sh` / `~/.claude/chezmoi-auto-apply.sh` / `~/.claude/lsp-hint.sh` / `~/.claude/statusline.sh` | chezmoi end-to-end | `home/dot_claude/` 側を編集すると Stop hook (`chezmoi-auto-apply.sh`) が dotfiles repo 配下の作業時に自動 `chezmoi apply`。手動で同期したい時は `chezmoi apply` / `make sync` |
| `~/.claude/skills/{jupyter-notebook,screenshot}` | chezmoi end-to-end (vendored) | 同上。`anthropic-agent-skills` marketplace は `docx`/`pdf`/`pptx`/`xlsx` のみ提供で `jupyter-notebook` / `screenshot` は無い → tier-3 vendor が最終手段として残置。marketplace に対応 plugin が現れたら plugin 化を検討して vendor を退避 |
| `~/.claude/skills/bitwarden-cli` | chezmoi end-to-end (vendored) | 同上。Bitwarden 公式 skill / marketplace plugin が無く tier-3 vendor。`home/dot_claude/skills/bitwarden-cli/SKILL.md` を編集すると zsh wrapper allowlist (`home/dot_config/zsh/bitwarden.zsh`) と `tests/bitwarden-zsh.sh` の denylist 配列の同期が必須（[change-checklist.md#cli-zsh](change-checklist.md#cli-zsh) 参照）。MCP 路線見送り経緯は archive 2026-04-29 |
| `~/.claude/skills/{security-best-practices,ui-ux-pro-max}` | post-setup install (skill, upstream `npx skills add`) | `scripts/post-setup.sh` の install ブロックを編集。upstream は `tech-leads-club/agent-skills` / `nextlevelbuilder/ui-ux-pro-max-skill`。`post-setup.sh` が install 完了後に `.upstream-installed` marker を skill dir に書き、`ai-repair.sh` がこの marker の有無で legacy vendored copy（marker 無し）を判別して能動 rm |
| `~/.claude/plugins/marketplaces/anthropic-agent-skills/` 配下の `document-skills` plugin (skills `docx`/`pdf`/`pptx`/`xlsx`) | post-setup install (plugin) | `scripts/lib/claude-plugins.sh` の `CLAUDE_DOCUMENT_PLUGINS` を編集。marketplace は `anthropics/skills` (`anthropic-agent-skills`)。旧 vendor `~/.claude/skills/{doc,pdf,presentation,spreadsheet}` は `ai-repair.sh` が能動 rm（path 直接判定、marker 不要） |
| `~/.claude/settings.json` の baseline 4 key（`autoUpdatesChannel` / `env.ENABLE_TOOL_SEARCH` / `hooks` / `effortLevel`） | dotfiles baseline | `scripts/ai-repair.sh` の upsert ロジックを編集。実体は Claude Code が rewrite する前提（`/effort` で local 上書き可、`make ai-repair` で high に snap back） |
| `~/.claude/settings.json` のそれ以外（`permissions` / `model` / `statusLine`） | local 自由 | 触らない（Claude Code が rewrite） |
| `~/.claude/skills/{gws-*,find-skills,playwright-cli,notion-cli}` | post-setup install (skill) | `scripts/post-setup.sh` の install 句を編集。`npx skills add` 経由 |
| `~/.claude/plugins/installed_plugins.json` | post-setup install (plugin) | `scripts/lib/claude-plugins.sh` の配列を編集。`claude plugin install` 経由 |
| `~/.claude/projects/` / `history.jsonl` / `sessions/` / `cache/` | 完全 local | 触らない |
| `~/.claude.json`（MCP 登録） | dotfiles baseline | `scripts/ai-repair.sh` の MCP 登録ブロックを編集 |
| `~/.claude/settings.local.json` | 完全 local | マシン固有 override。dotfiles では触らない |
| `~/.playwright/cli.config.json`（playwright-cli の global config） | chezmoi end-to-end | `home/dot_playwright/cli.config.json` を編集。playwright-cli が起動毎に auto load する `launchOptions.args` / `ignoreDefaultArgs` で stealth (`navigator.webdriver` 抑止) を成立させる |
