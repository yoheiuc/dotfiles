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

# pwedge [url] — AI 用 Microsoft Edge を headed / persistent / 専用プロファイルで開始。
# L1 (~/.claude/CLAUDE.md) の「ブラウザ自動化の運用デフォルト」節を tooling で再現。
# プロファイル先は PLAYWRIGHT_AI_EDGE_PROFILE で override 可（デフォルト ~/.ai-edge）。
# 失敗時は PLAYWRIGHT_CLI_SESSION を汚染しない（成功後にだけ export する）。
pwedge() {
  local profile="${PLAYWRIGHT_AI_EDGE_PROFILE:-$HOME/.ai-edge}"
  mkdir -p "${profile}"
  if playwright-cli --session=edge open --browser=msedge --headed --persistent --profile="${profile}" "$@"; then
    export PLAYWRIGHT_CLI_SESSION=edge
    osascript -e 'tell application "Microsoft Edge" to activate' >/dev/null 2>&1 || true
    echo "PLAYWRIGHT_CLI_SESSION=edge (Microsoft Edge, headed, profile=${profile})"
  else
    local rc=$?
    echo "pwedge: playwright-cli exited ${rc}; PLAYWRIGHT_CLI_SESSION left unchanged" >&2
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

# playwright-cli — 状態変更系コマンドを ~/.cache/playwright-cli/actions.log に
# TSV 追記する shell wrapper。読み取り系（snapshot / *-list / *-get / console
# 等）はスキップしてログを膨らませない。bypass は `command playwright-cli …`。
playwright-cli() {
  local logdir="${XDG_CACHE_HOME:-$HOME/.cache}/playwright-cli"
  local logfile="${logdir}/actions.log"
  case "$*" in
    *click*|*fill*|*type*|*goto*|*open*|*press*|*keydown*|*keyup*|*upload*|*drag*|*hover*|*select*|*check*|*uncheck*|*cookie-set*|*cookie-delete*|*cookie-clear*|*localstorage-set*|*localstorage-delete*|*localstorage-clear*|*sessionstorage-set*|*sessionstorage-delete*|*sessionstorage-clear*|*state-load*|*tab-close*|*tab-new*|*resize*|*reload*|*go-back*|*go-forward*|*eval*|*run-code*|*route*|*unroute*|*network-state-set*|*delete-data*|*close*)
      mkdir -p "${logdir}"
      printf '%s\tsession=%s\tcwd=%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "${PLAYWRIGHT_CLI_SESSION:-default}" \
        "${PWD}" \
        "$*" >> "${logfile}"
      ;;
  esac
  command playwright-cli "$@"
}
