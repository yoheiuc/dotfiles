#!/usr/bin/env bash
# session-topic.sh — UserPromptSubmit hook that generates a short session
# topic with Haiku and caches to ~/.claude/session-topics/{id}.txt.
# The statusline reads that file so the user sees a meaningful label
# without rerunning the API on every render.
#
# Opt out: set CLAUDE_SESSION_TOPIC=0 in the environment.
#
# Respects /rename: if the transcript already carries .session_name, the
# hook exits — manual names win.
#
# Regenerates on the 1st, 3rd, 5th, 10th, 15th, ... prompt so the topic
# refines as the session evolves without hammering the API.
set -euo pipefail

[ "${CLAUDE_SESSION_TOPIC:-1}" = "0" ] && exit 0
command -v claude >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)
user_prompt=$(printf '%s' "$input" | jq -r '.user_prompt // empty' 2>/dev/null || true)

[ -z "$session_id" ] && exit 0

TOPIC_DIR="${HOME}/.claude/session-topics"
mkdir -p "${TOPIC_DIR}"
TOPIC_FILE="${TOPIC_DIR}/${session_id}.txt"
COUNT_FILE="${TOPIC_DIR}/${session_id}.count"

# Respect a manual /rename — statusline already shows .session_name, so skip.
if [ -n "${transcript_path}" ] && [ -r "${transcript_path}" ]; then
  if grep -q '"session_name"' "${transcript_path}" 2>/dev/null; then
    exit 0
  fi
fi

# Counter: regenerate on 1, 3, 5, 10, 15, 20, ...
count=0
if [ -f "${COUNT_FILE}" ]; then
  count=$(cat "${COUNT_FILE}" 2>/dev/null || printf 0)
fi
count=$((count + 1))
printf '%d' "${count}" > "${COUNT_FILE}"

case "${count}" in
  1|3) ;;
  *)
    if [ $((count % 5)) -ne 0 ]; then
      exit 0
    fi
    ;;
esac

extract_context() {
  local path="$1"
  python3 - "${path}" 2>/dev/null <<'PY'
import json, sys
path = sys.argv[1]
msgs = []
try:
    with open(path) as f:
        for line in f:
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "user":
                continue
            m = d.get("message", {}) or {}
            c = m.get("content", "")
            if isinstance(c, list):
                c = " ".join(
                    x.get("text", "")
                    for x in c
                    if isinstance(x, dict) and x.get("type") == "text"
                )
            if isinstance(c, str):
                s = c.strip()
                if s and not s.startswith("<command-") and not s.startswith("<local-command"):
                    msgs.append(s[:200])
    msgs = msgs[-5:]
    print("\n\n".join(msgs)[:2000])
except Exception:
    pass
PY
}

context=""
if [ -n "${transcript_path}" ] && [ -r "${transcript_path}" ]; then
  context=$(extract_context "${transcript_path}")
fi

if [ -n "${user_prompt}" ]; then
  context="${context}

${user_prompt}"
fi
context=$(printf '%s' "${context}" | head -c 2000)
[ -z "${context}" ] && exit 0

# Fire-and-forget background API call so the hook doesn't delay the prompt.
# --bare skips hooks/LSP/CLAUDE.md discovery so we don't recurse into our
# own hook from the subprocess.
(
  prompt="Summarize the user's session topic in 4-6 English words, title case, no punctuation, no quotes, no prefix, no trailing period. Return only the words.

Session context:
${context}

Topic:"
  topic=$(printf '%s' "${prompt}" | claude -p --bare --model haiku 2>/dev/null | head -n 1)
  topic=$(printf '%s' "${topic}" | tr -d '"`' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
  topic=$(printf '%s' "${topic}" | head -c 80)
  if [ -n "${topic}" ]; then
    printf '%s' "${topic}" > "${TOPIC_FILE}.tmp" && mv "${TOPIC_FILE}.tmp" "${TOPIC_FILE}"
  fi
) </dev/null >/dev/null 2>&1 &
disown

exit 0
