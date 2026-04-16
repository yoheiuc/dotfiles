#!/usr/bin/env bash
# Claude Code Stop フックから自動呼び出し
# コンテキスト使用率が高い場合にメモリファイルを更新する
set -euo pipefail

# Find the most recently modified memory file for the current project.
# Claude Code stores project memories under ~/.claude/projects/<encoded-path>/memory/.
find_memory_file() {
  local projects_dir="$HOME/.claude/projects"
  [[ -d "${projects_dir}" ]] || return 1

  local workspace_dir
  workspace_dir="$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null || true)"
  [[ -z "${workspace_dir}" ]] && workspace_dir="$PWD"

  # Encode the project path the same way Claude Code does (/ → -)
  local encoded
  encoded="$(printf '%s' "${workspace_dir}" | tr '/' '-')"
  local candidate="${projects_dir}/${encoded}/memory"

  if [[ -d "${candidate}" ]]; then
    # Return the most recently modified .md file
    find "${candidate}" -maxdepth 1 -name '*.md' -type f -print0 2>/dev/null \
      | xargs -0 ls -t 2>/dev/null \
      | head -1
    return
  fi

  return 1
}

INPUT="$(cat || true)"
MEMORY_FILE="$(find_memory_file || true)"
TODAY="$(date '+%Y-%m-%d')"
NOW="$(date '+%Y-%m-%d %H:%M')"

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
description = f"最終自動保存: {now} / dir: {work_dir}"
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
