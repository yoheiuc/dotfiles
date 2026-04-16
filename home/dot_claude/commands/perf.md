Performance audit and optimization. Leverages chrome-devtools MCP for web performance analysis.

## Available MCP tools

### Chrome DevTools (for web performance)
- `mcp__chrome-devtools__lighthouse_audit` — full Lighthouse audit (performance, a11y, SEO, best practices)
- `mcp__chrome-devtools__performance_start_trace` — start performance recording
- `mcp__chrome-devtools__performance_stop_trace` — stop and analyze trace
- `mcp__chrome-devtools__performance_analyze_insight` — deep-dive into trace insights
- `mcp__chrome-devtools__take_memory_snapshot` — capture heap snapshot
- `mcp__chrome-devtools__list_network_requests` — inspect network waterfall
- `mcp__chrome-devtools__get_network_request` — inspect individual request details

## Workflow

### Web performance
1. **Lighthouse first**: run `lighthouse_audit` to get a baseline score and prioritized recommendations.
2. **Identify the bottleneck**: is it network, rendering, JavaScript, or server?
3. **Trace**: use `performance_start_trace` / `performance_stop_trace` for detailed runtime analysis.
4. **Network analysis**: use `list_network_requests` to find slow or large requests.
5. **Memory**: use `take_memory_snapshot` if memory leaks are suspected.
6. **Fix and re-measure**: after each optimization, re-run Lighthouse to confirm improvement.

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
