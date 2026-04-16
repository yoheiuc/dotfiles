#!/usr/bin/env bash
set -euo pipefail

# AI session launcher — Zellij with AI workspace layout
if ! command -v zellij >/dev/null 2>&1; then
  echo "ai launcher: zellij が見つかりません (brew install zellij)" >&2
  exit 1
fi

SESSION_NAME="ai-${1:-$(basename "$PWD")}"

# Attach to existing session or create new one with AI layout
exec zellij attach "$SESSION_NAME" --create --layout ai
