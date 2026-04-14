Structured technical research using web search. Leverages Exa MCP for high-quality search results.

## Available MCP tools
- `mcp__exa__web_search_exa` — search the web with Exa (optimized for technical content)
- `mcp__exa__web_fetch_exa` — fetch and read a specific URL

## Workflow
1. **Define the question**: what exactly do you need to know? Be specific.
2. **Search**: use `web_search_exa` with targeted queries. Start broad, narrow down.
3. **Read sources**: use `web_fetch_exa` to read promising results in full.
4. **Synthesize**: compare multiple sources. Note agreements, disagreements, and gaps.
5. **Report**: present findings with sources cited.

## Research patterns

### Technology comparison
1. Search for "[A] vs [B]" and "[A] vs [B] [year]" for recent comparisons.
2. Search for "[A] pros cons" and "[B] pros cons" separately.
3. Check official docs for both. Note maturity, community size, maintenance status.
4. Present as a comparison table with clear criteria.

### Best practice / how-to
1. Search for "[topic] best practices [year]" for current guidance.
2. Check official documentation first — it's the authority.
3. Cross-reference with well-known blogs (e.g., engineering blogs from major companies).
4. Distinguish between opinions and established practices.

### Bug investigation
1. Search for the exact error message (in quotes).
2. Check GitHub Issues for the relevant project.
3. Check Stack Overflow for community solutions.
4. Check the project's changelog/release notes for known fixes.

### Library/tool evaluation
1. Check the project's GitHub: stars, last commit, open issues, release frequency.
2. Search for "[library] alternatives" to see the landscape.
3. Check npm/PyPI download trends for adoption signals.
4. Look for security advisories.

## Search query tips
- Use specific technical terms, not natural language.
- Include the year for time-sensitive topics: "React server components 2024".
- Quote exact error messages: `"Cannot read properties of undefined"`.
- Add context: "postgresql connection pooling python" > "database connection pooling".
- Search official docs directly: "site:docs.python.org asyncio".

## Output format
Present research findings as:
```
## Question
[The specific question being researched]

## Summary
[2-3 sentence answer]

## Findings
### [Source 1 title] (URL)
- Key points...

### [Source 2 title] (URL)
- Key points...

## Recommendation
[Actionable recommendation based on findings]
```

## Quality criteria
- **Multiple sources**: don't rely on a single source.
- **Recency**: prefer recent sources for fast-moving topics.
- **Authority**: official docs > established blogs > random articles > forum posts.
- **Specificity**: "use X because Y" is better than "X is popular".
- **Cite everything**: include URLs for all claims.

$ARGUMENTS
