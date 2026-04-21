Performance audit and optimization. Web performance profiling is done via CLI tools (standalone Lighthouse, `playwright-cli` traces) — the `chrome-devtools` MCP was retired; drive the user's real browser with `playwright-cli attach --cdp=chrome` (`pwattach`) when live traces are needed.

## Web performance tooling

- **Lighthouse** (CLI): `npx lighthouse <url> --view` — full audit (perf / a11y / SEO / best practices). Headless Chrome, JSON / HTML report.
- **`playwright-cli tracing-start` / `tracing-stop`**: capture a runtime trace against the user's attached Chrome (after `pwattach`) or a persistent profile.
- **Browser DevTools by hand**: for one-off deep dives (Performance panel, Memory heap snapshot, Network waterfall), just drive the user's Chrome directly via `pwattach` and let the user inspect the devtools UI.
- **Backend profilers**: language-native (`cProfile` / `py-spy` for Python, `--prof` for Node, `pprof` for Go).

## Workflow

### Web performance
1. **Lighthouse first**: `npx lighthouse <url>` for a baseline score and prioritized recommendations.
2. **Identify the bottleneck**: network, rendering, JavaScript, or server?
3. **Trace**: `pwattach` → `playwright-cli tracing-start` → reproduce the interaction → `tracing-stop`. Inspect via `playwright show-trace <file>`.
4. **Network analysis**: DevTools Network panel in the attached Chrome, or `playwright-cli` network APIs.
5. **Memory**: DevTools Memory panel → heap snapshot, in the attached Chrome.
6. **Fix and re-measure**: re-run Lighthouse after each optimization to confirm improvement.

### Backend performance
1. **Profiling**: use language-specific profilers (Python: `cProfile`/`py-spy`, Node: `--prof`, Go: `pprof`).
2. **Database**: check slow queries, missing indexes, N+1 problems.
3. **Caching**: identify repeated expensive computations or API calls.
4. **Concurrency**: check for blocking I/O, thread pool exhaustion, connection pool limits.

## Core Web Vitals targets
| Metric | Good | Needs improvement | Poor |
|---|---|---|---|
| LCP (Largest Contentful Paint) | ≤ 2.5s | ≤ 4.0s | > 4.0s |
| INP (Interaction to Next Paint) | ≤ 200ms | ≤ 500ms | > 500ms |
| CLS (Cumulative Layout Shift) | ≤ 0.1 | ≤ 0.25 | > 0.25 |

## Common optimizations

### Network
- Compress assets (gzip/brotli)
- Use WebP/AVIF for images
- Lazy load below-fold images and components
- Preload critical resources (`<link rel="preload">`)
- Reduce request count (bundle, sprite, inline critical CSS)
- Use CDN for static assets
- Set proper cache headers

### Rendering
- Avoid layout thrashing (batch DOM reads/writes)
- Use `transform` and `opacity` for animations (GPU-accelerated)
- Reserve space for async content (prevent CLS)
- Use `content-visibility: auto` for long lists
- Defer non-critical JavaScript (`defer`, `async`, dynamic import)

### JavaScript
- Code split (dynamic `import()` at route boundaries)
- Tree shake unused code
- Debounce/throttle expensive event handlers
- Move heavy computation to Web Workers
- Avoid blocking the main thread (long tasks > 50ms)

### Database
- Add indexes for frequent query patterns
- Use `EXPLAIN` / `EXPLAIN ANALYZE` to inspect query plans
- Eliminate N+1 queries (eager load, batch queries, DataLoader)
- Use connection pooling
- Consider read replicas for read-heavy workloads

### Caching
- HTTP cache headers (Cache-Control, ETag)
- Application-level cache (Redis, in-memory)
- Memoization for pure functions with repeated inputs
- Static generation / ISR for content that changes infrequently

## Anti-patterns
- Optimizing before measuring.
- Optimizing code that's not on the hot path.
- Micro-optimizing when the bottleneck is I/O.
- Adding caching without invalidation strategy.
- Premature code splitting that increases request count.

$ARGUMENTS
