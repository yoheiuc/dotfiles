# dotfiles

macOS 開発マシンを chezmoi で再現可能に管理する個人 opinionated 設定。Claude Code を中心にした AI 設定 / SaaS 自動化 / credential の Keychain 集約 / drift 自己修復までを 1 リポジトリに閉じ込めている。

採用基準・整合性ルール・依存マップ・判断ログは [`CLAUDE.md`](./CLAUDE.md) に集約してある。新ツール追加・既存置換・廃止のいずれも先にそちらを通す。運用中の状態は [docs/notes/current-state.md](docs/notes/current-state.md)。ライセンスは [MIT](LICENSE)。

> ⚠️ 個人マシン用。`chezmoi apply` は `~/` を上書きする。他人が使うなら fork して [fork して使うとき](#fork-して使うとき) を潰してから apply。

---

## 前提条件

| 項目 | 内容 |
|---|---|
| macOS | 13 Ventura 以降（`vision` MCP が Apple Vision framework を使うため） |
| Homebrew | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Git | Xcode CLT (`xcode-select --install`) または `brew install git` |

git identity は `git config --global user.{name,email}` で持っているならそのまま使える。なければ `cp docs/examples/chezmoidata.yaml .chezmoidata.yaml` して `gitIdentity.{name,email}` を埋める。global `pre-commit` hook が author / committer を `git config --global` と照合し、ズレたら commit を止める。

---

## 初期セットアップ

```bash
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
cd ~/dotfiles

make install         # brew bundle + chezmoi apply + post-setup
exec zsh             # PATH を反映
make doctor          # required 項目が pass することを確認
make preview         # 以降の変更は apply 前に必ず diff 確認
```

### make ターゲット

| ターゲット | 内容 |
|---|---|
| `make status` | 日常 sanity check |
| `make ai-audit` | AI 設定 drift 検出（CI 用は `bash scripts/ai-audit.sh --quiet`） |
| `make ai-repair` | AI 設定 drift 修復（baseline 寄せ + legacy 削除） |
| `make install` | brew bundle + `chezmoi apply` + post-setup |
| `make preview` | `chezmoi diff` + brew preview |
| `make sync` | `chezmoi apply` + brew sync (cleanup あり) + post-setup |
| `make sync PULL=1` | `git pull` してから sync |
| `make doctor` | 深い診断（22 セクション、Required + Optional） |
| `make test` | shell ベース回帰テスト |
| `make tips` | コマンドヒント（zsh では `dothelp` でも可） |
| `make uninstall` | dotfiles を削除 |

新 package は `home/dot_Brewfile` を直接編集 → `make sync` で実体反映 + `brew bundle cleanup`。

---

## 設計思想

「MCP を足すか CLI を足すか何もしないか」「source と実体のどちらを正とするか」「credential をどこに置くか」を、後から迷わないようマトリクスとルールで凍結している。詳細は [`CLAUDE.md`](./CLAUDE.md)。要点だけ:

- **single source of truth は `home/`**（`~/` だけ変えても次の `chezmoi apply` で巻き戻る）
- **credential は Keychain にだけ置く**（`mcp-with-keychain-secret` wrapper 経由で stdio MCP に注入、設定ファイルには参照だけ）
- **drift は `make ai-repair` で baseline に snap back**（Claude `~/.claude.json` / hooks / channel / legacy MCP 削除）
- **AI に見せるアカウントは最小権限**（`pwattach` は AI 専用 Chrome プロファイル強制、Slack/Notion/Workspace の admin アカウントは持ち込まない）
- **迷ったら削除**（dotfiles 肥大化と drift 源を避ける、標準機能で代替できるなら custom 実装しない）

---

## ブラウザ自動化（pwattach のセキュリティ）

`@playwright/cli` の `attach --cdp=chrome` を `pwattach` zsh helper でラップしてある。実 Chrome に CDP 接続してログイン状態のまま AI に操作させる用途。**普段使い Chrome に attach すると Gmail / 銀行 / 業務 admin の全セッションが agent の操作対象になる**ため、dotfiles では AI 専用プロファイルを env var (`PLAYWRIGHT_AI_CHROME_READY=1`) で強制する。

詳細な脅威モデル・運用ルール・初回セットアップ手順は `~/.claude/CLAUDE.md` の「ブラウザ自動化のセキュリティ規則（CDP attach 時）」節（毎ターン Claude が読む context）。`make install` の onboarding メッセージにも 4 ステップが出る。

zsh helper（`home/dot_config/zsh/playwright.zsh`）:

| コマンド | 用途 |
|---|---|
| `pwattach` | 起動中の実 Chrome に CDP attach（`PLAYWRIGHT_CLI_SESSION=chrome` を export） |
| `pwdetach` | attach を切る（Chrome 本体は殺さない） |
| `pwlogin <name> <url>` | `--headed --persistent` で別プロファイル起動（手動ログイン用） |
| `pwlist` / `pwshow` / `pwkill <name>` / `pwkillall` | 永続セッション管理 |

---

## chezmoi の基本運用

```bash
$EDITOR home/dot_config/zsh/aliases.zsh   # 1. repo 側を編集
chezmoi diff                              # 2. 差分確認
chezmoi apply                             # 3. HOME へ反映
chezmoi add ~/.zshrc                      # 4. HOME 側の編集を取り込む
```

巻き戻し:

```bash
git checkout <commit> -- home/dot_config/zsh/tools.zsh
chezmoi apply

git revert HEAD
chezmoi apply
```

---

## Git の privacy guard

`~/.gitconfig` は次を管理:

- `user.name` / `user.email`
- `core.hooksPath = ~/.config/git/hooks`

`~/.config/git/hooks/pre-commit` が author / committer を global config と照合し、ズレたら commit を止める。`GIT_AUTHOR_*` 上書きや repo local config も検査対象。

---

## マシン固有のセットアップガイド

- [gcloud と企業プロキシ（Python 3.13 問題）](docs/setup-guides/gcloud-python-ssl.md) — Netskope / Zscaler 経由で `VERIFY_X509_STRICT` に弾かれる場合の `sitecustomize.py` workaround
- [Ghostty 設定](docs/setup-guides/ghostty.md) — `~/.config/ghostty/` の分割構成、GUI 変更の取り込み
- [仕事用 MCP の setup](docs/work-mcp-setup.md) — Netskope / Microsoft MCP / Jamf 実 tenant / Intune など tenant 固有の MCP（dotfiles 管理外）

---

## ディレクトリ構成

```text
dotfiles/
├── CLAUDE.md                       # 設計思想 / 採用基準 / 整合性ルール / 判断ログ
├── Makefile                        # install / sync / doctor / ai-* / test / uninstall
├── .chezmoiroot                    # "home" を chezmoi source root として指す
├── home/                           # chezmoi source → $HOME
│   ├── dot_Brewfile / dot_zshrc / dot_gitconfig.tmpl / dot_python-version
│   ├── dot_claude/
│   │   ├── CLAUDE.md               # → ~/.claude/CLAUDE.md (毎ターン読まれる L1)
│   │   ├── executable_*.sh         # statusline / auto-save / lsp-hint / chezmoi-auto-apply
│   │   ├── dot_mcp.json            # → ~/.claude/.mcp.json (HTTP MCP baseline)
│   │   └── skills/                 # 同梱 skill (screenshot / doc / pdf / spreadsheet / presentation / jupyter-notebook)
│   ├── dot_local/
│   │   ├── bin/                    # mcp-with-keychain-secret
│   │   ├── lib/python-ssl-compat/  # Python 3.13 VERIFY_X509_STRICT 無効化
│   │   └── share/navi/cheats/dotfiles/
│   └── dot_config/
│       ├── atuin/ gh/ ghostty/ zellij/ starship.toml
│       ├── git/hooks/pre-commit
│       └── zsh/
├── scripts/
│   ├── bootstrap.sh                # SSL compat + brew + chezmoi + apply
│   ├── post-setup.sh               # CLI / skill / stdio MCP 登録、brew-autoupdate 無効化
│   ├── doctor.sh / status.sh / preview.sh / uninstall.sh / dotfiles-help.sh
│   ├── ai-audit.sh / ai-repair.sh / brew-bundle.sh
│   └── lib/{ai-config,brew-autoupdate,claude-checks,claude-plugins,ui}.sh
├── tests/                          # shell ベースの回帰テスト
└── docs/
    ├── notes/current-state.md
    ├── examples/                   # chezmoidata.yaml / envrc.playwright.example
    ├── setup-guides/               # gcloud-python-ssl.md / ghostty.md
    └── work-mcp-setup.md
```

---

## トラブルシューティング

### `make install` 後に CLI が見つからない

`post-setup.sh` は npm global へインストールするが、新しいシェルを開くまで `PATH` に反映されない。

```bash
hash -r
exec zsh
```

### `pwattach` が `PLAYWRIGHT_AI_CHROME_READY=1 が必要` で止まる

意図的な安全策。AI 専用 Chrome プロファイルの初期セットアップを終えてから `~/.zshenv` に `export PLAYWRIGHT_AI_CHROME_READY=1` を追加する。手順は `make install` の onboarding メッセージか `~/.claude/CLAUDE.md` の「ブラウザ自動化のセキュリティ規則」節を参照。

### `gcloud` が `CERTIFICATE_VERIFY_FAILED` で動かない

企業 CASB/プロキシの MITM 証明書が Python 3.13 の `VERIFY_X509_STRICT` で拒否されている。`make doctor` で「VERIFY_X509_STRICT bypass: active」を確認。詳細は [gcloud-python-ssl.md](docs/setup-guides/gcloud-python-ssl.md)。

### `make ai-audit` が legacy MCP / setting を warn する

```bash
make ai-repair    # legacy MCP / drift を全部掃除
make ai-audit     # clean になるはず
```

それでも MCP 接続が直らないときは Claude Code を再起動。

### `chezmoi apply` が source を見つけられない

`bootstrap.sh` は `~/.local/share/chezmoi` をこの repo への symlink にする。手動で clone した場合は symlink を自分で張るか `chezmoi init --source=<path>` を実行。

```bash
ln -s ~/dotfiles ~/.local/share/chezmoi
```

---

## fork して使うとき

fork して自分のマシンに合わせる前提。apply 前に以下を自分で決める:

1. **git identity**: `cp docs/examples/chezmoidata.yaml .chezmoidata.yaml` → `gitIdentity.{name,email}` を差し替え。global config もこの値に合わせる
2. **Brewfile**: `home/dot_Brewfile` は IT 業務 + AI agent 運用前提（IME / password manager / clipboard manager / 2FA / Chrome / 文書変換）。不要 cask は削除
3. **AI agent の取捨**: Claude Code を使わないなら `home/dot_claude/` / `scripts/ai-{repair,audit}.sh` / `post-setup.sh` の対応ブロックを落とす。`make test` が通れば consistent
4. **MCP セット**: 不要 MCP は `home/dot_claude/dot_mcp.json` から削除し、`ai-repair.sh` の baseline と legacy 削除対象を対応させる。新規追加は [`CLAUDE.md`](./CLAUDE.md) のマトリクスを先に通す
5. **terminal / multiplexer / shell**: `home/dot_config/{ghostty,zellij,zsh}` は嗜好が強い領域。fork 先で書き換える前提
6. **routing table**: `home/dot_claude/CLAUDE.md` は agent が毎回読む指示書。自分の運用に書き換える
7. **CI**: `.github/workflows/` は外してある。fork 先で `make test` を叩く 1 行 workflow を追加すれば済む

apply は必ず dry-run から:

```bash
make preview
chezmoi apply -n -v
```

---

## 貢献 / フィードバック

個人 opinionated なので feature request には応えない。歓迎するもの:

- **typo / 事実誤認 / 壊れたリンク**: PR
- **セキュリティ問題**（credential 漏洩、過剰 permission、MITM 等）: Issue（repro 手順つき）
- **設計判断への反論**: [`CLAUDE.md`](./CLAUDE.md) のマトリクス枠組みで書かれた反論は読む。「好み」ベースは読まない
