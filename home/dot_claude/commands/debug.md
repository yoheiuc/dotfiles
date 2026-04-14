Systematic debugging methodology. Follow the structured process below to diagnose and fix the issue.

## Process

### 1. Reproduce
- Get the exact steps, input, and environment that trigger the bug.
- Confirm you can reproduce it. If you can't reproduce it, you can't verify the fix.
- Note: is it 100% reproducible, or intermittent?

### 2. Isolate
- **Narrow the scope**: which file, function, or line? Use binary search (comment out halves) if the codebase is large.
- **Read the error**: stack traces, error messages, and logs are the primary evidence. Read them carefully before guessing.
- **Check recent changes**: `git log --oneline -20`, `git diff HEAD~5`. Did the bug exist before recent changes?
- **Minimal reproduction**: strip away everything unrelated. Can you reproduce in a test?

### 3. Understand
- **Form a hypothesis** before changing code. "I think X happens because Y."
- **Verify the hypothesis** with logging, breakpoints, or a targeted test — not by guessing a fix.
- **Trace the data flow**: follow the actual values through the code path. Where does reality diverge from expectation?
- **Check assumptions**: types, null/undefined, off-by-one, encoding, timezone, race conditions.

### 4. Fix
- **Minimal change**: fix the root cause, not the symptom. Don't refactor while debugging.
- **Write a test** that fails before the fix and passes after. This prevents regression.
- **Verify the fix**: run the reproduction steps. Confirm the bug is gone.
- **Check for collateral damage**: run the full test suite. Did the fix break anything else?

### 5. Reflect
- **Why did this happen?** Could similar bugs exist elsewhere?
- **Why wasn't it caught?** Missing test? Missing validation? Unclear contract?
- **Is a systemic fix warranted?** Type safety, validation layer, better error handling?

## Common bug categories

### State bugs
- Stale state, race conditions, missing initialization
- **Technique**: log state at each transition point, add assertions

### Data flow bugs
- Wrong type, wrong encoding, null where unexpected, off-by-one
- **Technique**: trace values through the call chain, add type checks

### Timing bugs
- Race conditions, deadlocks, stale caches, event ordering
- **Technique**: add timestamps to logs, use synchronization primitives

### Environment bugs
- Works locally, fails in CI/production
- **Technique**: diff environment variables, dependency versions, OS, file paths

### Integration bugs
- API contract mismatch, schema drift, version incompatibility
- **Technique**: compare actual vs expected payloads, check API docs/changelog

## Tools
- **git bisect**: find the commit that introduced the bug.
- **Logging**: strategic `console.log` / `print` / `log.Debug` at decision points.
- **Debugger**: breakpoints for complex state inspection.
- **Network inspector**: chrome-devtools MCP for HTTP/WebSocket issues.
- **Profiler**: chrome-devtools `performance_*` tools for performance bugs.

## Anti-patterns
- Changing code without understanding the root cause.
- "Shotgun debugging" — trying random fixes hoping one works.
- Fixing the symptom (adding a null check) instead of the cause (why is it null?).
- Removing error handling to "fix" the error.
- Debugging in production without reproducing locally first.

$ARGUMENTS
