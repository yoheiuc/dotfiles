#!/bin/bash

set -euo pipefail

input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "Claude"')
project=$(printf '%s' "$input" | jq -r '(.workspace.project_dir // .cwd // "") | split("/") | map(select(length > 0)) | last // ""')

elapsed_ms=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // 0')
elapsed_min=$((elapsed_ms / 60000))

ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
five_used=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_used=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

format_duration() {
  local total_seconds=$1
  if [ "$total_seconds" -le 0 ]; then
    printf 'now'
    return
  fi

  local days hours minutes
  days=$((total_seconds / 86400))
  hours=$(((total_seconds % 86400) / 3600))
  minutes=$(((total_seconds % 3600) / 60))

  if [ "$days" -gt 0 ]; then
    printf '%dd%dh' "$days" "$hours"
    return
  fi

  if [ "$hours" -gt 0 ]; then
    printf '%dh%dm' "$hours" "$minutes"
    return
  fi

  printf '%dm' "$minutes"
}

format_elapsed() {
  local total_minutes=$1
  local hours minutes
  hours=$((total_minutes / 60))
  minutes=$((total_minutes % 60))

  if [ "$hours" -gt 0 ]; then
    printf '%dh%dm' "$hours" "$minutes"
    return
  fi

  printf '%dm' "$minutes"
}

is_unix_timestamp() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

format_window() {
  local label=$1
  local used=$2
  local reset_at=$3

  [ -n "$used" ] || return 0

  local now eta
  now=$(date +%s)
  eta=""
  local remaining
  remaining=$(awk -v used="$used" 'BEGIN { value = 100 - used; if (value < 0) value = 0; printf "%.0f", value }')

  if is_unix_timestamp "$reset_at"; then
    eta=$(format_duration $((reset_at - now)))
  fi

  if [ -n "$eta" ]; then
    printf '%s left %s%% %s' "$label" "$remaining" "$eta"
    return
  fi

  printf '%s left %s%%' "$label" "$remaining"
}

parts=()

parts+=("$model")

if [ -n "$project" ] && [ "$project" != "." ]; then
  parts+=("$project")
fi

five_part=$(format_window "5h" "$five_used" "$five_reset")
if [ -n "$five_part" ]; then
  parts+=("$five_part")
fi

week_part=$(format_window "7d" "$week_used" "$week_reset")
if [ -n "$week_part" ]; then
  parts+=("$week_part")
fi

if [ -n "$ctx_pct" ]; then
  parts+=("ctx $(printf '%.0f' "$ctx_pct")%")
fi

parts+=("$(format_elapsed "$elapsed_min")")

# Session label shown right-aligned. Preference order:
#   1. explicit name fields (user-provided via `claude -n` if ever exposed)
#   2. the auto-generated slug from the transcript (what /resume shows)
#   3. first 8 chars of session_id as last resort
session_label=$(printf '%s' "$input" | jq -r '
  .name // .session.name // .session_name // .display_name // empty
' 2>/dev/null)

if [ -z "$session_label" ]; then
  transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$transcript_path" ] && [ -r "$transcript_path" ]; then
    # Slug is written on nearly every entry; read the tail to keep this cheap.
    session_label=$(tail -n 50 "$transcript_path" 2>/dev/null \
      | grep -oE '"slug":"[^"]+"' \
      | tail -n 1 \
      | sed -E 's/"slug":"([^"]+)"/\1/')
  fi
fi

if [ -z "$session_label" ]; then
  session_id=$(printf '%s' "$input" | jq -r '.session_id // .session.id // empty' 2>/dev/null)
  if [ -n "$session_id" ]; then
    session_label="${session_id:0:8}"
  fi
fi

# Build left side into a string so we can measure width for right-alignment.
left=""
for i in "${!parts[@]}"; do
  if [ "$i" -gt 0 ]; then
    left+=" | "
  fi
  left+="${parts[$i]}"
done

if [ -n "$session_label" ]; then
  cols="${COLUMNS:-}"
  if [ -z "$cols" ]; then
    cols=$(tput cols 2>/dev/null || echo 80)
  fi
  left_len=${#left}
  right_len=${#session_label}
  pad=$((cols - left_len - right_len))
  # Single space if we'd otherwise overflow, so layout stays readable.
  if [ "$pad" -lt 1 ]; then
    pad=1
  fi
  # \e[2m = dim, \e[0m = reset. Session label is secondary info.
  printf '%s%*s\033[2m%s\033[0m\n' "$left" "$pad" '' "$session_label"
else
  printf '%s\n' "$left"
fi
