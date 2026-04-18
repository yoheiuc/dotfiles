# playwright.zsh — Playwright CLI セッション管理ヘルパー
# playwright-cli 未インストール時は静かに no-op。

if ! command -v playwright-cli >/dev/null 2>&1; then
  return 0
fi

# pwsession <name> — セッション名を PLAYWRIGHT_CLI_SESSION に export。
# 以降の playwright-cli / wrapper 呼び出しが同じプロファイルを再利用する。
pwsession() {
  if (( $# != 1 )); then
    echo "usage: pwsession <name>" >&2
    return 1
  fi
  export PLAYWRIGHT_CLI_SESSION="$1"
  echo "PLAYWRIGHT_CLI_SESSION=${PLAYWRIGHT_CLI_SESSION}"
}

# pwlogin <name> <url> — 手動ログイン用に可視ブラウザを --persistent で開く。
# 2FA 含め人間が一度ログインし終えたら閉じる。以降は headless で再利用される。
# 失敗時は PLAYWRIGHT_CLI_SESSION を汚染しない（成功後にだけ export する）。
pwlogin() {
  if (( $# != 2 )); then
    echo "usage: pwlogin <name> <url>" >&2
    return 1
  fi
  local name="$1" url="$2"
  # Canonical argv: --session=<name> before subcommand, subcommand-specific
  # flags (--headed / --persistent) after `open`.
  if playwright-cli --session="${name}" open --headed --persistent "${url}"; then
    export PLAYWRIGHT_CLI_SESSION="${name}"
  else
    local rc=$?
    echo "pwlogin: playwright-cli exited ${rc}; PLAYWRIGHT_CLI_SESSION left unchanged" >&2
    return "${rc}"
  fi
}

# pwlist — 既存セッションの一覧表示。
pwlist() {
  playwright-cli list "$@"
}

# pwshow — ダッシュボード起動（実行中セッションの監視用）。
pwshow() {
  playwright-cli show "$@"
}

# pwkill <name> — 指定セッションの永続データを削除。
pwkill() {
  if (( $# != 1 )); then
    echo "usage: pwkill <name>" >&2
    return 1
  fi
  playwright-cli delete-data --session "$1"
}

# pwkillall — 全 playwright-cli プロセスを強制終了。
pwkillall() {
  playwright-cli kill-all "$@"
}
