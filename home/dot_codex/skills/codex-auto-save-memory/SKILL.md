---
name: codex-auto-save-memory
description: Configure, inspect, and debug automatic Codex memory capture driven by a Stop hook. Use when the user wants Codex to auto-save a compact memory note near the end of long sessions, tune the context-usage threshold, inspect generated memory files, or troubleshoot hook-based autosave behavior.
---

# Codex Auto Save Memory

This skill manages a global `Stop` hook that writes a Markdown memory note when the latest turn's context usage crosses a threshold.

The current implementation reads Codex's `token_count` event from the transcript, compares `last_token_usage.input_tokens / model_context_window`, and updates a per-project memory file under `~/.codex/memories/auto-save/`.

## Quick Start

- Hook config: `~/.codex/hooks.json`
- Hook script: `~/.codex/skills/codex-auto-save-memory/scripts/autosave_memory.py`
- Generated memory files: `~/.codex/memories/auto-save/*.md`
- Default threshold: `0.75`

## Behavior

- The hook runs on every `Stop` event.
- It writes a memory file only when the latest `input_tokens / model_context_window` ratio is greater than or equal to the threshold.
- The file is updated in place per project, so it stays compact instead of growing forever.
- The note stores the latest user prompt, latest assistant message, transcript path, and the measured context usage.

## Limitations

- This is not a native `/compact` hook. It runs at `Stop`.
- The threshold uses transcript token telemetry, not a first-class "current context usage" API.
- The note is deterministic text, not an LLM-generated summary.

## Common Tasks

### Inspect the current autosave setup

- Read `~/.codex/hooks.json`
- Read `~/.codex/config.toml`
- Read `references/behavior.md`
- Check whether `~/.codex/memories/auto-save/` contains recent notes

### Test the hook logic manually

```bash
python3 ~/.codex/skills/codex-auto-save-memory/scripts/autosave_memory.py \
  --transcript-path /path/to/session.jsonl \
  --cwd /path/to/project \
  --session-id test-session \
  --turn-id test-turn \
  --last-assistant-message "Latest assistant message"
```

### Tune the threshold or output location

- Set `CODEX_MEMORY_AUTOSAVE_THRESHOLD` before launching Codex to override the default threshold.
- Set `CODEX_MEMORY_AUTOSAVE_ROOT` to change where autosaved Markdown files are written.

## References

- Hook behavior and file format: `references/behavior.md`
