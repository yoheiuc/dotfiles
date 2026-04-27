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
# 起動成功後に tab-list を 1 度叩き、AI 専用 profile らしくないタブが見えたら warning。
pwedge() {
  local profile="${PLAYWRIGHT_AI_EDGE_PROFILE:-$HOME/.ai-edge}"
  mkdir -p "${profile}"
  if playwright-cli --session=edge open --browser=msedge --headed --persistent --profile="${profile}" "$@"; then
    export PLAYWRIGHT_CLI_SESSION=edge
    osascript -e 'tell application "Microsoft Edge" to activate' >/dev/null 2>&1 || true
    echo "PLAYWRIGHT_CLI_SESSION=edge (Microsoft Edge, headed, profile=${profile})"
    local tabs
    if tabs="$(command playwright-cli --session=edge tab-list 2>/dev/null)"; then
      if printf '%s' "${tabs}" | grep -iEq 'gmail|mail\.google|admin\.google|accounts\.google|chase|stripe.*dashboard|aws.*console|console\.aws|github\.com/settings|banking|salesforce'; then
        printf '[pwedge guard] tab-list contains URLs that suggest a non-AI profile is loaded. Verify --profile=%s isolation before continuing.\n' "${profile}" >&2
      fi
    fi
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
# TSV 追記し、L1 の禁止 click / eval パターンと session 未設定を機械的に拒否する
# shell wrapper。読み取り系（snapshot / *-list / *-get / console 等）はスキップ。
# bypass は `command playwright-cli …`（state-changing でも guard でも素通し）。
#
# Guards:
#   D. state-changing で PLAYWRIGHT_CLI_SESSION 未設定かつ args に --session が無い
#      → exit 1（cold start を可視化、session 再利用を促す）
#   A. click / dblclick / press の引数が L1 禁止 textContent 正規表現に match
#      → exit 1（誤検知は `command playwright-cli` で素通し可）
#   B. eval / run-code に DOM 書き換え・cookie/storage 書き込み・fetch POST 等
#      → exit 1（読み取り系 textContent / getAttribute 等は素通し）
playwright-cli() {
  local logdir="${XDG_CACHE_HOME:-$HOME/.cache}/playwright-cli"
  local logfile="${logdir}/actions.log"
  local args="$*"
  local is_state_changing=0
  case "${args}" in
    *click*|*dblclick*|*fill*|*type*|*goto*|*open*|*press*|*keydown*|*keyup*|*upload*|*drag*|*hover*|*select*|*check*|*uncheck*|*cookie-set*|*cookie-delete*|*cookie-clear*|*localstorage-set*|*localstorage-delete*|*localstorage-clear*|*sessionstorage-set*|*sessionstorage-delete*|*sessionstorage-clear*|*state-load*|*tab-close*|*tab-new*|*resize*|*reload*|*go-back*|*go-forward*|*eval*|*run-code*|*route*|*unroute*|*network-state-set*|*delete-data*|*close*)
      is_state_changing=1
      ;;
  esac

  if (( is_state_changing )); then
    if [[ -z "${PLAYWRIGHT_CLI_SESSION:-}" && "${args}" != *"--session"* ]]; then
      printf '[playwright-cli guard] no active session; run `pwedge <url>` or `pwsession <name>` first (bypass: `command playwright-cli ...`)\n' >&2
      return 1
    fi

    case "${args}" in
      *click*|*dblclick*|*press*)
        if printf '%s' "${args}" | grep -iEq '削除|delete|remove|cancel|解約|キャンセル|unsubscribe|logout|sign[[:space:]]*out|プラン変更|change[[:space:]]*plan|update.*payment|支払.*変更|save[[:space:]]*changes|apply|変更を保存|更新|送信|submit|購入|subscribe|招待|invite|共有|share|publish|公開'; then
          printf '[playwright-cli guard] forbidden destructive pattern in args: %s\n' "${args}" >&2
          printf '[playwright-cli guard] L1 requires user confirmation for these labels. Bypass with `command playwright-cli ...` if intentional.\n' >&2
          return 1
        fi
        ;;
    esac

    case "${args}" in
      *eval*|*run-code*)
        if printf '%s' "${args}" | grep -Eq 'document\.execCommand|XMLHttpRequest|\.innerHTML[[:space:]]*=|document\.cookie[[:space:]]*=|localStorage\.(setItem|removeItem|clear)|sessionStorage\.(setItem|removeItem|clear)|\.submit\(|\.click\(|method[^a-zA-Z].*(POST|PUT|DELETE|PATCH)'; then
          printf '[playwright-cli guard] forbidden write pattern in eval/run-code: %s\n' "${args}" >&2
          printf '[playwright-cli guard] L1 allows read-only DOM access (textContent / getAttribute / getBoundingClientRect 等). Bypass with `command playwright-cli ...` if intentional.\n' >&2
          return 1
        fi
        ;;
    esac

    mkdir -p "${logdir}"
    printf '%s\tsession=%s\tcwd=%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "${PLAYWRIGHT_CLI_SESSION:-default}" \
      "${PWD}" \
      "$*" >> "${logfile}"
  fi

  command playwright-cli "$@"
}
