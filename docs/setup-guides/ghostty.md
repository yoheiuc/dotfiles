# Ghostty 設定

Ghostty の設定は `~/.config/ghostty/` 配下で分割管理している。

| ファイル | 用途 |
|---|---|
| `config.ghostty` | エントリポイント |
| `core.ghostty` | shell integration、scrollback、終了挙動 |
| `ui.ghostty` | フォント、テーマ、padding |
| `keybinds.ghostty` | 追加キーバインド |
| `local.ghostty` | 任意のマシンローカル設定用。git 管理しない |

## GUI で設定を変えた場合

Ghostty の GUI から設定を変更すると、通常は `~/.config/ghostty/*.ghostty` が直接書き換わる。この変更は `chezmoi diff` で検出できる。

```bash
chezmoi diff
chezmoi diff ~/.config/ghostty/config.ghostty
```

運用方針:

- GUI での変更は一時的なローカル差分として扱う
- 残したい変更だけ dotfiles 側へ取り込む
- `chezmoi apply` をすると共通設定で上書きされることがある

## `local.ghostty` について

マシンごとの上書き設定を使いたい場合は、必要なマシンだけ `~/.config/ghostty/local.ghostty` を作成する。

```conf
# ~/.config/ghostty/local.ghostty
font-size = 16
theme = nord
```

Ghostty は存在しない `config-file` を無視せずエラーにするため、`local.ghostty` は共通設定からは自動で読み込まない。本当に使いたいマシンだけ、そのマシンの `~/.config/ghostty/config.ghostty` に次を手で追加する。

```conf
config-file = local.ghostty
```

> この手修正は共通の chezmoi 管理対象ではないため、あとで `chezmoi apply` すると元に戻る可能性がある。恒久化したい場合は dotfiles 側へ取り込むこと。

> Ghostty CLI が `$PATH` に無い場合でも `/Applications/Ghostty.app/Contents/MacOS/ghostty` から実行できる。`doctor.sh` は両方を確認する。
