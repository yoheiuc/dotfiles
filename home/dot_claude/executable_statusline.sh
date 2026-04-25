#!/bin/bash

set -euo pipefail

input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "Claude"')
project=$(printf '%s' "$input" | jq -r '(.workspace.project_dir // .cwd // "") | split("/") | map(select(length > 0)) | last // ""')
worktree=$(printf '%s' "$input" | jq -r '.workspace.git_worktree // empty')

elapsed_ms=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // 0')
elapsed_min=$((elapsed_ms / 60000))

ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty')
thinking=$(printf '%s' "$input" | jq -r '.thinking.enabled // empty')
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
    printf '%s %s%% · %s' "$label" "$remaining" "$eta"
    return
  fi

  printf '%s %s%%' "$label" "$remaining"
}

# 24-bit ANSI helpers (Catppuccin Mocha palette).
RESET=$'\033[0m'
SEP_C=$'\033[38;2;108;112;134m'
MAUVE=$'\033[38;2;203;166;247m'
BLUE=$'\033[38;2;137;180;250m'
LAVENDER=$'\033[38;2;180;190;254m'
TEAL=$'\033[38;2;148;226;213m'
SAPPHIRE=$'\033[38;2;116;199;236m'
GREEN=$'\033[38;2;166;227;161m'
YELLOW=$'\033[38;2;249;226;175m'
PEACH=$'\033[38;2;250;179;135m'
RED=$'\033[38;2;243;139;168m'
PINK=$'\033[38;2;245;194;231m'
ROSEWATER=$'\033[38;2;245;224;220m'

# Color a numeric "used %" — green when low, red when nearing 100.
color_for_used() {
  awk -v u="$1" '
    BEGIN {
      if (u+0 >= 90) print "\033[38;2;243;139;168m";
      else if (u+0 >= 75) print "\033[38;2;250;179;135m";
      else if (u+0 >= 50) print "\033[38;2;249;226;175m";
      else print "\033[38;2;166;227;161m";
    }'
}

# Nerd Font glyphs (escape-notation so they survive editor / clipboard round-trips).
# All from FA4 + Powerline set, which JetBrainsMono Nerd Font v2/v3 both ship.
GLYPH_MODEL=$'󰚩'             # MDI robot (U+F06A9, UTF-8 literal — macOS bash 3.2 lacks \U escape)
GLYPH_FOLDER=$''       # FA folder
GLYPH_BRANCH=$''       # Powerline branch
GLYPH_CLOCK=$''        # FA clock-o
GLYPH_CALENDAR=$''     # FA calendar
GLYPH_CTX=$''          # FA microchip
GLYPH_EFFORT=$''       # FA dashboard / tachometer
GLYPH_THINK=$''        # FA lightbulb-o
GLYPH_ELAPSED=$''      # FA hourglass-half
GLYPH_SEP=$'│'          # box vertical (full cap-height, baselines align with NF icons)

# Determine terminal width — used to decide single line vs 2-line wrap.
# Width source priority: .terminal.width (if Claude Code provides it) → $COLUMNS → tput cols → 200
width=$(printf '%s' "$input" | jq -r '.terminal.width // empty' 2>/dev/null)
[ -z "$width" ] && width="${COLUMNS:-0}"
case "$width" in ''|*[!0-9]*) width=0 ;; esac
[ "$width" -le 0 ] && width=$(tput cols 2>/dev/null || echo 200)

# Group A — identity (who/where).
identity_parts=("${MAUVE}${GLYPH_MODEL}${RESET} ${model}")
if [ -n "$project" ] && [ "$project" != "." ]; then
  if [ -n "$worktree" ]; then
    identity_parts+=("${BLUE}${GLYPH_FOLDER}${RESET} ${project}${SEP_C}(${RESET}${LAVENDER}${GLYPH_BRANCH}${RESET} ${worktree}${SEP_C})${RESET}")
  else
    identity_parts+=("${BLUE}${GLYPH_FOLDER}${RESET} ${project}")
  fi
fi

# Group B — usage / state.
usage_parts=()
five_part=$(format_window "5h" "$five_used" "$five_reset")
[ -n "$five_part" ] && usage_parts+=("${TEAL}${GLYPH_CLOCK}${RESET} ${five_part}")

week_part=$(format_window "7d" "$week_used" "$week_reset")
[ -n "$week_part" ] && usage_parts+=("${SAPPHIRE}${GLYPH_CALENDAR}${RESET} ${week_part}")

if [ -n "$ctx_pct" ]; then
  ctx_color=$(color_for_used "$ctx_pct")
  usage_parts+=("${ctx_color}${GLYPH_CTX}${RESET} ctx $(printf '%.0f' "$ctx_pct")%")
fi

[ -n "$effort" ] && usage_parts+=("${PINK}${GLYPH_EFFORT}${RESET} ${effort}")
[ "$thinking" = "true" ] && usage_parts+=("${YELLOW}${GLYPH_THINK}${RESET}")
usage_parts+=("${ROSEWATER}${GLYPH_ELAPSED}${RESET} $(format_elapsed "$elapsed_min")")

# Join an arbitrary number of parts with the colored vertical separator.
join_parts() {
  local i first=1
  for i in "$@"; do
    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf ' %s%s%s ' "$SEP_C" "$GLYPH_SEP" "$RESET"
    fi
    printf '%s' "$i"
  done
}

# Visible length (strips ANSI escapes; counts UTF-8 codepoints, not bytes).
# bash ${#var} counts codepoints when LC_CTYPE/LANG specifies a UTF-8 locale,
# which we force here so multi-byte Nerd Font glyphs count as 1 each.
visible_len() {
  local LC_ALL=en_US.UTF-8
  local s=$1
  s=$(printf '%s' "$s" | sed $'s/\x1b\\[[0-9;]*m//g')
  printf '%d' "${#s}"
}

single_line=$(join_parts "${identity_parts[@]}" "${usage_parts[@]}")
single_vlen=$(visible_len "$single_line")

if [ "$single_vlen" -le "$width" ]; then
  printf '%s\n' "$single_line"
else
  # Wrap to two lines: identity row, then usage row.
  printf '%s\n' "$(join_parts "${identity_parts[@]}")"
  printf '%s\n' "$(join_parts "${usage_parts[@]}")"
fi
