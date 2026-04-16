Create or improve CI/CD pipelines. Default to GitHub Actions unless the project uses another system.

## Workflow
1. **Check existing CI**: look at `.github/workflows/`, `.circleci/`, `Jenkinsfile`, `.gitlab-ci.yml`, `Makefile`, etc.
2. **Match existing conventions**: if CI exists, follow its patterns for naming, structure, and job organization.
3. **Start minimal**: a CI pipeline that runs fast is better than a comprehensive one nobody waits for.
4. **Test locally when possible**: use `act` for GitHub Actions local testing.

## GitHub Actions structure
```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup
        # language-specific setup
      - name: Install dependencies
        # install step
      - name: Lint
        # lint step
      - name: Test
        # test step
```

## Pipeline stages (in order)
| Stage | Purpose | Fail fast? |
|---|---|---|
| Lint | Catch style/formatting issues | Yes |
| Type check | Catch type errors | Yes |
| Unit tests | Verify logic | Yes |
| Build | Confirm it compiles/bundles | Yes |
| Integration tests | Verify component interactions | Yes |
| E2E tests | Verify user flows | Yes (but run last) |
| Deploy | Ship to environment | Only after all above pass |

## Best practices
- **Cache dependencies**: use `actions/cache` or built-in caching (`actions/setup-node` with cache).
- **Parallel jobs**: run lint, type check, and tests in parallel when they don't depend on each other.
- **Fail fast**: put quick checks (lint, type check) first.
- **Pin versions**: use exact action versions (`@v4` minimum, SHA for security-critical).
- **Secrets management**: use GitHub Secrets, never hardcode. Use OIDC for cloud provider auth.
- **Matrix builds**: test across multiple OS/language versions when needed.
- **Timeouts**: set `timeout-minutes` to prevent hung jobs.
- **Concurrency**: use `concurrency` to cancel outdated runs on the same branch.

## Common patterns

### Concurrency control
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

### Dependency caching
```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 20
    cache: 'npm'
```

### Conditional deployment
```yaml
deploy:
  needs: [lint, test, build]
  if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```

### Reusable workflows
For shared CI logic across repos, use `workflow_call` trigger.

## Anti-patterns
- Running all tests sequentially when they could be parallel.
- No caching — every run reinstalls from scratch.
- Deploying without all checks passing.
- Overly complex pipelines that are hard to debug.
- Running CI on every branch push without concurrency control.
- Storing secrets in environment variables in workflow files.

$ARGUMENTS
