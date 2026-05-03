# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# dotfiles — Claude Code Notes

このリポジトリで作業する Claude / 自分が読むためのルール集。会話中の振る舞いルール（簡潔に答える、日本語で返す等）と subagent の運用ルール（呼ぶ / 呼ばない判断とモデル振り分け）は `~/.claude/CLAUDE.md`（L1）側にある。

このファイル（L2）が担当するのは「新ツールを足すか / 既存を直すか / 何も足さないか」の判断と、その判断を一貫させるための整合性ルール。詳細リファレンスは `docs/notes/` に分離してある。

## このリポについて（30 秒）

macOS 開発環境（chezmoi で `~/` 以下を管理 + Brewfile + Claude Code 設定）。`home/` 以下が single source of truth。

- 状態確認: `make status` → `make ai-audit` → `make doctor`（深さの順）
- 修復: `make ai-repair`（AI 設定 drift） / `make sync`（実体寄せ + post-setup、`PULL=1` で `git pull origin main` 同梱）
- 全テスト: `make test`。単体テスト 1 本だけは `bash tests/<name>.sh` — 編集箇所別によく叩くのは `bash tests/ai-repair.sh`（MCP / hooks / 廃止 cleanup を変更時）/ `bash tests/post-setup.sh`（plugin / skill install を変更時）/ `bash tests/doctor.sh`（診断項目を変更時）/ `bash tests/playwright-zsh.sh` / `bash tests/bitwarden-zsh.sh`（zsh wrapper 編集時）
- コミット規約は L1 (`~/.claude/CLAUDE.md`) を正本とし、本リポも同じルール。本リポでよく使う commit prefix の例: `docs` / `ai` / `ai-audit` / `mcp` / `skills` / `playwright` / `bitwarden` / `statusline` / `ghostty` / `tests` / `dotfiles`（広いスコープは `dotfiles:`）
- 過去判断 / 新規判断の追記先: [`docs/notes/decisions-archive.md`](docs/notes/decisions-archive.md)（末尾追記、`status` 凡例は archive 冒頭）

詳細・セットアップ手順は `README.md`。

## Architecture (60 秒)

実体管理は 3 層に分かれている:

1. **chezmoi** (`home/` → `~/`): declarative file sync。Stop hook (`home/dot_claude/executable_chezmoi-auto-apply.sh`) が dotfiles repo 配下作業時に毎ターン末で自動 `chezmoi apply`
2. **`scripts/post-setup.sh`**: imperative install (`npm install` / `curl | bash` / `claude plugin install` / `npx skills add`)。冪等。`make install` / `make sync` から呼ばれる
3. **`scripts/ai-repair.sh` + `scripts/ai-audit.sh`**: drift detect-and-repair pair。Claude Code 設定 (`~/.claude.json` の MCP / `~/.claude/settings.json` の baseline 4 key / hooks / 廃止 MCP の能動削除) が外乱で書き換わるのを反復修正

`scripts/doctor.sh` は (1)-(3) と独立した system-wide diagnostic（22 セクション）。read-only。検証ロジックは `scripts/lib/claude-checks.sh` の predicate 群に集約され ai-audit / doctor の 2 caller が共有。`scripts/lib/` の各 lib のヘッダコメントに役割を書いてある。

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

`scripts/lib/` は単一責務で分割（5 本の bash lib `ui.sh` / `ai-config.sh` / `claude-checks.sh` / `claude-plugins.sh` / `brew-autoupdate.sh` + `ai-config.sh` だけが subprocess 呼びする Python backend `ai_config.py`）。新しい共通処理を足すときはどれにも合わなければ新 lib を作る（既存 lib を肥大化させない）。

## `~/.claude/` 配下の管理モード

新規パスの追加・既存パスの管理モード変更は [docs/notes/claude-paths.md](docs/notes/claude-paths.md) の分類表で判断する。

## 整合性ルール

設定 / スクリプト / テスト / ドキュメントに同じ情報が散る構造のため、片側だけ更新すると必ず矛盾する。変更を加えたら `make ai-audit` / `make doctor` / `make test` の 3 種すべて green を確認する。

## やらないこと

頻出アンチパターン。踏むと drift / dead code / cleanup 漏れの原因になる:

- `~/` 以下を直接編集する → 次のターン末で `chezmoi-auto-apply.sh` Stop hook が `home/` から巻き戻す。dotfiles ソース（`home/` 以下）が single source of truth。
- chezmoi 命名規則を破る（`dot_` / `executable_` / `.tmpl` / `private_` の prefix を欠落させる）。
- credential / token を `home/` 配下に入れる → Keychain に置く。`hosts.yml` / `auth.json` / `oauth_creds.json` / `.netrc` 等は dotfiles に commit しない。
- 廃止時に `scripts/ai-repair.sh` の能動削除と `scripts/ai-audit.sh` の legacy 警告を入れ忘れる → chezmoi は orphan target を自動削除しないため、既存マシンが収束しない。
- `~/.claude/.mcp.json` に書く → 公式 MCP scope（`local=~/.claude.json` / `project=<repo>/.mcp.json` / `user=~/.claude.json`）に該当しない dead path。Claude Code は load しない。
- `home/dot_claude/commands/` に新しい slash command を追加 → invoke されないと dead code（archive 2026-04-26）。毎ターン守らせたい rule は L1 (`home/dot_claude/CLAUDE.md`) にインライン化する方が確実。
- `home/dot_claude/skills/` に SKILL.md を vendor → marketplace plugin / `npx skills add` 配布が tier 1-2、vendor は tier 3 の最終手段。tier 1-2 が出現したら都度 vendor 退避。
- user 明示要求なしに `--no-verify` / `git push --force` / `git reset --hard` / `chmod -R` 系の destructive flag を使う（commit 規約 L1）。
- BW_SESSION を `home/` 配下や `~/.zshenv.local` / `.envrc` / `.env` 等の disk に書く（Keychain にも入れない）。`bwunlock` で current shell にだけ短命 export する運用が前提で、長期 background agent から触りたい要件が出たら別計画として再評価する。

## 変更箇所の依存マップ

変更時は対応する checklist を必ず確認する（更新漏れで scripts / tests / docs が矛盾する事故を防ぐ）。詳細は [docs/notes/change-checklist.md](docs/notes/change-checklist.md):

- MCP サーバー → [#mcp](docs/notes/change-checklist.md#mcp)
- Brewfile → [#brewfile](docs/notes/change-checklist.md#brewfile)
- CLI / zsh / cheat → [#cli-zsh](docs/notes/change-checklist.md#cli-zsh)
- skill / plugin → [#skills-plugins](docs/notes/change-checklist.md#skills-plugins)
- `settings.json` baseline key → [#settings-baseline](docs/notes/change-checklist.md#settings-baseline)
- slash command → [#slash-commands](docs/notes/change-checklist.md#slash-commands)
- テスト → [#tests](docs/notes/change-checklist.md#tests)
