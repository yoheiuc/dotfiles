#!/usr/bin/env bash
# dotfiles-help.sh — print common dotfiles workflows and command hints
#
# Usage:
#   ./scripts/dotfiles-help.sh
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ACTIVE_PROFILE="$(bash "${REPO_ROOT}/scripts/profile.sh" get)"

section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

printf '\033[1m=== dotfiles help ===\033[0m\n'
printf 'Active profile: %s\n' "${ACTIVE_PROFILE}"

section "Daily"
printf '  make status       # 今の状態を短く確認\n'
printf '  make ai-audit     # AI 設定だけを詳しく確認\n'
printf '  make preview      # 変更前の確認\n'
printf '  make update       # pull + apply + install (cleanup なし)\n'
printf '  make doctor       # 状態確認\n'

section "Sync"
printf '  make sync         # 現在の profile を cleanup 付きで同期\n'
printf '  make sync-core    # 会社 PC を core に寄せる\n'
printf '  make sync-home    # 自宅 PC を home に寄せる\n'

section "Brew Tracking"
printf '  make brew-diff            # 今の profile とローカル Brew 実体の差分\n'
printf '  make brew-diff-core       # core とローカルの差分\n'
printf '  make brew-diff-home       # home とローカルの差分\n'
printf '  make brew-add-core KIND=brew NAME=jq\n'
printf '  make brew-add-home KIND=cask NAME=google-chrome\n'

section "Profiles"
printf '  dotprofile        # 現在の dotfiles profile を表示\n'
printf '  make sync-core    # profile を core に保存して同期\n'
printf '  make sync-home    # profile を home に保存して同期\n'

section "When Unsure"
printf '  make help         # Make target 一覧\n'
printf '  dothelp           # この案内を再表示\n'
