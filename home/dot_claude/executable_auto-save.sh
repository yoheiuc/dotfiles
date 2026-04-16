#!/usr/bin/env bash
# Claude Code Stop フックから自動呼び出し
# コンテキスト使用率が高い場合にメモリファイルを更新する
set -euo pipefail

MEMORY_FILE="$HOME/.claude/projects/-Users-REDACTED-dotfiles/memory/project_dotfiles_ccb.md"
TODAY="$(date '+%Y-%m-%d')"
NOW="$(date '+%Y-%m-%d %H:%M')"
INPUT="$(cat || true)"

PCT="${CLAUDE_CONTEXT_PERCENT:-}"
if [[ -z "$PCT" ]]; then
  PCT="$(printf '%s' "$INPUT" | jq -r '.context_window.used_percentage // 0 | floor' 2>/dev/null || echo 0)"
fi
if [[ ! "$PCT" =~ ^[0-9]+$ ]]; then
  PCT=0
fi

WORKSPACE_DIR="$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // ""' 2>/dev/null || true)"
if [[ -n "$WORKSPACE_DIR" ]]; then
  WORK_DIR="$(basename "$WORKSPACE_DIR")"
else
  WORK_DIR="$(basename "$PWD")"
fi

# 75% 未満は何もしない
(( PCT < 75 )) && exit 0
[[ -f "$MEMORY_FILE" ]] || exit 0

export MEMORY_FILE TODAY NOW PCT WORK_DIR

python3 - <<'PYEOF'
from pathlib import Path
import os
import re

memory_file = Path(os.environ["MEMORY_FILE"])
today = os.environ["TODAY"]
now = os.environ["NOW"]
pct = os.environ["PCT"]
work_dir = os.environ["WORK_DIR"]

text = memory_file.read_text()

frontmatter_pattern = r"(^---\n.*?^description:\s*)(.*?)(\n.*?^---\n)"
description = f"dotfilesリポジトリをCCB中心に開発中。最終自動保存: {now} / dir: {work_dir}"
if re.search(frontmatter_pattern, text, flags=re.MULTILINE | re.DOTALL):
    text = re.sub(
        frontmatter_pattern,
        lambda m: f"{m.group(1)}{description}{m.group(3)}",
        text,
        count=1,
        flags=re.MULTILINE | re.DOTALL,
    )

section = f"## 自動保存 ({now})\nctx: {pct}% | dir: {work_dir}\n"
section_pattern = rf"\n## 自動保存 \({re.escape(today)}[^\n]*\n(?:.*\n)*?(?=\n## |\Z)"
if re.search(section_pattern, text, flags=re.MULTILINE):
    text = re.sub(section_pattern, f"\n{section}", text, count=1, flags=re.MULTILINE)
else:
    text = text.rstrip() + f"\n\n{section}"

memory_file.write_text(text)
PYEOF
