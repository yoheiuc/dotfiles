Systematically refactor code. Change structure without changing behavior.

## Ground rules
- **Tests must pass before AND after**. If there are no tests, write them first for the code being refactored.
- **One refactoring at a time**. Each step should be a working, committable state.
- **No feature changes mixed in**. Refactoring and behavior changes are separate commits.

## Workflow
1. **Understand**: read the code being refactored. Understand its purpose, callers, and edge cases.
2. **Ensure coverage**: verify tests exist for the behavior being preserved. Write them if missing.
3. **Plan the steps**: break the refactoring into small, sequential steps. Each step compiles and tests pass.
4. **Execute step by step**: make one change, run tests, confirm green. Repeat.
5. **Verify**: run the full test suite. Review the diff — did behavior change accidentally?

## Common refactoring patterns

### Extract
- **Extract function**: repeated logic or a long function with a clear sub-task.
- **Extract module/class**: when a file does too many things.
- **Extract constant**: magic numbers or repeated string literals.

### Rename
- **Rename for clarity**: names should describe what, not how. Use the domain language.
- **Use serena MCP** (`mcp__serena__rename_symbol`) for safe cross-file renames.

### Simplify
- **Remove dead code**: unused functions, unreachable branches, commented-out code.
- **Flatten nesting**: early returns to reduce indentation depth.
- **Replace conditional with polymorphism**: when switch/if chains map to types.
- **Inline trivial wrappers**: functions that just call another function without adding value.

### Restructure
- **Move to better home**: function in the wrong file/module.
- **Split large files**: by responsibility, not by arbitrary line count.
- **Consolidate duplicates**: when 3+ copies exist (not 2 — wait for the third).

## Safety techniques
- **Parallel implementation**: build new code alongside old, switch callers one by one, delete old.
- **Feature flags**: for large refactors in production code, gate the new path.
- **Strangler pattern**: gradually replace old system with new, piece by piece.
- **Type system**: use types to enforce the new structure. Compiler errors guide the migration.

## Scope control
- Don't refactor code you're not working on.
- Don't "improve" code style that's consistent within its file.
- Don't add abstractions for hypothetical future needs.
- If a refactoring keeps growing, stop and re-plan.

## Red flags (stop and reconsider)
- Tests are failing and you're not sure why.
- The "simple refactoring" has touched 20+ files.
- You're refactoring and adding features at the same time.
- You don't understand what the original code does.

$ARGUMENTS
