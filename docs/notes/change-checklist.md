# 変更箇所の依存マップ

設定 / スクリプト / テスト / ドキュメントに同じ情報が散る構造のため、片側だけ更新すると必ず矛盾する。変更時は対応するセクションのチェックリストをすべて確認する。整合性は `make ai-audit` / `make doctor` / `make test` で全項目検証されるので、3 種とも green を確認すること。

## MCP

MCP サーバーの追加・削除・変更は影響範囲が広い。以下をすべて更新する:

- `scripts/ai-repair.sh`（baseline upsert / drift 修復 / 廃止 MCP の能動的削除）
- `scripts/ai-audit.sh`（baseline verify / legacy 警告）
- `tests/ai-repair.sh` / `tests/ai-audit.sh`（clean / drift / legacy 3 scenario すべて）
- 該当 entry が `post-setup.sh` に残っていないか確認（baseline は ai-repair に集約、post-setup での重複登録は責務分離違反）

`~/.claude/.mcp.json` は Claude Code が読まないパスなので絶対に書かない（MCP scope は local=`~/.claude.json` / project=`<project>/.mcp.json` / user=`~/.claude.json` の 3 つだけ）。

## Brewfile

Brewfile 変更（cask / formula）:

- `home/dot_Brewfile`（追加 / 削除）
- `scripts/doctor.sh`（AI 運用上の必須 binary なら存在確認を追加。例: `microsoft-edge` cask は `playwright-cli` セクション内で Edge.app の存在確認を行う）
- 追加対象が **CLI ツール**（`rg` / `jq` / `gh` / `mmdc` 等）なら下の [#cli-zsh](#cli-zsh) も実施。app cask（`microsoft-edge` / `ghostty` 等）は zsh / navi cheat 対象外

## cli-zsh

CLI ツール / zsh wrapper / cheat の追加・編集。CLI を新規導入する時は、Brewfile / npm install に加えて:

- `scripts/post-setup.sh`（npm / npx 系の install。brew で入るなら不要）
- `home/dot_config/zsh/` の対応モジュール（completion / alias / wrapper helper を置く場所）
- `home/dot_local/share/navi/cheats/dotfiles/` の cheat（よく叩くフラグ組み合わせ）
- `tests/` 配下の回帰テスト（zsh helper を足したなら必須）

wrapper が L1 セキュリティルール（例: `home/dot_config/zsh/playwright.zsh` の禁止 click / 禁止 eval / session 未設定 guard）を機械 enforce する場合は、対応 `tests/<tool>-zsh.sh` に **禁止 pattern が exit 1 / 読み取り系が素通し / `command <tool>` で bypass 可** の 3 系統を回帰必須。L1 文面と wrapper 実装の乖離はテスト無しでは検知できない。

ブラウザ自動化の運用ルール（user が `pwopen <tag>` / `pwedge` 起動 → Claude が `--session=<tag>` で attach する二段運用、tag 別に並走可能な profile / session、禁止 click / eval パターン、AI 専用プロファイル分離）は L1 (`home/dot_claude/CLAUDE.md`) の「ブラウザ自動化のセキュリティ規則」「ブラウザ自動化の運用デフォルト」節が正本。`pwopen <tag>` は `~/.ai-<tag>` profile を sibling 規則で生やす tag 駆動 launcher（`pwedge` は `pwopen edge` の back-compat shim）で、SaaS マルチテナント等で複数並走させたいときは `pwopen acme` / `pwopen tenant-foo` 等を user が任意に増やす。env override は `PLAYWRIGHT_AI_<TAG_UPPER>_PROFILE`（hyphen は underscore に変換）。dotfiles source 編集は不要、必要なら `~/.zshenv.local` 等で per-tag override を export。L2 で wrapper / cheat / Brewfile の整合を扱うときは L1 と乖離していないか確認する。stealth 設定は `home/dot_playwright/cli.config.json`（chezmoi → `~/.playwright/cli.config.json`）が `launchOptions.args` / `ignoreDefaultArgs` を担い、整合チェックは `playwright_is_stealth_patched` predicate + `make doctor` で毎回 verify（採用経緯は archive 2026-04-28）。

Bitwarden CLI の operation スコープ（read-only allowlist）は L1 (`home/dot_claude/CLAUDE.md`) の「Bitwarden CLI 操作のセキュリティ規則」が正本。allowlist / denylist を変更する場合は **(1) `home/dot_config/zsh/bitwarden.zsh` の wrapper 関数の `case` allowlist、(2) `home/dot_claude/skills/bitwarden-cli/SKILL.md` の許可コマンド表 / 禁止行為、(3) `tests/bitwarden-zsh.sh` の `allowed_cases` / `denied_cases` 配列、(4) L1 の規則文面** の 4 点を必ず同期する。BW_SESSION は短命 shell-scoped 運用が前提で disk 永続化禁止（CLAUDE.md「やらないこと」参照）。MCP 路線（`@bitwarden/mcp-server`）は上流が POC 表明のため不採用（2026-04-29 archive 参照）。

**stealth 化** (2026-04-28 採用): `~/.playwright/cli.config.json` (chezmoi 管理) で playwright-cli の global config に `launchOptions.args=["--disable-blink-features=AutomationControlled"]` + `ignoreDefaultArgs=["--enable-automation"]` を入れる方式。playwright-cli は起動毎にこの config を auto load し、`launchPersistentContext` の launchOptions にそのまま流し込むので CLI 表面・wrapper・テストには無影響。実証: `bot.sannysoft.com` で `WebDriver(New) missing (passed)` / `navigator.webdriver === false` 確認済み。同期点：

1. source `home/dot_playwright/cli.config.json` を編集
2. `scripts/lib/claude-checks.sh` の `playwright_is_stealth_patched` predicate が必須キーを `jq` で確認
3. `scripts/doctor.sh` の playwright-cli セクションが warn ベースで surface
4. `tests/playwright-zsh.sh` の test #16 が env export の forward-compat 挙動を回帰

rebrowser-patches Phase 1 (`playwright` package を直接 patch) は Anthropic 配布の `@playwright/cli` が bundle 化した `playwright-core` の `lib/coreBundle.js` 一本化レイアウトと非互換で見送り（archive 2026-04-28 の rejected entry 参照）。Runtime.Enable leak まで塞ぐ Phase 2 (patchright drop-in / coreBundle 手書き shim) は bot 判定が業務影響レベルに来てから別計画で着手。

**pwopen ephemeral + per-invocation unique profile** 整合 (2026-05-03 採用) の同期点：

1. `home/dot_config/zsh/playwright.zsh` の `__pwopen_cleanup` helper + `pwopen` 内 `trap … EXIT INT TERM` + profile schema `~/.ai-<tag>-<UTC>-<pid>` + 起動時 `~/.ai-<tag>-*` orphan sweep + `chmod 700`
2. `scripts/lib/claude-checks.sh` の `playwright_pwopen_is_ephemeral` predicate が 4 sentinel（cleanup 関数・trap 行・chmod 700・unique suffix）を grep 確認
3. `scripts/doctor.sh` の playwright-cli セクションと `scripts/ai-audit.sh` の Playwright Wrapper セクションで ok / attention surface
4. `tests/playwright-zsh.sh` の test #17 修正 + #21–#26（ephemeral on success / on failure / command bypass / chmod 700 / per-invocation unique / orphan sweep）

L1 の「`pwopen <tag>` は ephemeral」段落と本依存マップは 1 コミットで同時更新（部分更新は禁止）。env override (`PLAYWRIGHT_AI_<TAG>_PROFILE`) は固定 path での明示的 persistence opt-in として残し、override path は cleanup の `rm` 対象外（close / delete-data は常に発火）。pwlogin は別系統（明示的 persistence path、ephemeral 化スコープ外）。

## skills-plugins

Claude Code の skill / plugin の追加・削除:

- **公式 CLI で配布される** skill（gws / playwright / notion 等）: `scripts/post-setup.sh` が `~/.claude/skills/` に install。dotfiles source には vendor しない
- **plugin marketplace 経由で配布される** plugin（`claude-plugins-official` の LSP / general 群、`anthropic-agent-skills` の document 群）:
  - 期待リストは `scripts/lib/claude-plugins.sh` の `CLAUDE_LSP_PLUGINS` / `CLAUDE_GENERAL_PLUGINS` / `CLAUDE_DOCUMENT_PLUGINS` に集約。新規追加・削除はここを編集（同時に対応する `CLAUDE_*_MARKETPLACE_NAME` / `_SOURCE` 定数の確認）
  - `scripts/post-setup.sh` の `_install_claude_marketplace_plugins` ヘルパーが marketplace 単位で iterate し `claude plugin install <name>@<marketplace>` を冪等実行（per-user scope）。新 marketplace を足すならヘルパーへの追加 1 callsite で済む
  - `scripts/doctor.sh` / `scripts/ai-audit.sh` が同じリストと marketplace 名を使って `~/.claude/plugins/installed_plugins.json` 上の有無を検証（`claude_plugins_check_summary` の第 4 引数で marketplace 指定）
  - `scripts/lib/claude-checks.sh` の `claude_<group>_plugins_missing` predicate を group 単位で追加。marketplace 指定が必要なら `claude_plugin_is_installed "$p" "$marketplace_name"` で渡す
  - dotfiles に SKILL.md を vendor しない。upstream が marketplace で rolling update するため、vendor すると drift する
  - 旧 vendor copy（`home/dot_claude/skills/<name>/`）が残っているマシン向けに `scripts/ai-repair.sh` で能動 rm を入れる（path 直接判定。marker file は不要）。`tests/ai-repair.sh` に該当 skill ごとに fixture + assertion を追加
  - `tests/lib/testlib.sh` の `write_installed_plugins_stub` が新 group も `installed_plugins.json` fixture に含めるか確認

## settings-baseline

`~/.claude/settings.json` の baseline key を増減・変更するときは以下を全部更新する。一つでも漏らすと L2 / scripts / tests のどこかが嘘になる：

- `scripts/ai-repair.sh`: upsert 句の追加 + 「Claude Code local settings baseline」セクション冒頭の local-managed コメント（baseline / local 境界が動く）
- `scripts/ai-audit.sh`: ok / attention pair の追加
- `scripts/lib/claude-checks.sh`: predicate 関数の追加（`claude_<key>_is_<value>` 形式）
- `docs/notes/claude-paths.md`: baseline 行 / local 行
- `docs/notes/decisions-archive.md`: 政策変更のエントリを末尾に追記
- `docs/notes/current-state.md` の Claude Code 行
- `tests/ai-repair.sh`: 初期 upsert assertion と、user-override scenario の snap-back / preserve assertion
- `tests/ai-audit.sh`: clean / drift / legacy-MCP の 3 scenario すべてに fixture と assertion

## slash-commands

Claude Code slash command の追加・削除:

**新規追加は原則しない**（2026-04-26 archive エントリ参照：invoke されないと dead code、毎ターン守らせたい rule は L1 にインライン化が確実）。削除時は `scripts/ai-repair.sh` の retired_command 配列と `tests/ai-repair.sh` の retired-state scenario を更新する（chezmoi は orphan target を自動削除しない）。

## tests

shell ベース回帰テストは `tests/` 直下に 1 ファイル / 1 テーマで配置。新規テストを書く前に必ず:

- 共通 helper を `tests/lib/testlib.sh` から source する（`assert_eq` / `assert_contains` / `assert_not_contains` / `run_capture` / `pass_test` / `fail_test` / `write_installed_plugins_stub`）。独自 assertion を書かない
- subprocess は **hermetic 化**: `env -i "${HERMETIC_BASE_ENV[@]}" zsh -c …` 形式で親 shell の export（`PLAYWRIGHT_CLI_SESSION` / `REBROWSER_PATCHES_RUNTIME_FIX_MODE` / `PATH` 等）が leak しない構成にする（前例: `tests/playwright-zsh.sh` archive 2026-04-27 hermetic 化）
- 外部副作用（`npm install` / `claude plugin install` / file system 書き込み）は **PATH-stub** に置き換えて binary 呼び出しを固定（前例: `tests/post-setup.sh` / `tests/bootstrap.sh`）。実 binary を踏むと CI / 別マシンで再現性が崩れる
- `Makefile` の `test:` ターゲットに新規ファイルを追加し、`make test` で全 green を確認
- 命名規則は `tests/<script>.sh` だが、zsh helper の short name と揃える例外あり: `scripts/dotfiles-help.sh` → `tests/dothelp.sh`（zsh alias `dothelp` 由来）
