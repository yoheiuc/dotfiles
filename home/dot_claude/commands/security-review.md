Perform language and framework specific security best-practice reviews. Supported: Python, JavaScript/TypeScript, Go.

## Workflow

1. **Identify languages and frameworks** in scope. Focus on primary core frameworks. For web apps, identify BOTH frontend and backend.
2. **Load reference guides** from `~/.claude/skills/security-best-practices/references/` if available:
   - `python-django-web-server-security.md`
   - `python-fastapi-web-server-security.md`
   - `python-flask-web-server-security.md`
   - `javascript-express-web-server-security.md`
   - `javascript-typescript-nextjs-web-server-security.md`
   - `javascript-typescript-react-web-frontend-security.md`
   - `javascript-typescript-vue-web-frontend-security.md`
   - `javascript-jquery-web-frontend-security.md`
   - `javascript-general-web-frontend-security.md`
   - `golang-general-backend-security.md`
   Read ALL reference files matching the project's stack.
3. **Apply the right mode**:

### Mode 1: Secure-by-default (writing new code)
Use loaded guidance to write secure code from the start.

### Mode 2: Passive detection (while working)
Flag critical vulnerabilities as you encounter them. Focus on highest-impact issues only.

### Mode 3: Full security report (on request)
Produce a comprehensive report:
- Write to `security_best_practices_report.md` (or user-specified location).
- Executive summary at top.
- Organized by severity: Critical > High > Medium > Low.
- Each finding: numeric ID, one-sentence impact, code location with line numbers.
- Offer to fix after user reviews.

## Fixing vulnerabilities
- Fix one finding at a time.
- Add concise comments explaining the security practice and why it matters.
- Consider impact on existing functionality — avoid breaking changes.
- Follow the project's normal commit flow.
- Run existing tests to check for regressions.

## General security guidance

### Avoid incrementing IDs for public resources
Use UUID4 or random hex instead of auto-incrementing IDs for publicly exposed resources.

### TLS considerations
- Don't report lack of TLS as a security issue (dev environments usually lack it).
- Be careful with "secure" cookies — they break non-TLS environments.
- Avoid recommending HSTS without full understanding of impacts.

### Overrides
Respect project documentation that requires bypassing certain practices. When overriding, suggest documenting the reason.

$ARGUMENTS
