UI/UX design intelligence for web and mobile applications. Covers 10 stacks (React, Next.js, Vue, Svelte, SwiftUI, React Native, Flutter, Tailwind, shadcn/ui, HTML/CSS).

## When to apply
**Must use**: designing pages, creating/refactoring components, choosing color/typography/spacing, reviewing UI for accessibility, implementing navigation/animations, product-level design decisions.
**Skip**: pure backend, API/database design, infrastructure, non-visual scripts.

## Data references
If available, load relevant data from `~/.codex/skills/ui-ux-pro-max/data/`:
- `products.csv` — 161 product types with recommendations
- `colors.csv` — 161 color palettes with accessibility compliance
- `styles.csv` — 50+ design styles with variants
- `typography.csv` — 57 font pairings with stack compatibility
- `design.csv` — design style rules and anti-patterns
- `ux-guidelines.csv` — 99 UX best practices
- `charts.csv` — 25 chart type specifications
- `ui-reasoning.csv` — product -> style -> pattern reasoning rules

## Rule categories by priority

| Priority | Category | Impact | Key Checks |
|----------|----------|--------|------------|
| 1 | Accessibility | CRITICAL | Contrast 4.5:1, alt text, keyboard nav, aria-labels |
| 2 | Touch & Interaction | CRITICAL | Min 44x44px, 8px+ spacing, loading feedback |
| 3 | Performance | HIGH | WebP/AVIF, lazy loading, CLS < 0.1 |
| 4 | Style Selection | HIGH | Match product type, consistency, SVG icons |
| 5 | Layout & Responsive | HIGH | Mobile-first breakpoints, viewport meta, no horizontal scroll |
| 6 | Typography & Color | MEDIUM | 16px base, 1.5 line-height, semantic color tokens |
| 7 | Animation | MEDIUM | 150-300ms duration, meaningful motion, reduced-motion |
| 8 | Forms & Feedback | MEDIUM | Visible labels, error near field, helper text |
| 9 | Navigation | HIGH | Predictable back, bottom nav <=5, deep linking |
| 10 | Charts & Data | LOW | Legends, tooltips, accessible colors |

## Accessibility (CRITICAL)
- Color contrast: 4.5:1 normal text, 3:1 large text
- Focus states: visible 2-4px rings on interactive elements
- Alt text for meaningful images
- aria-labels for icon-only buttons
- Full keyboard navigation, tab order matches visual order
- Sequential heading hierarchy h1->h6
- Don't convey info by color alone
- Support Dynamic Type / system text scaling
- Respect `prefers-reduced-motion`
- Escape routes in modals (cancel/back/close)

## Touch & Interaction (CRITICAL)
- Touch targets: min 44x44pt (Apple) / 48x48dp (Material)
- 8px+ gaps between touch targets
- Use click/tap for primary interactions, don't rely on hover alone
- Loading states on buttons (spinner/progress)
- `cursor-pointer` on clickable elements
- `touch-action: manipulation` to reduce 300ms delay
- Safe area awareness (notch, Dynamic Island, gesture bar)
- Visual press feedback, haptic for confirmations

## Performance (HIGH)
- Use WebP/AVIF for images
- Lazy load below-fold content
- Reserve space for async content (CLS < 0.1)
- Avoid layout thrashing

## Typography & Color (MEDIUM)
- Base font: 16px minimum
- Line height: 1.5
- Use semantic color tokens, not raw hex in components
- No text < 12px for body content
- Avoid gray-on-gray low contrast

## Animation (MEDIUM)
- Duration: 150-300ms
- Motion should convey meaning, not decorate
- Always support `prefers-reduced-motion`
- Never animate width/height directly (use transform)

## Forms & Feedback (MEDIUM)
- Always use visible labels (not placeholder-only)
- Show errors near the field, not only at top
- Progressive disclosure for complex forms
- Helper text for non-obvious fields

$ARGUMENTS
