# Behavior

## Trigger

- Event: `Stop`
- Source of usage data: latest `event_msg` with `payload.type == "token_count"` in the transcript
- Threshold formula: `last_token_usage.input_tokens / model_context_window`

## Output

- Directory: `~/.codex/memories/auto-save/`
- File strategy: one Markdown file per project path, updated in place
- Default threshold: `0.75`

## Environment Variables

- `CODEX_MEMORY_AUTOSAVE_THRESHOLD`
- `CODEX_MEMORY_AUTOSAVE_ROOT`
- `CODEX_MEMORY_AUTOSAVE_MAX_SNIPPET_CHARS`

## Note Format

Each generated note contains:

- timestamp
- cwd
- session id / turn id
- measured context usage
- transcript path
- latest user prompt excerpt
- latest assistant message excerpt
