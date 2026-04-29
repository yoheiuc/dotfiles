# bitwarden.zsh — Bitwarden CLI を AI から read-only で扱うための shell ヘルパー / wrapper
# bw 未インストール時は静かに no-op。
# shellcheck shell=bash

if ! command -v bw >/dev/null 2>&1; then
  return 0
fi

# bwunlock — `bw unlock --raw` で BW_SESSION を取得し current shell に export。
# master password は user が手動で打つ前提（AI/スクリプトは入力しない）。失敗時は
# env を汚染しない（pwlogin と同形の rc handling）。
bwunlock() {
  local session rc
  session="$(command bw unlock --raw)"
  rc=$?
  if (( rc != 0 )); then
    echo "bwunlock: bw unlock exited ${rc}; BW_SESSION left unchanged" >&2
    return "${rc}"
  fi
  if [[ -z "${session}" ]]; then
    echo "bwunlock: empty session token; BW_SESSION left unchanged" >&2
    return 1
  fi
  export BW_SESSION="${session}"
  echo "BW_SESSION exported (length=${#session}). Run 'bwlock' when finished."
}

# bwlock — vault を lock し BW_SESSION を unset。
bwlock() {
  command bw lock >/dev/null 2>&1 || true
  unset BW_SESSION
  echo "vault locked; BW_SESSION unset"
}

# bwstatus — `bw status` を JSON で表示（lock 状態 / serverUrl 確認用）。
bwstatus() {
  command bw status "$@"
}

# bw — read-only allowlist を機械 enforce する wrapper 関数。
# 状態変更系 subcommand は exit 1。bypass は `command bw …`。
# 設計は L1 (~/.claude/CLAUDE.md) の playwright wrapper と同形:
#   - allowlist 外の subcommand は禁止（vault 改変・外部書き出し・HTTP 公開を防ぐ）
#   - 拒否ログを ~/.cache/bitwarden-cli/actions.log に TSV 追記
#   - bypass: `command bw <subcommand> …`（user が明示的に意図したとき）
#
# 同期必須: home/dot_claude/skills/bitwarden-cli/SKILL.md の禁止コマンド表 /
#           tests/bitwarden-zsh.sh の denylist test と allowlist が一致すること。
bw() {
  # 第 1 非フラグ引数 = subcommand を抽出（`bw --help` / `bw --version` のような
  # flag-only 起動を allowlist 通過させるため flag を skip）。
  local sub="" arg
  for arg in "$@"; do
    case "${arg}" in
      -*) continue ;;
      *)  sub="${arg}"; break ;;
    esac
  done

  # フラグだけ（`bw`, `bw --help`, `bw --version`）は bw 本体に丸投げ。
  if [[ -z "${sub}" ]]; then
    command bw "$@"
    return $?
  fi

  # allowlist: read-only 操作 / auth lifecycle / metadata 系。
  case "${sub}" in
    list|get|generate|status|sync|unlock|lock|login|logout|config|completion|update|help)
      command bw "$@"
      return $?
      ;;
  esac

  # denylist (明示): create/edit/delete/restore/share/send/import/export/move/
  # confirm/encode/serve/pending 等。記録してから拒否。
  local logdir="${XDG_CACHE_HOME:-$HOME/.cache}/bitwarden-cli"
  local logfile="${logdir}/actions.log"
  mkdir -p "${logdir}"
  printf '%s\tDENY\tcwd=%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "${PWD}" \
    "$*" >> "${logfile}"

  printf '[bw guard] subcommand "%s" is not in the read-only allowlist.\n' "${sub}" >&2
  printf '[bw guard] allowed: list / get / generate / status / sync / unlock / lock / login / logout / config / completion / update / help\n' >&2
  printf '[bw guard] bypass with `command bw %s` if intentional (state-changing operations require user confirmation).\n' "$*" >&2
  return 1
}
