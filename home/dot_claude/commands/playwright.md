Automate browser interactions using the `playwright-cli` command. For navigation, form filling, screenshots, data extraction, and long-lived authenticated sessions (SaaS admin rounds, ticketing triage, etc.).

## Tool

- CLI: `playwright-cli` (installed globally via `@playwright/cli`)
- Skill: `~/.claude/skills/playwright/` (managed by `playwright-cli install --skills`)
- zsh helpers: `pwsession` / `pwattach` / `pwdetach` / `pwlogin` / `pwlist` / `pwshow` / `pwkill` / `pwkillall`
- Session env var: `PLAYWRIGHT_CLI_SESSION`

Treat this as CLI-first automation. Do NOT pivot to `@playwright/test` unless the user explicitly asks for test files.

## Prerequisite check

```bash
command -v playwright-cli >/dev/null || echo "run ./scripts/post-setup.sh"
```

## Session-aware invocation

If `PLAYWRIGHT_CLI_SESSION` is set in the shell (commonly via `.envrc` + direnv), the zsh wrapper and `playwright-cli` both auto-attach to that persistent profile. Verify with:

```bash
echo "${PLAYWRIGHT_CLI_SESSION:-<none>}"
```

**`PLAYWRIGHT_CLI_SESSION=chrome` is special**: it means the user has already attached to their real running Chrome via `pwattach` (CDP connection, `@playwright/cli` v0.1.8+). Treat that session as an already-logged-in, full-extension Chrome — do NOT `close` / `pwdetach` / `pwkill` it at task end, and do NOT run `pwlogin` on top of it (that would spawn a throwaway persistent profile and defeat the attach).

If unset and the task needs an authenticated SaaS, there are two flows:

- **Use the user's real Chrome** (preferred when cookies / extensions / full browser state matter): ask the user to run `pwattach` first. Requires Chrome 144+ with `chrome://inspect/#remote-debugging` → "Allow remote debugging for this browser instance" toggled ON.
- **Use a throwaway persistent profile** (when you need isolation from the user's main browser): ask the user to run `pwlogin <name> <url>` first (visible browser + manual 2FA), then retry.

## Core workflow

1. Open the page.
2. Snapshot to get stable element refs.
3. Interact using refs from the latest snapshot.
4. Re-snapshot after navigation or significant DOM changes.
5. Capture artifacts (screenshot, pdf, traces) when useful.

```bash
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli click e3
playwright-cli snapshot
```

## When to re-snapshot

- After navigation
- After clicking elements that change UI substantially
- After opening/closing modals or menus
- After tab switches
- When a command fails due to a missing ref

## Common patterns

### Form fill and submit

```bash
playwright-cli open https://example.com/form
playwright-cli snapshot
playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password123"
playwright-cli click e3
playwright-cli snapshot
```

### Screenshot and read back

```bash
playwright-cli screenshot           # saves under output/ or cwd
# then Read the resulting file to inspect visually
```

### Multi-tab work

```bash
playwright-cli tab-new https://example.com
playwright-cli tab-list
playwright-cli tab-select 0
playwright-cli snapshot
```

### Debug a UI flow with traces

```bash
playwright-cli open https://example.com --headed
playwright-cli tracing-start
# ...interactions...
playwright-cli tracing-stop
```

## Session management

- **Task / SaaS per session**: never mix `freshservice` browsing into an `intune-admin` session. Scope creep leaks cookies across blast radii.
- **Never sign in as an admin account** for an AI-used session. Use a read-only / viewer login.
- **First login (persistent profile)**: `pwlogin <name> <url>` pops a visible browser. Human completes 2FA, closes the window. Subsequent headless runs reuse the cookies.
- **Attach to real Chrome**: user runs `pwattach` after toggling `chrome://inspect/#remote-debugging`; session name is `chrome`. Do not `pwlogin` into this — the real Chrome is already logged in.
- **Session expired**: re-run `pwlogin <name> <url>` with the same name — it overwrites in place. For the real-Chrome `chrome` session, user re-logs in via their actual browser.
- **Cleanup**: `pwkill <name>` to delete one persistent profile. `pwdetach` to release the real-Chrome attach without killing Chrome itself. `pwkillall` to purge all running CLI processes (does not close Chrome).
- **Monitor**: `pwshow` opens the dashboard; keep it visible while Claude drives the browser.

## Guardrails

- Always snapshot before referencing element ids (`e12`, etc.).
- Re-snapshot when refs seem stale.
- Prefer explicit commands over `eval` / `run-code` unless no other option.
- Use `--headed` only when a visual check helps — headless is the default.
- Capture artifacts under `output/playwright/`; do not scatter files at repo root.
- Never run an AI-driven session on an admin-privileged account.
- Do not handle PII / regulated data through these sessions.

$ARGUMENTS
