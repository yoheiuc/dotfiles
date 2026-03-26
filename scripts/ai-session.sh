#!/usr/bin/env bash
set -euo pipefail

# AI session launcher (plain zellij)
if ! command -v zellij >/dev/null 2>&1; then
  echo "ai launcher: zellij が見つかりません (brew install zellij)" >&2
  exit 1
fi

exec zellij
