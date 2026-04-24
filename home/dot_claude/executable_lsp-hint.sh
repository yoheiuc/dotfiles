#!/usr/bin/env bash
# ~/.claude/lsp-hint.sh — PreToolUse advisory hook for Grep.
#
# When an agent uses Grep with a pattern that looks like it's searching
# for a code symbol definition (literal `def ` / `function ` / `class `),
# emit an advisory to stderr suggesting Claude Code's native LSP tool.
# Never blocks (always exit 0). The agent sees the hint and can decide
# whether to switch tools.
#
# Intentionally conservative: only triggers on explicit definition-keyword
# patterns, not generic CamelCase, to avoid misfiring on normal text search.

set -euo pipefail

# stdin is JSON — extract the Grep pattern. jq is the common path; fall back
# to a python one-liner if jq is unavailable (macOS ships without jq by default).
pattern=""
if command -v jq >/dev/null 2>&1; then
  pattern="$(jq -r '.tool_input.pattern // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  pattern="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("pattern",""))' 2>/dev/null || true)"
fi

[[ -z "${pattern}" ]] && exit 0

# Conservative symbol-search heuristics: leading space avoids matching
# substrings like "definitely" / "classifier".
if printf '%s' "${pattern}" | grep -Eq '(^| )(def |function |class |interface |struct |trait |impl )'; then
  cat >&2 <<'EOF'
[lsp-hint] This Grep pattern looks like a code-symbol search.
  Consider the native LSP tool (go-to-definition / find-references / hover)
  instead — LSP returns structured results with no false positives from
  comments or strings. Keep Grep for text search; use LSP for code
  navigation.
EOF
fi

exit 0
