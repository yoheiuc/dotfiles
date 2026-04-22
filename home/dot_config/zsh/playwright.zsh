# playwright.zsh — Playwright CLI セッション管理ヘルパー
# playwright-cli 未インストール時は静かに no-op。
# shellcheck shell=bash

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

# pwattach — 起動中の実 Chrome に CDP attach し、PLAYWRIGHT_CLI_SESSION=chrome
# を export する。以降このシェルから起動した Claude Code / Codex の
# playwright-cli 呼び出しは、サンドボックス Chromium ではなくユーザーが
# ログイン済みの Chrome を操作する。
#
# ポリシー：AI 専用 Chrome プロファイルでだけ使う（普段使いプロファイルの
# 全ログイン状態を agent に渡してしまうのを避ける）。ユーザー側で
#   1. AI 専用 Chrome プロファイルを作成
#   2. そのプロファイルでだけ chrome://inspect/#remote-debugging の
#      "Allow remote debugging for this browser instance" を ON
#   3. ~/.zshenv に `export PLAYWRIGHT_AI_CHROME_READY=1` を追加
# を済ませた宣言として PLAYWRIGHT_AI_CHROME_READY を見る。
# セット無しだと pwattach は拒否する（事故防止）。
# 失敗時は PLAYWRIGHT_CLI_SESSION を汚染しない（成功後にだけ export する）。
pwattach() {
  if [[ -z "${PLAYWRIGHT_AI_CHROME_READY:-}" ]]; then
    cat >&2 <<'EOF'
pwattach: refusing to run — PLAYWRIGHT_AI_CHROME_READY is not set.
  policy: pwattach must target an AI-dedicated Chrome profile, not your
          everyday browser. Set up once:
    1. create a dedicated Chrome profile (profile picker → "Add")
    2. open chrome://inspect/#remote-debugging in THAT profile and
       toggle "Allow remote debugging for this browser instance" ON
       (keep your main profile's toggle OFF)
    3. add to ~/.zshenv:  export PLAYWRIGHT_AI_CHROME_READY=1
    4. restart the shell and re-run pwattach
  see README.md "pwattach のセキュリティ" for the rationale.
EOF
    return 2
  fi
  if playwright-cli --session=chrome attach --cdp=chrome; then
    export PLAYWRIGHT_CLI_SESSION=chrome
    echo "PLAYWRIGHT_CLI_SESSION=chrome (attached to AI-dedicated Chrome)"
  else
    local rc=$?
    echo "pwattach: playwright-cli exited ${rc}; PLAYWRIGHT_CLI_SESSION left unchanged" >&2
    echo "  check: Chrome 144+, the AI-dedicated profile is foreground, and" >&2
    echo "         chrome://inspect/#remote-debugging is ON in that profile" >&2
    return "${rc}"
  fi
}

# pwdetach — 実 Chrome との attach を切り、PLAYWRIGHT_CLI_SESSION を unset。
# Chrome 本体は殺さない（CDP セッションを閉じるだけ）。
pwdetach() {
  playwright-cli --session=chrome close >/dev/null 2>&1 || true
  unset PLAYWRIGHT_CLI_SESSION
  echo "detached from real Chrome; PLAYWRIGHT_CLI_SESSION unset"
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
