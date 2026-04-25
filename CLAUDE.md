# dotfiles — Claude Code Notes

このリポジトリで作業する Claude / 自分が読むためのルール集。会話中の振る舞いルール（簡潔に答える、日本語で返す等）と subagent モデル振り分けは `~/.claude/CLAUDE.md`（L1）側にある。

このファイル（L2）が担当するのは「新ツールを足すか / 既存を直すか / 何も足さないか」の判断と、その判断を一貫させるための整合性ルール。

## このリポについて（30 秒）

macOS 開発環境（chezmoi で `~/` 以下を管理 + Brewfile + Claude Code 設定）。`home/` 以下が single source of truth。

- 状態確認: `make status` → `make ai-audit` → `make doctor`（深さの順）
- 修復: `make ai-repair`（AI 設定 drift） / `make sync`（実体寄せ + post-setup）
- 全テスト: `make test`

詳細・セットアップ手順は `README.md`。

## ツール採用基準

新ツールの追加・置換は以下のマトリクスで方式を決める。迷ったら削除が既定。

| 状況 | 採用方式 | 例 |
|---|---|---|
| 公式 CLI + 公式 skill が揃っている | **CLI + skill**（`scripts/post-setup.sh` で install） | `playwright-cli`、`ntn`、`gws` |
| 公式 CLI なし、公式 remote MCP がある（OAuth 認証） | **remote HTTP MCP**（`dot_mcp.json` に URL のみ） | Slack、Exa、Jamf docs |
| Local stdio MCP に credential を渡す必要がある | `mcp-with-keychain-secret` wrapper 経由で Keychain から注入 | （現状 consumer なし、framework として残置） |
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
| `ui.sh` | `section` / `ok` / `warn` / `info` の出力ヘルパー | `doctor` / `ai-audit` / `ai-repair` / `status` / `post-setup` / `ai-secrets` |
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

| 日付 | 判断 | 理由 | 関連 commit/issue |
|---|---|---|---|
| 2026-04 | `chrome-devtools-mcp` plugin を採用しない | 実 Chrome に attach せず throwaway Chromium を spawn する設計で、`pwattach` 運用と相反 | `2064181` (playwright-cli: adopt attach --cdp=chrome) |
| 2026-04-25 | Exa は HTTP MCP のまま、plugin 化しない | `claude-plugins-official` の `exa` plugin は stdio 版で API key と subprocess が要る → policy「remote MCP > local stdio MCP」と衝突。`web_search_exa` / `web_fetch_exa` の 2 tool で日常用途は足りる | `b21fdcd` (consolidate web search on Exa) |
| 2026-04-25 | `code-review` / `pr-review-toolkit` plugin を採用しない | `/review` `/ultrareview` `/security-review` で同等の用途をカバー済み | `b2ad19e` (install claude-plugins-official) |
| 2026-04-25 | `code-simplifier` plugin を採用しない | 同等の `simplify` skill を vendoring 済み | `b2ad19e` |
| 2026-04-25 | `commit-commands` plugin を採用しない | HEREDOC + Co-Authored-By 等の独自コミット規約と衝突しやすい | `b2ad19e` |
| 2026-04-25 | `superpowers` / `context7` plugin は dotfiles 管理外 | 必要時にセッション内 `/plugin install` で個別投入。dotfiles 必須セットには含めない | README.md に明文 |
| 2026-04-25 | `shfmt` を Brewfile に追加しない | `shellcheck` で実害は止まる。personal repo で style 揺れの実害なし。L2 policy「迷ったら削除」に該当 | （本セッションでの判断、commit なし） |
| 2026-04-25 | `ai-repair.sh` の hooks block は merge せず wholesale 置換のまま | Claude Code は `settings.json` と `settings.local.json` の hooks を append/concat で merge する（override ではない）ので、baseline を全置換しても user-added hook は失われない。user-added は `settings.local.json` 側に置く運用 | https://code.claude.com/docs/en/hooks.md |
| 2026-04-25 | `.claude/settings.json` に project-shared な permission allowlist を commit | `fewer-permission-prompts` skill の出力を採用。read-only / inert なものに絞り、書き込み・任意コード実行・retired MCP は除外。`settings.local.json` (gitignored) は machine-local override として残す | `5327658` 系列で追加、本セッション |
| 2026-04-25 | Jamf 公式 docs MCP (`https://developer.jamf.com/mcp`) を baseline 化、`jamf-mcp-server` (実 tenant 操作) は保留 | Jamf Pro を業務利用しているが、まず無認証 read-only な公式 docs MCP で API 仕様検索を加速。実 tenant 操作 MCP は credential + Keychain wrapper の運用判断（read-only mode 可否、最小権限 API client 発行）を経てから次セッションで判断 | 本セッション |
| 2026-04-25 | 業務 SaaS の MCP（Netskope / Microsoft MCP for Enterprise / Jamf 実 tenant / Intune）は dotfiles baseline に乗せず手順だけ集約 | tenant URL / access code / API token が tenant 固有で共有不可。`mcp-with-keychain-secret` wrapper の framework は維持、実 install は手順を見て user 判断 | 本セッション、L2 「仕事用 MCP の setup 手順」セクション |
| 2026-04-25 | `revise-claude-md` slash command を Stop hook 化しない（手動 `/revise-claude-md` 運用のまま） | Stop hook 適性 = ①LLM 不要 ②冪等 ③高速 ④user approval 不要、の 4 条件。`chezmoi-auto-apply` は全部満たす（chezmoi apply は決定論的 sync）が、`revise-claude-md` は LLM 必須・reflection 含む・step 5 で approval 要求の 5 ステップ command。Stop で LLM を回すと再帰問題もある（hook 内 session の Stop でまた hook…）。`auto-save` は memory rewrite で similar 構造だが context >75% の rate-limit があるから成立している | claude-plugins-official の `claude-md-management/commands/revise-claude-md.md` を確認、本セッション |
| 2026-04-25 | `session-report` plugin を baseline 化しない（必要時に bundle 内 `analyze-sessions.mjs` を直接叩く） | 集計粒度は `subagent_type` 単位で、`Agent({model: ...})` 別 breakdown を持たないため subagent モデル振り分け効果の検証という当初目的にはギャップ。週次〜月次 review 用途は `node ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/session-report/skills/session-report/analyze-sessions.mjs --json --since 7d` で足りる（plugin install すら不要）。baseline 化の閾値「毎回欲しいか」を満たさない | 本セッションで実行・確認 |
| 2026-04-25 | `hookify` plugin を per-user で install、dotfiles `.claude/hookify.*.local.md` に 4 rule 配置（trial、結論ペンディング） | rule ファイルは `.local.md` 慣例で gitignored（`.gitignore` に `.claude/hookify.*.local.md` 追加済み）。block: `rm -rf $HOME\|/`, `git push --force`。warn: `git reset --hard`, `--no-verify` / `--no-gpg-sign`。pretooluse.py は try/except で常に exit 0 = エラー時も操作を block しない安全側。**Claude 再起動で活性化**。次セッションで rule 誤発火 / 漏れを観察してから baseline 化（`scripts/lib/claude-plugins.sh` の配列追加）を判断。cwd 依存設計のため他 project に展開するなら template 化が要る | 本セッションで install + rule 配置 |
| 2026-04-25 | hookify trial 再起動後の smoke test で `rm-rf-home` rule は職能重複と判明（暫定） | `re.search` で command 文字列中どこでもマッチするため `echo "rm -rf $HOME/..."` も誤発火 = false positive。一方 `rm -rf /tmp/...` は Claude Code permission system で先に block されるので、hookify の rm rule は permission と重複して value 低。`git push --force` block / `--force-with-lease` 通過 / `no-verify` warn は permission を通り抜ける slot にあって真の防御線、value 高。hookify の sweet spot は「permission で許可されてる tool の中の特定 pattern だけ止めたい」設計で、rm のように tool 全体が permission で require-approval なものには不要 | smoke test 本セッション、rule 整理は次セッション |
| 2026-04-26 | Codex retire の cleanup 漏れを解消（`home/dot_codex/` 削除 + `ai-repair.sh` で `~/.codex` 能動削除） | 2026-04 に Codex / Gemini 廃止を宣言した（`docs/notes/current-state.md`）が `home/dot_codex/skills/.../__pycache__/autosave_memory.cpython-314.pyc` の orphan 1 ファイルが残置 → chezmoi が `~/.codex/` を毎 sync 再生成 → `make ai-audit` が「retired agent state still on disk」warn を出し続ける状態。frontend-design 廃止と同じパターン（source 削除 + ai-repair で能動 rm）で収束させた | 本セッション |
| 2026-04-26 | `presentation` skill を vendor 追加して Office 3 点セット (.docx/.xlsx/.pptx) + .pdf を揃える。SKILL.md は自作（既存 `doc` / `spreadsheet` と同じトーン、python-pptx + LibreOffice rendering） | `anthropics/skills@pptx` は LICENSE で「retain copies outside the Services」「create derivative works」が禁止なので vendor 不可。`claude-plugins-official` marketplace にも `pptx` plugin は無く、`openai/skills` の `.curated/` 旧 set からも消えていた。community skill (`tfriedel/...` / `claude-office-skills/...`) は配布元の継続性が読めない。**既存 `doc` / `spreadsheet` の flavor で minimal な SKILL.md を自作** が license 問題ゼロ・lineage 統一・依存も既存の python-* + LibreOffice + Poppler に揃う最善解 | 本セッション |

## `~/.claude/` 配下の管理モード

同じディレクトリでも管理経路が混在する。新規パスを追加するときは下表のどれかに分類して、編集ルールに従う。分類できない新規パスを足すなら表を更新する。

| パス | 管理モード | 編集ルール |
|---|---|---|
| `~/.claude/CLAUDE.md` / `auto-save.sh` / `chezmoi-auto-apply.sh` / `lsp-hint.sh` / `statusline.sh` / `commands/` / `.mcp.json` | chezmoi end-to-end | `home/dot_claude/` 側を編集すると Stop hook (`chezmoi-auto-apply.sh`) が dotfiles repo 配下の作業時に自動 `chezmoi apply`。手動で同期したい時は `chezmoi apply` / `make sync` |
| `~/.claude/skills/{doc,jupyter-notebook,pdf,presentation,screenshot,security-best-practices,spreadsheet,ui-ux-pro-max}` | chezmoi end-to-end (vendored) | 同上。marketplace に対応 plugin が現れたら plugin 化を検討して vendor を退避 |
| `~/.claude/settings.json` の baseline 3 key（`autoUpdatesChannel` / `env.ENABLE_TOOL_SEARCH` / `hooks`） | dotfiles baseline | `scripts/ai-repair.sh` の upsert ロジックを編集。実体は Claude Code が rewrite する前提 |
| `~/.claude/settings.json` のそれ以外（`permissions` / `model` / `effortLevel` / `statusLine`） | local 自由 | 触らない（Claude Code が rewrite） |
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

## 仕事用 MCP の setup 手順（dotfiles 管理外、必要時に install）

業務利用する SaaS の MCP は **tenant URL / access code / API token** がそれぞれの環境固有なので dotfiles baseline に乗らない。L2 採用判断は「使う時が来たら setup、判断ログにマシン install を記録」。手順だけ集約しておく。

### 共通: Keychain wrapper の使い方

dotfiles に framework 残置済みの `~/.local/bin/mcp-with-keychain-secret`（service: `dotfiles.ai.mcp`）を介して、stdio MCP に env var を注入する。手順:

```bash
# 1. Keychain にトークン保存
security add-generic-password -U -s dotfiles.ai.mcp -a <account> -w '<secret>'

# 2. ~/.claude.json に MCP 登録（手で or claude mcp add 経由）
# wrapper が <account> を読んで env var <ENV_NAME> として stdio コマンドに渡す
{
  "mcpServers": {
    "<name>": {
      "type": "stdio",
      "command": "/Users/<you>/.local/bin/mcp-with-keychain-secret",
      "args": ["<ENV_NAME>", "dotfiles.ai.mcp", "<account>", "npx", "mcp-remote", "<remote-url>"]
    }
  }
}
```

remote HTTP MCP に header で token を渡す native pattern もあるが、Claude Code 起動時の env に `<ENV_NAME>` がないと動かない。Keychain wrapper の方が「起動環境 free」で堅牢。

### Netskope MCP（hosted preview）

- 公式 hosted: `https://mcp-preview.goskope.com/{tenant}/{access_code}/mcp`
- tools: 70+（セキュリティアラート / インシデント / DLP / CCI / Network / ポリシー）
- 必要: tenant subdomain (`<tenant>.goskope.com`) + 6-char access code + Netskope API V2 Bearer token（Application/Page/Alert/Incident/Client/Network datasearch + CCI + Incidents 権限）

setup:

```bash
# Keychain にトークン保存
security add-generic-password -U -s dotfiles.ai.mcp -a netskope-api-token -w '<TOKEN>'

# claude mcp add（半 credential な URL は手で組む）
claude mcp add --transport http --scope user netskope \
  https://mcp-preview.goskope.com/<TENANT>/<ACCESS_CODE>/mcp \
  --header "Authorization: Bearer ${NETSKOPE_API_TOKEN}"

# Claude Code 起動前に env で読み込む（zshrc に追加 or ai-secrets.env に書く）
export NETSKOPE_API_TOKEN="$(security find-generic-password -w -s dotfiles.ai.mcp -a netskope-api-token)"
```

注意: tenant URL / access code 自体も半 credential なので `~/.claude.json`（dotfiles 管理外）に置く。git に commit しない。

### Microsoft MCP for Enterprise (Entra ID 公式 read-only)

- 公式 hosted: `https://mcp.svc.cloud.microsoft/enterprise`
- tools: Entra ID admin (users / groups / devices / apps / sign-in audit / 条件付きアクセス) + 基本 device readiness（Intune の compliance 状態）
- 必要: Entra テナントで MCP Client app 登録 + admin consent + redirect URI 設定 + PowerShell module `Microsoft.Entra.Beta` で `Grant-EntraBetaMCPServerPermission`

setup（簡略）:

```powershell
# Windows / PowerShell（Entra admin 権限で実行）
Install-Module Microsoft.Entra.Beta -RequiredVersion 1.0.13
Connect-Entra
# 自分の MCP Client app を登録 → 取得した clientId を渡す
Grant-EntraBetaMCPServerPermission -ClientId <YOUR_MCP_CLIENT_APP_ID>
```

```bash
# Claude Code 側 (~/.claude.json)
{
  "mcpServers": {
    "ms-enterprise": {
      "type": "http",
      "url": "https://mcp.svc.cloud.microsoft/enterprise",
      "oauth": { "clientId": "<your-mcp-client-app-id>", "callbackPort": <port> }
    }
  }
}
```

注意: ChatGPT / Claude は **custom client ID 必須**（公式デフォルトの VS Code 用 ID は使えない）。tenant ごとに app 登録が要る。

### Jamf Pro 実 tenant 操作 (`dbankscard/jamf-mcp-server`)

- 公式の docs MCP は別物（既に baseline 化済）。これは **実 Jamf Pro tenant への操作**用
- read-only mode で運用するのが安全（`JAMF_READ_ONLY=true`）
- 必要: Jamf Pro API client (CLIENT_ID + CLIENT_SECRET)、最小権限を割り当て

setup:

```bash
# Keychain
security add-generic-password -U -s dotfiles.ai.mcp -a jamf-client-id -w '<ID>'
security add-generic-password -U -s dotfiles.ai.mcp -a jamf-client-secret -w '<SECRET>'

# Node 版を local clone（or npm 化されたら直 npx）
git clone https://github.com/dbankscard/jamf-mcp-server ~/src/jamf-mcp-server
cd ~/src/jamf-mcp-server && npm install && npm run build

# ~/.claude.json — 2 段 wrapper（CLIENT_ID と CLIENT_SECRET 両方注入）
{
  "mcpServers": {
    "jamf": {
      "type": "stdio",
      "command": "bash",
      "args": ["-lc",
        "JAMF_CLIENT_ID=$(security find-generic-password -w -s dotfiles.ai.mcp -a jamf-client-id) \
         JAMF_CLIENT_SECRET=$(security find-generic-password -w -s dotfiles.ai.mcp -a jamf-client-secret) \
         JAMF_URL=https://<tenant>.jamfcloud.com \
         JAMF_READ_ONLY=true \
         node /Users/<you>/src/jamf-mcp-server/dist/index-main.js"
      ]
    }
  }
}
```

write 解禁する場合は `JAMF_READ_ONLY=false` にする前に判断ログへ書く。

### Intune 専用 MCP

- 公式版 (Microsoft MCP for Enterprise) で **基本 device readiness は covered**。専用 MCP は機能ギャップ次第
- community 候補: `pamontag-org-ghe/intune-mcp-server`（最小、Azure Container Apps self-host） / PowerShell.MCP（local PowerShell session 経由で Graph PowerShell）
- 採用判断: 公式 MCP for Enterprise を install して足りない部分を測ってから

## Commit message 規約

`<topic>: <動詞句>` の prefix style。topic は「変更箇所のスコープ」で、git log の前例を踏襲する。

- 既存 prefix の例: `docs` / `ai` / `ai-audit` / `mcp` / `skills` / `playwright-cli` / `pwattach` / `statusline` / `ghostty` / `tests` / `dotfiles`
- スコープが広い改善は repo 名 (`dotfiles:`) を使う
- 詳細・複数項目はコミット本文に bullet で書く（subject は 1 行で要約）
- 末尾に `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`（HEREDOC で渡す）

## 変更箇所の依存マップ

### MCP サーバーの追加・削除・変更

影響範囲が広い。以下をすべて更新する:

- `home/dot_claude/dot_mcp.json`（HTTP MCP 登録）
- `scripts/ai-repair.sh`（drift 修復 / 廃止 MCP の能動的削除）
- `scripts/ai-audit.sh`（legacy 警告）
- `scripts/ai-secrets.sh`（credential が必要な場合）
- `README.md` の「MCP の基本セット」
- 関連する `home/dot_claude/commands/*.md`
- `tests/` 配下の対応テスト

### CLI 系ツールの追加（npm global / brew 等）

- `scripts/post-setup.sh`（install）
- `scripts/doctor.sh`（存在確認）
- `home/dot_config/zsh/` の対応モジュール
- `home/dot_local/share/navi/cheats/dotfiles/` の cheat
- 関連する `home/dot_claude/commands/*.md`
- `README.md`
- `tests/` 配下の回帰テスト

### Claude Code の skill / plugin

- **公式 CLI で配布される** skill（gws / playwright / notion 等）: `scripts/post-setup.sh` が `~/.claude/skills/` に install。dotfiles source には vendor しない
- **plugin marketplace 経由で配布される** plugin（`claude-plugins-official` の `*-lsp` 群と general 群）:
  - 期待リストは `scripts/lib/claude-plugins.sh` の `CLAUDE_LSP_PLUGINS` / `CLAUDE_GENERAL_PLUGINS` に集約。新規追加・削除はここを編集
  - `scripts/post-setup.sh` が両リストを iterate して `claude plugin install <name>@claude-plugins-official` を冪等実行（per-user scope）
  - `scripts/doctor.sh` が同じリストを使って `~/.claude/plugins/installed_plugins.json` 上の有無を検証
  - dotfiles に SKILL.md を vendor しない。upstream が marketplace で rolling update するため、vendor すると drift する
  - README の該当節も同期して更新
