#!/usr/bin/env bash
# dotfiles-help.sh — print common dotfiles workflows and command hints
#
# Usage:
#   ./scripts/dotfiles-help.sh
set -euo pipefail

section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

printf '\033[1m=== dotfiles help ===\033[0m\n'

section "Daily"
printf '  make status       # 今の状態を短く確認\n'
printf '  make ai-audit     # AI 設定だけを詳しく確認\n'
printf '  make preview      # 適用前の差分確認\n'
printf '  make doctor       # 状態の深い確認\n'

section "Sync"
printf '  make sync         # chezmoi apply + brew sync (cleanup 付き) + post-setup\n'
printf '  make sync PULL=1  # git pull してからフル同期\n'

section "Brew tracking"
printf '  Brewfile を直接編集: home/dot_Brewfile\n'
printf '  chezmoi apply → make sync で反映\n'

section "When unsure"
printf '  make help         # Make target 一覧\n'
printf '  dothelp           # この案内を再表示\n'
