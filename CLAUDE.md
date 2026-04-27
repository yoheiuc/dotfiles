# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# dotfiles — Claude Code Notes

このリポジトリで作業する Claude / 自分が読むためのルール集。会話中の振る舞いルール（簡潔に答える、日本語で返す等）と subagent の運用ルール（呼ぶ / 呼ばない判断とモデル振り分け）は `~/.claude/CLAUDE.md`（L1）側にある。

このファイル（L2）が担当するのは「新ツールを足すか / 既存を直すか / 何も足さないか」の判断と、その判断を一貫させるための整合性ルール。

## このリポについて（30 秒）

macOS 開発環境（chezmoi で `~/` 以下を管理 + Brewfile + Claude Code 設定）。`home/` 以下が single source of truth。

- 状態確認: `make status` → `make ai-audit` → `make doctor`（深さの順）
- 修復: `make ai-repair`（AI 設定 drift） / `make sync`（実体寄せ + post-setup、`PULL=1` で `git pull origin main` 同梱）
- 全テスト: `make test`、単体テスト 1 本だけは `bash tests/<name>.sh`（例: `bash tests/ai-repair.sh`）

詳細・セットアップ手順は `README.md`。

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
| 公式 CLI が既存 process への attach を持っている | **CLI の attach 機能**（MCP が throwaway を立てるなら避ける） | `pwattach` で実 Chrome |

優先順位の理由:

- **CLI + skill > MCP**: token 効率（CLI 出力は pipe / file へ流せる、tool schema は毎ターン context を食う）、scripted 用途（cron / CI でも呼べる）、長時間セッション（state をディスクに持てる）
- **remote MCP > local stdio MCP**: subprocess を起こさない、OAuth token 管理を agent 側に集約、Keychain 不要
- **MCP > CLI**: CLI 化で `mcp__*__*` の tool 単位 schema 配信が失われると価値が消える tight integration（symbol 解析、ライブ DOM 観測、CoT scaffolding 等）

### skill / plugin 配布の優先順位

Claude Code に skill / plugin を足したいときは上から順に検討する。

1. **`claude-plugins-official` marketplace の plugin**: `scripts/lib/claude-plugins.sh` の配列に追加 → `make install` で自動配置。SHA pin で再現性あり、upstream rolling update も marketplace 経由で取り込める
2. **upstream の公式 CLI が提供する skill 配布**（gws / playwright / notion 等）: `scripts/post-setup.sh` の `npx skills add ...` で `~/.claude/skills/` に install。dotfiles source には入れない
3. **vendor**（`home/dot_claude/skills/` に SKILL.md 直置き）: 上の 1 / 2 で配布されていない場合のみの最終手段。marketplace に対応 plugin が出たら都度 vendor を退避する（frontend-design = c606583 の前例）

理由: vendor すると upstream の rolling update から取り残されて drift するし、license / 更新責任が dotfiles 側に来る。可能な限り marketplace か公式 distributor に任せる。

## スクリプトの責務境界

ヘルスチェック・修復系の3スクリプトの境界:

| script | 種類 | 守備範囲 | 想定の使われ方 |
|---|---|---|---|
| `scripts/ai-repair.sh` | **write**（drift 修復） | Claude Code 設定 baseline / MCP 登録 / hooks / legacy 削除 | `make ai-repair`、`post-setup.sh` から自動呼び出し |
| `scripts/ai-audit.sh` | **read**（AI 設定 drift 検出） | 上と同じ範囲を予測値と突き合わせて diff 報告 | `make ai-audit`、CI / 通知 |
| `scripts/doctor.sh` | **read**（システム全体の健康診断） | OS tools / Brewfile / git identity / Claude / clasp / gcloud / SSL compat 等 22 セクション | `make doctor`、新環境 setup 後 |

検証ロジックは `scripts/lib/claude-checks.sh` の predicate に集約（`ai-audit` / `doctor` の両方が同じ関数を呼ぶ）。message format だけ各スクリプトが自分の調子で組み立てる。

### `scripts/lib/` の責務一覧

各 lib は単一責務。新しい共通処理を足すときはどれにも合わなければ新 lib を作る（既存 lib を肥大化させない）。

| lib | 責務 | 主な consumer |
|---|---|---|
| `ui.sh` | `section` / `ok` / `warn` / `info` の出力ヘルパー | `doctor` / `ai-audit` / `ai-repair` / `status` / `post-setup` |
| `ai-config.sh` + `ai_config.py` | `~/.claude.json` / `settings.json` の安全な read / upsert / remove。JSON mutation は Python が tempfile + `os.replace` で原子的に行う | `ai-audit` / `ai-repair` |
| `claude-checks.sh` | Claude Code 設定の純粋 predicate（hook 登録 / MCP 登録 / autoupdate channel 等の有無を bool で返す） | `ai-audit` / `doctor` |
| `claude-plugins.sh` | 期待 plugin リスト（`CLAUDE_LSP_PLUGINS` / `CLAUDE_GENERAL_PLUGINS`）と marketplace 名 + 単一 plugin の installed 判定 | `post-setup` (install) / `doctor` (verify) |
| `brew-autoupdate.sh` | Homebrew autoupdate launchd job の path / 状態判定 / dotfiles baseline 一致判定 | `doctor` / `post-setup` |

責務分割の原則:

- **predicate（読み取り）と mutation（書き込み）を混ぜない**: `claude-checks.sh` は read-only。`ai-config.sh` の `*_upsert_*` / `*_remove_*` は write 専用
- **データ（リスト / 設定値）と処理を分ける**: `claude-plugins.sh` は配列定義が主目的。判定関数は 1 つだけ（`claude_plugin_is_installed`）
- **call site の UI 文言は lib に持たせない**: 各 script が自分のトーン（`ok` / `warn` / `attention` / `fail`）で出力する

## 個別判断ログ

マトリクスでは決まらないケース（同じ機能を提供する複数の経路がある等）の判断記録。同じ議論を繰り返さないため、新規エントリは表の下に追記する（古いものを上、新しいものを下）。

`status` 列の凡例:

- `adopted`: 採用して現在 baseline / コード反映済
- `rejected`: 採用しない判断として確定
- `superseded`: 後の判断で覆された、または状況変化で意味が変わった
- `pending`: 結論ペンディング / trial 中

`adopted` / `rejected` で議論再開の見込みがないものは [`docs/notes/decisions-archive.md`](docs/notes/decisions-archive.md) に切り出して L2 を圧縮している（毎ターン context cost 削減）。古い判断を遡る際はそちらを見る。

| 日付 | status | 判断 | 理由 | 関連 commit/issue |
|---|---|---|---|---|
| 2026-04-25 | adopted | `ai-repair.sh` の hooks block は merge せず wholesale 置換のまま | Claude Code は `settings.json` と `settings.local.json` の hooks を append/concat で merge する（override ではない）ので、baseline を全置換しても user-added hook は失われない。user-added は `settings.local.json` 側に置く運用 | https://code.claude.com/docs/en/hooks.md |
| 2026-04-25 | adopted | `.claude/settings.json` に project-shared な permission allowlist を commit | `fewer-permission-prompts` skill の出力を採用。read-only / inert なものに絞り、書き込み・任意コード実行・retired MCP は除外。`settings.local.json` (gitignored) は machine-local override として残す | `5327658` 系列で追加、本セッション |
| 2026-04-25 | pending | hookify trial 再起動後の smoke test で `rm-rf-home` rule は職能重複と判明（暫定） | `re.search` で command 文字列中どこでもマッチするため `echo "rm -rf $HOME/..."` も誤発火 = false positive。一方 `rm -rf /tmp/...` は Claude Code permission system で先に block されるので、hookify の rm rule は permission と重複して value 低。`git push --force` block / `--force-with-lease` 通過 / `no-verify` warn は permission を通り抜ける slot にあって真の防御線、value 高。hookify の sweet spot は「permission で許可されてる tool の中の特定 pattern だけ止めたい」設計で、rm のように tool 全体が permission で require-approval なものには不要 | smoke test 本セッション、rule 整理は次セッション |
| 2026-04-26 | adopted | Codex retire の cleanup 漏れを解消（`home/dot_codex/` 削除 + `ai-repair.sh` で `~/.codex` 能動削除） | 2026-04 に Codex / Gemini 廃止を宣言した（`docs/notes/current-state.md`）が `home/dot_codex/skills/.../__pycache__/autosave_memory.cpython-314.pyc` の orphan 1 ファイルが残置 → chezmoi が `~/.codex/` を毎 sync 再生成 → `make ai-audit` が「retired agent state still on disk」warn を出し続ける状態。frontend-design 廃止と同じパターン（source 削除 + ai-repair で能動 rm）で収束させた | 本セッション |
| 2026-04-26 | superseded | `effortLevel: "xhigh"` を `~/.claude/settings.json` の dotfiles baseline に追加（旧 policy「local 自由・触らない」を覆す） | Opus 4.7 公式が「ほぼ全タスクで xhigh、最難関だけ max（max は overthinking）」と team-shareable な default を提示。旧 policy 制定時はこの「明確な共有可能 default」が無かった。`/effort` で local 上書きは可能（次の `make ai-repair` で snap back する rewrite-on-repair 方式）。`autoUpdatesChannel` と同じ運用に揃える | 本セッション、Qiita "Opus 4.7でClaude Codeの使い方が180度逆になった" |
| 2026-04-27 | adopted | `effortLevel` baseline を `xhigh` → `high` に降格 | user 確認で routine task に対して xhigh は overthink 寄りと判断（Opus 4.7 公式 default である xhigh は「最難関で max を避ける」基準で設計されており、routine 用途では high で十分）。`xhigh` を要する難タスクは `/effort xhigh` で都度上書きできる（次の `make ai-repair` で `high` に snap back）。snap-back 方式そのものは維持 | 本セッション |
| 2026-04-26 | rejected | プロジェクト側 Stop hook + test 自動実行は dotfiles baseline 化しない（project repo の責務） | `~/.claude/settings.json` の Stop hook は dotfiles 自体の運用 (`auto-save` / `chezmoi-auto-apply`) 専用。記事推奨の `npm test` 自動再実行型 hook は project ごとに test runner / file pattern が違うので project repo の `.claude/settings.json` 側で組む。dotfiles はそのための allowlist (`Bash(make *)` 等) は既に project-shared `.claude/settings.json` に commit 済 | 本セッション、`5327658` 系列 |
| 2026-04-26 | adopted | `home/dot_claude/commands/` を 18 → 3 → 0 本に整理（**全削除**、`commands/` ディレクトリも削除） | E refactor で 3 本残す判断をしたが、user から「コマンド系使ったことない」signal を受けて再評価：slash command は `/<name>` を user が打って初めて Claude が読む = 打たないなら **dead code**。`/perf` `/research` は dead code として削除。`/playwright` の dotfiles 固有部分（CDP attach 時のセキュリティ guardrail）は本来 user invoke を待たず常に守るべき内容なので、**L1 CLAUDE.md の `## ブラウザ自動化のセキュリティ規則（CDP attach 時）` 節としてインライン化**（毎ターン読まれる context へ移動 = dead code から live rule へ昇格）。orphan target は `ai-repair.sh` の retired_command ループで能動削除。`tests/commands.sh` は consumer 消失で削除。 | 本セッション、L1 `43b4fa7` ルール適用 |
| 2026-04-26 | adopted | `security-best-practices` skill を vendor → upstream-install (`npx skills add` from `tech-leads-club/agent-skills`) に移行 | dotfiles 最大の重量物（10 言語別 reference 計 8,005 行 = skills/ subtree の 76%）が「skill 配布優先順位」 tier 3 (vendor) に居座っていた。upstream が `npx skills add` 互換と判明 → tier 2 (upstream CLI 配布) に昇格可能。`gws` / `find-skills` / `notion-cli` と同じ install pattern を `post-setup.sh` に追加。chezmoi は orphan target を自動削除しないため `ai-repair.sh` で legacy vendored copy を能動 rm（marker file `.upstream-installed` 不在で legacy 判定、frontend-design retire と類似パターン） | 本セッション、`tech-leads-club/agent-skills` 確認 |
| 2026-04-26 | adopted | `ui-ux-pro-max` skill を vendor → upstream-install (`nextlevelbuilder/ui-ux-pro-max-skill` v2.5.0) に移行 | 同じ tier-2 pattern。vendored は SKILL.md 658 行 + 16 CSV データファイル + 3 Python script で計 ~1500 行。upstream は active maintenance（2026-03-10 v2.5.0）かつ `npx skills add` 互換。security-best-practices と同じ marker-file 機構で legacy vendored copy 判定 + 自動 re-install | 本セッション、`nextlevelbuilder/ui-ux-pro-max-skill` 確認 |
| 2026-04-26 | adopted | `frontend-design` plugin を baseline 化（`CLAUDE_GENERAL_PLUGINS` に追加） | 2026-04-24 commit `c606583` で vendor 退却したまま、ローカル install / baseline 配列の drift 状態が放置されていた。user が「直近 3-6 ヶ月で Web frontend を書く」確認 → A: baseline 化を選択。`ui-ux-pro-max`（DB 型）と `frontend-design`（aesthetic guideline 型）は厳密に重複しないので併用可 | 本セッション、`scripts/lib/claude-plugins.sh` 編集 |
| 2026-04-26 | adopted | `microsoft-docs` plugin を baseline 化（`CLAUDE_GENERAL_PLUGINS` に追加） | reverse drift（installed_plugins.json には install 済 / `CLAUDE_GENERAL_PLUGINS` 配列に未記載）を frontend-design 対応中に発見。user が「Microsoft tech を扱う」確認 → baseline 化。`microsoft-docs` (search / fetch) / `microsoft-code-reference` (SDK 検証) / `microsoft-skill-creator` (新規 skill scaffolding) の 3 skill を提供。Azure / .NET / M365 / Windows / Power Platform 全般の docs grounding に使う | 本セッション、`scripts/lib/claude-plugins.sh` 編集 |
| 2026-04-26 | adopted | `sequential-thinking` MCP の管理を `post-setup.sh`（一回 install）から `ai-repair.sh`（drift detect-and-repair）+ `ai-audit.sh`（verify）に移管 | 他 4 baseline MCP（vision / exa / jamf-docs / slack）は upsert + verify の対をなすが、`sequential-thinking` だけ「post-setup 一回 install、以降 audit blind」の例外状態。registration が消失しても `make ai-audit` は気付かない = drift 検知の死角。L2 「依存マップ：MCP サーバー追加時は ai-repair / ai-audit / tests を全部更新」原則からも逸脱していた。`ai_config_mcp_registration_state` helper は唯一の consumer 消失で zero-consumer dead code になったため同時除去 | 本セッション |
| 2026-04-26 | adopted | `.claude/settings.json` allowlist に 6 件追加（`Bash(playwright-cli *)` を broad 化、`Bash(npm run dev)` / `Bash(npm test)` exact、`Bash(gitleaks *)`、Gmail MCP 2 種）。既存 `playwright-cli {close,resize,screenshot,goto,open,eval}` 6 entry は残す | `/fewer-permission-prompts` の集計で `--raw snapshot` (52) / `-s=foo eval` (49) / `snapshot` (31) 等が prompt 源泉と判明。L1 の CDP attach guardrails（実 Chrome attach 時の対象範囲制限）が真の防御線で、allowlist 広さと直交するため broad 化で安全側を崩さない。`npm run dev` / `npm test` は **exact のみ**（`npm run *` だと package.json scripts 経由で arbitrary code execution に拡がる skill rule 違反） | 本セッション、`/fewer-permission-prompts` 結果 |
| 2026-04-26 | adopted | Bash から呼べる汎用 CLI 7 種（`gh` / `playwright-cli` / `mmdc` / `marp` / `jq` / `yq` / `pandoc` / `rg` / `ffmpeg`）を L1 ツール選択ルール表で明示「使える前提」化、Brewfile に `marp-cli` / `ffmpeg` を追加 | 8/9 は既に Brewfile or post-setup で install 済だったが L1 表に未掲載のものは Claude が「install されてるか分からないので使わない」分岐を取りがち（`which` で都度確認するだけムダ）。L1 は毎ターン context に乗る = 表に書けば「前提」として常時効く（slash command と違い invoke 不要）。`marp` / `ffmpeg` だけ未 install だったので Brewfile に追加し install と表記載を対で揃えた（L2「依存マップ：CLI 系ツールの追加」運用通り）。`rg` は Claude 内蔵 Grep tool が裏で使うので「Bash 経由で直接叩く必要がある時用」と注記して棲み分け | 本セッション、Claude Code 勉強会 2026-04 スライド p.40 |

## `~/.claude/` 配下の管理モード

同じディレクトリでも管理経路が混在する。新規パスを追加するときは下表のどれかに分類して、編集ルールに従う。分類できない新規パスを足すなら表を更新する。

| パス | 管理モード | 編集ルール |
|---|---|---|
| `~/.claude/CLAUDE.md` / `auto-save.sh` / `chezmoi-auto-apply.sh` / `lsp-hint.sh` / `statusline.sh` | chezmoi end-to-end | `home/dot_claude/` 側を編集すると Stop hook (`chezmoi-auto-apply.sh`) が dotfiles repo 配下の作業時に自動 `chezmoi apply`。手動で同期したい時は `chezmoi apply` / `make sync` |
| `~/.claude/skills/{doc,jupyter-notebook,pdf,presentation,screenshot,spreadsheet}` | chezmoi end-to-end (vendored) | 同上。marketplace に対応 plugin が現れたら plugin 化を検討して vendor を退避 |
| `~/.claude/skills/{security-best-practices,ui-ux-pro-max}` | post-setup install (skill, upstream `npx skills add`) | `scripts/post-setup.sh` の install ブロックを編集。upstream は `tech-leads-club/agent-skills` / `nextlevelbuilder/ui-ux-pro-max-skill`。marker file `.upstream-installed` で legacy vendored copy と区別（vendor → upstream-install 移行は `ai-repair.sh` で能動 rm） |
| `~/.claude/settings.json` の baseline 4 key（`autoUpdatesChannel` / `env.ENABLE_TOOL_SEARCH` / `hooks` / `effortLevel`） | dotfiles baseline | `scripts/ai-repair.sh` の upsert ロジックを編集。実体は Claude Code が rewrite する前提（`/effort` で local 上書き可、`make ai-repair` で high に snap back） |
| `~/.claude/settings.json` のそれ以外（`permissions` / `model` / `statusLine`） | local 自由 | 触らない（Claude Code が rewrite） |
| `~/.claude/skills/{gws-*,find-skills,playwright-cli,notion-cli}` | post-setup install (skill) | `scripts/post-setup.sh` の install 句を編集。`npx skills add` 経由 |
| `~/.claude/plugins/installed_plugins.json` | post-setup install (plugin) | `scripts/lib/claude-plugins.sh` の配列を編集。`claude plugin install` 経由 |
| `~/.claude/projects/` / `history.jsonl` / `sessions/` / `cache/` | 完全 local | 触らない |
| `~/.claude.json`（MCP 登録） | dotfiles baseline | `scripts/ai-repair.sh` の MCP 登録ブロックを編集 |
| `~/.claude/settings.local.json` | 完全 local | マシン固有 override。dotfiles では触らない |

## 整合性ルール

同じ情報が設定 / スクリプト / テスト / ドキュメントに散る構造なので、片側だけ更新すると必ず矛盾する。

- dotfiles ソース（`home/` 以下）が single source of truth。実体（`~/` 以下）だけ変えると次の Claude turn 末（`chezmoi-auto-apply.sh` Stop hook）か手動 `chezmoi apply` で巻き戻る
- chezmoi の命名規則を守る: `dot_` / `executable_` / `.tmpl` / `private_` 等
- credential / token を含むファイル（`hosts.yml` / `auth.json` / `oauth_creds.json` / `.netrc`）は dotfiles に入れない。Keychain に置く
- 廃止時は `ai-repair.sh` で能動的に削除し、`ai-audit.sh` に legacy 警告を追加する。これをやらないと既存マシンが収束しない

## Commit message 規約

`<topic>: <動詞句>` の prefix style。topic は「変更箇所のスコープ」で、git log の前例を踏襲する。

- 既存 prefix の例: `docs` / `ai` / `ai-audit` / `mcp` / `skills` / `playwright-cli` / `pwattach` / `statusline` / `ghostty` / `tests` / `dotfiles`
- スコープが広い改善は repo 名 (`dotfiles:`) を使う
- 詳細・複数項目はコミット本文に bullet で書く（subject は 1 行で要約）
- 末尾に `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`（HEREDOC で渡す）

## 変更箇所の依存マップ

### MCP サーバーの追加・削除・変更

影響範囲が広い。以下をすべて更新する:

- `scripts/ai-repair.sh`（baseline upsert / drift 修復 / 廃止 MCP の能動的削除）
- `scripts/ai-audit.sh`（baseline verify / legacy 警告）
- `tests/ai-repair.sh` / `tests/ai-audit.sh`（clean / drift / legacy 3 scenario すべて）
- 該当 entry が `post-setup.sh` に残っていないか確認（baseline は ai-repair に集約、post-setup での重複登録は責務分離違反）

`~/.claude/.mcp.json` は Claude Code が読まないパスなので絶対に書かない（MCP scope は local=`~/.claude.json` / project=`<project>/.mcp.json` / user=`~/.claude.json` の 3 つだけ）。

### CLI 系ツールの追加（npm global / brew 等）

- `scripts/post-setup.sh`（install）
- `scripts/doctor.sh`（存在確認）
- `home/dot_config/zsh/` の対応モジュール
- `home/dot_local/share/navi/cheats/dotfiles/` の cheat
- `tests/` 配下の回帰テスト

### Claude Code の skill / plugin

- **公式 CLI で配布される** skill（gws / playwright / notion 等）: `scripts/post-setup.sh` が `~/.claude/skills/` に install。dotfiles source には vendor しない
- **plugin marketplace 経由で配布される** plugin（`claude-plugins-official` の `*-lsp` 群と general 群）:
  - 期待リストは `scripts/lib/claude-plugins.sh` の `CLAUDE_LSP_PLUGINS` / `CLAUDE_GENERAL_PLUGINS` に集約。新規追加・削除はここを編集
  - `scripts/post-setup.sh` が両リストを iterate して `claude plugin install <name>@claude-plugins-official` を冪等実行（per-user scope）
  - `scripts/doctor.sh` が同じリストを使って `~/.claude/plugins/installed_plugins.json` 上の有無を検証
  - dotfiles に SKILL.md を vendor しない。upstream が marketplace で rolling update するため、vendor すると drift する

### Claude Code `settings.json` の baseline key 追加・変更

`~/.claude/settings.json` の baseline key を増減・変更するときは以下を全部更新する。一つでも漏らすと L2 / scripts / tests のどこかが嘘になる：

- `scripts/ai-repair.sh`: upsert 句の追加 + 「Claude Code local settings baseline」セクション冒頭の local-managed コメント（baseline / local 境界が動く）
- `scripts/ai-audit.sh`: ok / attention pair の追加
- `scripts/lib/claude-checks.sh`: predicate 関数の追加（`claude_<key>_is_<value>` 形式）
- `CLAUDE.md`（L2）「`~/.claude/` 配下の管理モード」表の baseline 行 / local 行
- `CLAUDE.md`（L2）判断ログに政策変更のエントリ
- `docs/notes/current-state.md` の Claude Code 行
- `tests/ai-repair.sh`: 初期 upsert assertion と、user-override scenario の snap-back / preserve assertion
- `tests/ai-audit.sh`: clean / drift / legacy-MCP の 3 scenario すべてに fixture と assertion

### Claude Code slash command の追加・削除

**新規 slash command は原則追加しない**。2026-04-26 の整理（判断ログ参照）で `home/dot_claude/commands/` は全削除した：(1) user は `/<name>` を invoke する習慣がなく dead code 化しやすい、(2) 本当に毎ターン守らせたい rule は L1 にインライン化する方が確実（slash command は invoke されないと読まれない）、(3) 汎用 methodology は Claude が一般知識として持つ、(4) Office 系等は skill auto-trigger に委ねる。

それでも追加が必要な場合（例：dotfiles 固有の helper が複雑すぎて L1 に収まらない、かつ毎ターンは要らない）：

- L1「Claude Code 標準機能で代替できないか先に確認」を最優先で通す
- 「invoke されないと dead code」前提を意識し、本当に user が打つ運用かを user に直接確認する
- 追加するなら以下を全部更新：
  - `home/dot_claude/commands/<name>.md`（chezmoi end-to-end 管理）
  - `CLAUDE.md`（L2）判断ログにエントリ（user が invoke する確証も書く）

削除するとき：

- `scripts/ai-repair.sh`: retired_command ループの配列に追加（chezmoi は orphan target を自動削除しない）
- `tests/ai-repair.sh`: retired-state scenario の fixture と assertion を更新
- `CLAUDE.md`（L2）判断ログに削除理由
