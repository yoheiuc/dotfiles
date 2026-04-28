# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# dotfiles — Claude Code Notes

このリポジトリで作業する Claude / 自分が読むためのルール集。会話中の振る舞いルール（簡潔に答える、日本語で返す等）と subagent の運用ルール（呼ぶ / 呼ばない判断とモデル振り分け）は `~/.claude/CLAUDE.md`（L1）側にある。

このファイル（L2）が担当するのは「新ツールを足すか / 既存を直すか / 何も足さないか」の判断と、その判断を一貫させるための整合性ルール。

## このリポについて（30 秒）

macOS 開発環境（chezmoi で `~/` 以下を管理 + Brewfile + Claude Code 設定）。`home/` 以下が single source of truth。

- 状態確認: `make status` → `make ai-audit` → `make doctor`（深さの順）
- 修復: `make ai-repair`（AI 設定 drift） / `make sync`（実体寄せ + post-setup、`PULL=1` で `git pull origin main` 同梱）
- 全テスト: `make test`。単体テスト 1 本だけは `bash tests/<name>.sh` — 編集箇所別によく叩くのは `bash tests/ai-repair.sh`（MCP / hooks / 廃止 cleanup を変更時）/ `bash tests/post-setup.sh`（plugin / skill install を変更時）/ `bash tests/doctor.sh`（診断項目を変更時）/ `bash tests/playwright-zsh.sh`（zsh wrapper 編集時）
- コミット規約は L1 (`~/.claude/CLAUDE.md`) を正本とし、本リポも同じルール

詳細・セットアップ手順は `README.md`。

## Architecture (60 秒)

実体管理は 3 層に分かれている:

1. **chezmoi** (`home/` → `~/`): declarative file sync。Stop hook (`home/dot_claude/executable_chezmoi-auto-apply.sh`) が dotfiles repo 配下作業時に毎ターン末で自動 `chezmoi apply`
2. **`scripts/post-setup.sh`**: imperative install (`npm install` / `curl | bash` / `claude plugin install` / `npx skills add`)。冪等。`make install` / `make sync` から呼ばれる
3. **`scripts/ai-repair.sh` + `scripts/ai-audit.sh`**: drift detect-and-repair pair。Claude Code 設定 (`~/.claude.json` の MCP / `~/.claude/settings.json` の baseline 4 key / hooks / 廃止 MCP の能動削除) が外乱で書き換わるのを反復修正

`scripts/doctor.sh` は (1)-(3) と独立した system-wide diagnostic（Brewfile / git identity / Claude / clasp / SSL compat 等 22 セクション）。read-only。検証ロジックは `scripts/lib/claude-checks.sh` の predicate 群に集約され ai-audit / doctor の 2 caller が共有。`scripts/lib/` は単一責務 5 本: `ui.sh` / `ai-config.sh` / `claude-checks.sh` / `claude-plugins.sh` / `brew-autoupdate.sh`。

## このファイルの読み方

- 変更を加えるとき: 「整合性ルール」→「変更箇所の依存マップ」を必ず通す（更新漏れで scripts / tests / docs が矛盾する事故を防ぐ）
- 過去の判断を辿るとき / 新しい判断を追記するとき: [`docs/notes/decisions-archive.md`](docs/notes/decisions-archive.md)（末尾追記、`status` 凡例は archive 冒頭）

## ツール採用基準

新ツールの追加・置換は以下のマトリクスで方式を決める。迷ったら削除が既定。

| 状況 | 採用方式 | 例 |
|---|---|---|
| 公式 CLI + 公式 skill が揃っている | **CLI + skill**（`scripts/post-setup.sh` で install） | `playwright-cli`、`ntn`、`gws` |
| 公式 CLI なし、公式 remote MCP がある（OAuth 認証） | **remote HTTP MCP**（`scripts/ai-repair.sh` で `~/.claude.json` に upsert） | Slack、Exa、Jamf docs |
| agent context との tight integration が本質 | **MCP**（CLI 化すると価値が消える） | sequential-thinking |
| LSP ベースの symbol 解析 | **Claude Code native LSP tool + 公式 plugin** | `pyright-lsp` ほか（`claude-plugins-official`） |
| Claude Code の native tool（Read / Write / Edit / Grep / Glob）で代替できる | **削除 / 不採用** | filesystem MCP |
| text diff フレンドリーな代替がある | **代替に移行** | drawio MCP → Mermaid |

優先順位の理由:

- **CLI + skill > MCP**: token 効率（CLI 出力は pipe / file へ流せる、tool schema は毎ターン context を食う）、scripted 用途（cron / CI でも呼べる）、長時間セッション（state をディスクに持てる）
- **remote MCP > local stdio MCP**: subprocess を起こさない、OAuth token 管理を agent 側に集約、Keychain 不要
- **MCP > CLI**: CLI 化で `mcp__*__*` の tool 単位 schema 配信が失われると価値が消える tight integration（symbol 解析、ライブ DOM 観測、CoT scaffolding 等）

### skill / plugin 配布の優先順位

Claude Code に skill / plugin を足したいときは上から順に検討する。

1. **Anthropic 公式 / vetted marketplace の plugin**: `scripts/lib/claude-plugins.sh` の **配列 + marketplace 名のペア**に追加 → `make install` で自動配置。SHA pin で再現性あり、upstream rolling update も marketplace 経由で取り込める。現時点で 2 marketplace を使用中：
   - `claude-plugins-official` (`anthropics/claude-plugins-official`): LSP plugin 群 (`CLAUDE_LSP_PLUGINS`) + general plugin 群 (`CLAUDE_GENERAL_PLUGINS`)
   - `anthropic-agent-skills` (`anthropics/skills`): document skills (`CLAUDE_DOCUMENT_PLUGINS` = `document-skills` plugin が `docx`/`pdf`/`pptx`/`xlsx` を bundle)
2. **upstream の公式 CLI が提供する skill 配布**（gws / playwright / notion 等）: `scripts/post-setup.sh` の `npx skills add ...` で `~/.claude/skills/` に install。dotfiles source には入れない
3. **vendor**（`home/dot_claude/skills/` に SKILL.md 直置き）: 上の 1 / 2 で配布されていない場合のみの最終手段。marketplace に対応 plugin が出たら都度 vendor を退避する（frontend-design = c606583、document skills 4 種 = 2026-04-27 の前例）

理由: vendor すると upstream の rolling update から取り残されて drift するし、license / 更新責任が dotfiles 側に来る。可能な限り marketplace か公式 distributor に任せる。

## スクリプトの責務境界

ヘルスチェック・修復系の3スクリプトの境界:

| script | 種類 | 守備範囲 | 想定の使われ方 |
|---|---|---|---|
| `scripts/ai-repair.sh` | **write**（drift 修復） | Claude Code 設定 baseline / MCP 登録 / hooks / legacy 削除 | `make ai-repair`、`post-setup.sh` から自動呼び出し |
| `scripts/ai-audit.sh` | **read**（AI 設定 drift 検出） | 上と同じ範囲を予測値と突き合わせて diff 報告 | `make ai-audit`、CI / 通知 |
| `scripts/doctor.sh` | **read**（システム全体の健康診断） | OS tools / Brewfile / git identity / Claude / clasp / gcloud / SSL compat 等 22 セクション | `make doctor`、新環境 setup 後 |

検証ロジックは `scripts/lib/claude-checks.sh` の predicate に集約（`ai-audit` / `doctor` の両方が同じ関数を呼ぶ）。message format だけ各スクリプトが自分の調子で組み立てる。

`scripts/lib/` は単一責務で分割（`ui.sh` / `ai-config.sh` / `claude-checks.sh` / `claude-plugins.sh` / `brew-autoupdate.sh`）。新しい共通処理を足すときはどれにも合わなければ新 lib を作る（既存 lib を肥大化させない）。各 lib のヘッダコメントに役割を書く。

## `~/.claude/` 配下の管理モード

同じディレクトリでも管理経路が混在する。新規パスを追加するときは下表のどれかに分類して、編集ルールに従う。分類できない新規パスを足すなら表を更新する。

| パス | 管理モード | 編集ルール |
|---|---|---|
| `~/.claude/CLAUDE.md` / `auto-save.sh` / `chezmoi-auto-apply.sh` / `lsp-hint.sh` / `statusline.sh` | chezmoi end-to-end | `home/dot_claude/` 側を編集すると Stop hook (`chezmoi-auto-apply.sh`) が dotfiles repo 配下の作業時に自動 `chezmoi apply`。手動で同期したい時は `chezmoi apply` / `make sync` |
| `~/.claude/skills/{jupyter-notebook,screenshot}` | chezmoi end-to-end (vendored) | 同上。marketplace 未提供のため tier-3 vendor 残置。対応 plugin が出たら退避 |
| `~/.claude/skills/{security-best-practices,ui-ux-pro-max}` | post-setup install (skill, `npx skills add`) | `scripts/post-setup.sh` の install ブロックを編集。marker file `.upstream-installed` 不在で legacy vendor 判定 → `ai-repair.sh` で能動 rm |
| `~/.claude/plugins/marketplaces/anthropic-agent-skills/` 配下の `document-skills` plugin (`docx`/`pdf`/`pptx`/`xlsx`) | post-setup install (plugin) | `scripts/lib/claude-plugins.sh` の `CLAUDE_DOCUMENT_PLUGINS` を編集。旧 vendor `skills/{doc,pdf,presentation,spreadsheet}` は `ai-repair.sh` が path 直接判定で rm |
| `~/.claude/settings.json` の baseline 4 key（`autoUpdatesChannel` / `env.ENABLE_TOOL_SEARCH` / `hooks` / `effortLevel`） | dotfiles baseline | `scripts/ai-repair.sh` の upsert を編集。Claude Code が rewrite する前提（`/effort` で local 上書き可、`make ai-repair` で snap back） |
| `~/.claude/settings.json` のそれ以外（`permissions` / `model` / `statusLine`） | local 自由 | 触らない（Claude Code が rewrite） |
| `~/.claude/skills/{gws-*,find-skills,playwright-cli,notion-cli}` | post-setup install (skill) | `scripts/post-setup.sh` の install 句を編集。`npx skills add` 経由 |
| `~/.claude/plugins/installed_plugins.json` | post-setup install (plugin) | `scripts/lib/claude-plugins.sh` の配列を編集。`claude plugin install` 経由 |
| `~/.claude/projects/` / `history.jsonl` / `sessions/` / `cache/` | 完全 local | 触らない |
| `~/.claude.json`（MCP 登録） | dotfiles baseline | `scripts/ai-repair.sh` の MCP 登録ブロックを編集 |
| `~/.claude/settings.local.json` | 完全 local | マシン固有 override。dotfiles では触らない |
| `~/.playwright/cli.config.json` | chezmoi end-to-end | `home/dot_playwright/cli.config.json` を編集。stealth 設定（archive 2026-04-28） |

## 整合性ルール

同じ情報が設定 / スクリプト / テスト / ドキュメントに散る構造なので、片側だけ更新すると必ず矛盾する。

- dotfiles ソース（`home/` 以下）が single source of truth。実体（`~/` 以下）だけ変えると次の Claude turn 末（`chezmoi-auto-apply.sh` Stop hook）か手動 `chezmoi apply` で巻き戻る
- chezmoi の命名規則を守る: `dot_` / `executable_` / `.tmpl` / `private_` 等
- credential / token を含むファイル（`hosts.yml` / `auth.json` / `oauth_creds.json` / `.netrc`）は dotfiles に入れない。Keychain に置く
- 廃止時は `ai-repair.sh` で能動的に削除し、`ai-audit.sh` に legacy 警告を追加する。これをやらないと既存マシンが収束しない

上記の整合性は `make ai-audit` / `make doctor` / `make test` で全項目検証されるので、変更を加えたら必ず 3 種類とも green を確認する。

本リポでよく使う commit prefix の例: `docs` / `ai` / `ai-audit` / `mcp` / `skills` / `playwright` / `pwedge` / `statusline` / `ghostty` / `tests` / `dotfiles`（広いスコープは `dotfiles:`）。

## やらないこと

頻出アンチパターン。踏むと drift / dead code / cleanup 漏れの原因になる:

- `~/` 以下を直接編集する → 次のターン末で `chezmoi-auto-apply.sh` Stop hook が `home/` から巻き戻す。実体だけ変えても source が真。
- `~/.claude/.mcp.json` に書く → 公式 MCP scope（`local=~/.claude.json` / `project=<repo>/.mcp.json` / `user=~/.claude.json`）に該当しない dead path。Claude Code は load しない。
- `home/dot_claude/commands/` に新しい slash command を追加 → invoke されないと dead code（archive 2026-04-26）。毎ターン守らせたい rule は L1 (`home/dot_claude/CLAUDE.md`) にインライン化する方が確実。
- `home/dot_claude/skills/` に SKILL.md を vendor → marketplace plugin / `npx skills add` 配布が tier 1-2、vendor は tier 3 の最終手段。tier 1-2 が出現したら都度 vendor 退避。
- chezmoi 命名規則を破る（`dot_` / `executable_` / `.tmpl` / `private_` の prefix を欠落させる）。
- credential / token を `home/` 配下に入れる → Keychain に置く。`hosts.yml` / `auth.json` / `oauth_creds.json` / `.netrc` 等は dotfiles に commit しない。
- user 明示要求なしに `--no-verify` / `git push --force` / `git reset --hard` / `chmod -R` 系の destructive flag を使う（commit 規約 L1）。
- 廃止時に `scripts/ai-repair.sh` の能動削除と `scripts/ai-audit.sh` の legacy 警告を入れ忘れる → chezmoi は orphan target を自動削除しないため、既存マシンが収束しない。

## 変更箇所の依存マップ

### MCP サーバーの追加・削除・変更

影響範囲が広い。以下をすべて更新する:

- `scripts/ai-repair.sh`（baseline upsert / drift 修復 / 廃止 MCP の能動的削除）
- `scripts/ai-audit.sh`（baseline verify / legacy 警告）
- `tests/ai-repair.sh` / `tests/ai-audit.sh`（clean / drift / legacy 3 scenario すべて）
- 該当 entry が `post-setup.sh` に残っていないか確認（baseline は ai-repair に集約、post-setup での重複登録は責務分離違反）

`~/.claude/.mcp.json` は Claude Code が読まないパスなので絶対に書かない（MCP scope は local=`~/.claude.json` / project=`<project>/.mcp.json` / user=`~/.claude.json` の 3 つだけ）。

### Brewfile 変更（cask / formula）

- `home/dot_Brewfile`（追加 / 削除）
- `scripts/doctor.sh`（AI 運用上の必須 binary なら存在確認を追加。例: `microsoft-edge` cask は `playwright-cli` セクション内で Edge.app の存在確認を行う）
- 追加対象が **CLI ツール**（`rg` / `jq` / `gh` / `mmdc` 等）なら下の「CLI ツールの zsh / cheat 統合」も実施。app cask（`microsoft-edge` / `ghostty` 等）は zsh / navi cheat 対象外

### CLI ツールの zsh / cheat 統合

CLI を新規導入する時は、Brewfile / npm install に加えて:

- `scripts/post-setup.sh`（npm / npx 系の install。brew で入るなら不要）
- `home/dot_config/zsh/` の対応モジュール（completion / alias / wrapper helper を置く場所）
- `home/dot_local/share/navi/cheats/dotfiles/` の cheat（よく叩くフラグ組み合わせ）
- `tests/` 配下の回帰テスト（zsh helper を足したなら必須）

wrapper が L1 セキュリティルール（例: `home/dot_config/zsh/playwright.zsh` の禁止 click / 禁止 eval / session 未設定 guard）を機械 enforce する場合は、対応 `tests/<tool>-zsh.sh` に **禁止 pattern が exit 1 / 読み取り系が素通し / `command <tool>` で bypass 可** の 3 系統を回帰必須。L1 文面と wrapper 実装の乖離はテスト無しでは検知できない。

ブラウザ自動化の運用ルール（`pwopen <tag>` 起動 → `--session=<tag>` attach の二段運用、tag 別並走、禁止 click / eval、AI 専用プロファイル分離）は L1 「ブラウザ自動化のセキュリティ規則」「運用デフォルト」節が正本。L2 で wrapper / cheat / Brewfile の整合を扱うときは L1 と乖離していないか確認する。stealth は `home/dot_playwright/cli.config.json`（chezmoi → `~/.playwright/cli.config.json`）の `launchOptions.args` / `ignoreDefaultArgs` で完結。整合は `playwright_is_stealth_patched` predicate + `make doctor` で verify（採用経緯と Phase 2 計画は archive 2026-04-28）。

### Claude Code の skill / plugin

- 公式 CLI 配布の skill（gws / playwright / notion 等）: `scripts/post-setup.sh` の `npx skills add` 句を編集。dotfiles source には vendor しない
- marketplace plugin: `scripts/lib/claude-plugins.sh` の `CLAUDE_*_PLUGINS` 配列 + `_MARKETPLACE_NAME` / `_SOURCE` 定数を編集。`scripts/post-setup.sh::_install_claude_marketplace_plugins` が marketplace 単位で冪等 install。新 marketplace 追加もヘルパーへの 1 callsite で済む
- 検証: `scripts/doctor.sh` / `scripts/ai-audit.sh` が同じ配列で `installed_plugins.json` を verify（`claude_plugins_check_summary` の第 4 引数に marketplace 名）。group 単位の predicate `claude_<group>_plugins_missing` は `scripts/lib/claude-checks.sh` に追加
- vendor 退避が要るときは `scripts/ai-repair.sh` に path 直接判定の能動 rm + `tests/ai-repair.sh` に fixture / assertion 追加。`tests/lib/testlib.sh::write_installed_plugins_stub` が新 group を含むか確認

### Claude Code `settings.json` の baseline key 追加・変更

`~/.claude/settings.json` の baseline key を増減・変更するときは以下を全部更新する。一つでも漏らすと L2 / scripts / tests のどこかが嘘になる：

- `scripts/ai-repair.sh`: upsert 句の追加 + 「Claude Code local settings baseline」セクション冒頭の local-managed コメント（baseline / local 境界が動く）
- `scripts/ai-audit.sh`: ok / attention pair の追加
- `scripts/lib/claude-checks.sh`: predicate 関数の追加（`claude_<key>_is_<value>` 形式）
- `CLAUDE.md`（L2）「`~/.claude/` 配下の管理モード」表の baseline 行 / local 行
- `docs/notes/decisions-archive.md`: 政策変更のエントリを末尾に追記
- `docs/notes/current-state.md` の Claude Code 行
- `tests/ai-repair.sh`: 初期 upsert assertion と、user-override scenario の snap-back / preserve assertion
- `tests/ai-audit.sh`: clean / drift / legacy-MCP の 3 scenario すべてに fixture と assertion

### Claude Code slash command の追加・削除

**新規追加は原則しない**（2026-04-26 archive エントリ参照：invoke されないと dead code、毎ターン守らせたい rule は L1 にインライン化が確実）。削除時は `scripts/ai-repair.sh` の retired_command 配列と `tests/ai-repair.sh` の retired-state scenario を更新する（chezmoi は orphan target を自動削除しない）。

### テストの追加・編集

shell ベース回帰テストは `tests/` 直下に 1 ファイル / 1 テーマで配置。新規テストを書く前に必ず:

- 共通 helper を `tests/lib/testlib.sh` から source する（`assert_eq` / `assert_contains` / `assert_not_contains` / `run_capture` / `pass_test` / `fail_test` / `write_installed_plugins_stub`）。独自 assertion を書かない
- subprocess は **hermetic 化**: `env -i "${HERMETIC_BASE_ENV[@]}" zsh -c …` 形式で親 shell の export（`PLAYWRIGHT_CLI_SESSION` / `REBROWSER_PATCHES_RUNTIME_FIX_MODE` / `PATH` 等）が leak しない構成にする（前例: `tests/playwright-zsh.sh` archive 2026-04-27 hermetic 化）
- 外部副作用（`npm install` / `claude plugin install` / file system 書き込み）は **PATH-stub** に置き換えて binary 呼び出しを固定（前例: `tests/post-setup.sh` / `tests/bootstrap.sh`）。実 binary を踏むと CI / 別マシンで再現性が崩れる
- `Makefile` の `test:` ターゲットに新規ファイルを追加し、`make test` で全 green を確認
