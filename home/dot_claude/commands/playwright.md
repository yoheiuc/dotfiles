Automate browser interactions using the Playwright MCP server. For navigation, form filling, screenshots, data extraction, and UI testing.

## Available MCP tools
Claude Code has Playwright MCP tools built-in. Use these directly:

- `mcp__playwright__browser_navigate` — open a URL
- `mcp__playwright__browser_snapshot` — get page accessibility snapshot with element refs
- `mcp__playwright__browser_click` — click element by ref
- `mcp__playwright__browser_fill_form` — fill form fields
- `mcp__playwright__browser_type` — type text
- `mcp__playwright__browser_press_key` — press keyboard key
- `mcp__playwright__browser_hover` — hover over element
- `mcp__playwright__browser_drag` — drag element
- `mcp__playwright__browser_select_option` — select dropdown option
- `mcp__playwright__browser_take_screenshot` — capture screenshot
- `mcp__playwright__browser_evaluate` — execute JavaScript
- `mcp__playwright__browser_file_upload` — upload file
- `mcp__playwright__browser_handle_dialog` — handle alert/confirm/prompt
- `mcp__playwright__browser_navigate_back` — go back
- `mcp__playwright__browser_tabs` — list open tabs
- `mcp__playwright__browser_resize` — resize viewport
- `mcp__playwright__browser_console_messages` — get console output
- `mcp__playwright__browser_network_requests` — get network log
- `mcp__playwright__browser_wait_for` — wait for condition
- `mcp__playwright__browser_run_code` — run Playwright code
- `mcp__playwright__browser_close` — close browser

## Core workflow
1. **Navigate** to the target URL.
2. **Snapshot** to get stable element refs.
3. **Interact** using refs from the latest snapshot.
4. **Re-snapshot** after navigation or significant DOM changes.
5. **Capture** artifacts (screenshot, console logs) when useful.

## When to re-snapshot
- After navigation
- After clicking elements that change UI substantially
- After opening/closing modals or menus
- After tab switches
- When a command fails due to a missing ref

## Common patterns

### Form fill and submit
```
1. browser_navigate -> URL
2. browser_snapshot -> get refs
3. browser_fill_form -> fill fields by ref
4. browser_click -> submit button ref
5. browser_snapshot -> verify result
```

### Visual testing
```
1. browser_navigate -> URL
2. browser_resize -> set viewport
3. browser_take_screenshot -> capture
4. (Read the screenshot to inspect visually)
```

### Data extraction
```
1. browser_navigate -> URL
2. browser_snapshot -> get page structure
3. browser_evaluate -> extract data via JS
```

### Multi-tab work
```
1. browser_tabs -> list tabs
2. browser_navigate -> open new URL (creates tab)
3. browser_tabs -> switch between tabs
```

## Guardrails
- Always snapshot before using element refs.
- Re-snapshot when refs seem stale.
- Prefer MCP tools over `browser_evaluate` for standard interactions.
- Use `browser_evaluate` only when MCP tools can't achieve the goal.
- For browser screenshots, prefer Playwright MCP over OS-level `screencapture`.

$ARGUMENTS
