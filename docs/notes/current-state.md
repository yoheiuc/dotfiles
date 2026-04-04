# Current State

- Ghostty は共通設定を控えめに維持し、未対応キーは入れない。
- Ghostty の GUI 変更は `chezmoi diff` で確認し、必要なものだけ dotfiles に取り込む。
- `local.ghostty` は共通設定から自動読込しない。使うマシンだけ手で有効化する。
- `doctor.sh` は誤検知とハングしやすい箇所を修正済みで、required は通る。
- Codex skill は repo 同梱方式に統一済みで、`post-setup.sh` で外部 clone しない。
- 同梱 skill は `playwright`, `screenshot`, `doc`, `pdf`, `spreadsheet`, `jupyter-notebook`, `security-best-practices`。
- Claude Code は `~/.claude/settings.json` と `~/.claude/CLAUDE.md` だけ管理し、履歴や cache は管理しない。
- Gemini CLI は `~/.gemini/settings.json` だけ管理し、認証・履歴・state は管理しない。
- Codex は `~/.codex/config.toml` と `~/AGENTS.md` を管理し、auth や sessions は管理しない。
- Codex には `fast` / `review` / `deep` profile と `cx` / `cxf` / `cxr` / `cxd` / `cxl` alias を入れている。
- 仕事用 / 個人用の切り替えは `~/.config/dotfiles/profile` に保存し、`make preview` / `make update` / `make doctor` はその値を既定で使う。
- README は全面的に日本語化済みで、今の運用方針に合わせて更新済み。
