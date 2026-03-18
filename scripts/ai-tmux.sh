#!/usr/bin/env bash
set -euo pipefail

SESSION="ai"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux attach -t "$SESSION"
  exit 0
fi

tmux new-session -d -s "$SESSION"

# 左=claude (全高), 右上=gemini, 右下=terminal
RIGHT=$(tmux split-window -h -t "$SESSION":0.0 -P -F '#{pane_id}')
TERM_PANE=$(tmux split-window -v -t "$RIGHT" -P -F '#{pane_id}')

tmux send-keys -t "$SESSION":0.0 "claude" C-m
tmux send-keys -t "$RIGHT"       "gemini" C-m

tmux select-pane -t "$SESSION":0.0

tmux attach -t "$SESSION"
