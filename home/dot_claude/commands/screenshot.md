Capture desktop or system screenshots (full screen, specific app/window, or pixel region).

## Tool priority
1. **chrome-devtools MCP** — for screenshots of a live Chrome you're already observing, use `mcp__chrome-devtools__take_screenshot`.
2. **Playwright CLI** — for browser automation screenshots under a persistent session, use `playwright-cli screenshot` (respects `PLAYWRIGHT_CLI_SESSION`).
3. **This command** — for OS-level desktop captures, whole-system screenshots, or when neither of the above fits.

## Save location rules
1. User specifies a path -> save there.
2. User asks without a path -> save to OS default screenshot location.
3. Claude needs a screenshot for inspection -> save to `/tmp/`.

## macOS

### Permission preflight
If the Codex screenshot helper is available, run permission check first:
```bash
bash ~/.codex/skills/screenshot/scripts/ensure_macos_permissions.sh
```

### Python helper (preferred)
```bash
# Full screen to temp
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --mode temp

# Specific app
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --app "Safari" --mode temp

# Pixel region (x,y,w,h)
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --region 100,200,800,600 --mode temp

# Active window
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --active-window --mode temp

# Explicit path
python3 ~/.codex/skills/screenshot/scripts/take_screenshot.py --path output/screen.png
```

### Direct OS commands (fallback)
```bash
# Full screen
screencapture -x output/screen.png

# Pixel region
screencapture -x -R100,200,800,600 output/region.png

# Specific window id
screencapture -x -l<windowId> output/window.png
```

## Linux

Auto-selects first available tool: `scrot` > `gnome-screenshot` > ImageMagick `import`.

```bash
# Full screen
scrot output/screen.png

# Region
scrot -a 100,200,800,600 output/region.png

# Active window
scrot -u output/window.png
```

## Multi-display behavior
- macOS: one file per display when multiple monitors are connected.
- Linux/Windows: virtual desktop in one image; use `--region` to isolate a display.

## After capture
Claude Code can read captured images directly. View and analyze the screenshot to answer the user's question or compare with design references.

$ARGUMENTS
