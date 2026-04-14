Write tests for the current project. Detect the framework, follow existing patterns, and ensure meaningful coverage.

## Workflow
1. **Detect the test stack**: look at existing tests, `package.json`, `pyproject.toml`, `go.mod`, `Gemfile`, etc. Match the framework and conventions already in use.
2. **Read existing tests first**: understand naming, directory structure, helper utilities, fixtures, and mocking patterns before writing anything.
3. **Write tests that match the project style**: don't introduce new test libraries or patterns unless asked.
4. **Run the tests**: execute the test suite to confirm they pass. Fix failures before reporting done.

## Test hierarchy
| Level | What it tests | Speed | When to write |
|---|---|---|---|
| Unit | Single function/method in isolation | Fast | Always, for logic with branches or edge cases |
| Integration | Multiple components together | Medium | When units interact with DB, APIs, or file system |
| E2E | Full user workflow | Slow | Critical user paths, smoke tests |

**Default to unit tests** unless the user specifies otherwise or the code under test is primarily integration logic.

## What makes a good test
- **Tests one behavior**: each test has a single assertion focus (may have multiple asserts for that one behavior).
- **Readable name**: describes the scenario and expected outcome. `test_returns_404_when_user_not_found` > `test_get_user_error`.
- **Arrange-Act-Assert**: clear setup, execution, and verification.
- **Independent**: no test depends on another test's state or execution order.
- **Deterministic**: no flaky tests. Mock time, randomness, and external services.
- **Tests behavior, not implementation**: changing internal code should not break tests unless behavior changes.

## Framework-specific patterns

### Python (pytest)
- Use `pytest` conventions: `test_*.py` files, `test_` prefixed functions.
- Use fixtures for setup/teardown. Prefer function-scoped fixtures.
- Use `parametrize` for testing multiple inputs with the same logic.
- Mock with `unittest.mock.patch` or `pytest-mock`.

### JavaScript/TypeScript (Jest / Vitest)
- Use `describe`/`it` blocks for grouping.
- Use `beforeEach`/`afterEach` for setup/teardown.
- Mock with `jest.mock()` or `vi.mock()`.
- For React: use `@testing-library/react`, test user interactions not implementation.

### Go
- Use `*_test.go` files in the same package.
- Use table-driven tests for multiple cases.
- Use `testify` if the project already uses it; otherwise standard `testing` package.
- Use `httptest` for HTTP handler tests.

## Edge cases to consider
- Empty input, nil/null/undefined
- Boundary values (0, 1, max, min)
- Error paths and exception handling
- Concurrent access (if applicable)
- Large inputs / performance limits

## Anti-patterns to avoid
- Testing implementation details (private methods, internal state).
- Excessive mocking that makes tests meaningless.
- Tests that pass when the code is broken (tautological assertions).
- Snapshot tests for logic (only use for UI rendering).
- `sleep`-based timing in async tests (use proper waiting/polling).

$ARGUMENTS
