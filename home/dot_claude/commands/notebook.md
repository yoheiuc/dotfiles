Create clean, reproducible Jupyter notebooks for experiments or tutorials.

## When to use
- Create a new `.ipynb` notebook from scratch.
- Convert rough notes or scripts into a structured notebook.
- Refactor an existing notebook to be more reproducible and skimmable.

## Decision tree
- **Exploratory / analytical / hypothesis-driven** -> `experiment` pattern
- **Instructional / step-by-step / audience-specific** -> `tutorial` pattern
- **Editing an existing notebook** -> preserve intent and improve structure

## Workflow
1. **Lock the intent**: identify the notebook kind (experiment or tutorial). Capture objective, audience, and what "done" looks like.
2. **Scaffold**: if the helper script is available, use it:
   ```bash
   export JUPYTER_NOTEBOOK_CLI="$HOME/.claude/skills/jupyter-notebook/scripts/new_notebook.py"
   uv run --python 3.12 python "$JUPYTER_NOTEBOOK_CLI" --kind experiment --title "Title" --out output/jupyter-notebook/file.ipynb
   ```
   Otherwise, create the notebook JSON structure directly.
3. **Fill with small, runnable cells**: one step per code cell. Add short markdown cells explaining purpose and expected result.
4. **Apply the right pattern**:
   - Experiments: hypothesis -> setup -> execution -> analysis -> conclusion
   - Tutorials: context -> concepts -> guided steps -> practice -> summary
5. **Edit safely**: preserve notebook structure; avoid reordering cells unless it improves the top-to-bottom story. Prefer targeted edits over full rewrites.
6. **Validate**: run the notebook top-to-bottom when possible. If execution is not possible, say so and explain how to validate locally.

## Notebook JSON rules
- `.ipynb` is JSON with specific schema — do not break the structure.
- Each cell has `cell_type` ("code" or "markdown"), `source` (list of strings), `metadata`, and `outputs` (for code cells).
- Always use `"nbformat": 4` and `"nbformat_minor": 5`.
- When editing, prefer targeted cell changes over full file rewrites.

## Temp and output conventions
- Use `tmp/jupyter-notebook/` for intermediate files; delete when done.
- Write final artifacts under `output/jupyter-notebook/`.
- Use stable, descriptive filenames (e.g., `ablation-temperature.ipynb`).

## Dependencies (install only when needed)
```
uv pip install jupyterlab ipykernel
```

## Quality checklist
- [ ] Every code cell runs without error top-to-bottom
- [ ] Markdown cells explain the *why*, not just the *what*
- [ ] No large, noisy output — truncate or summarize
- [ ] Imports are at the top
- [ ] No hardcoded paths that won't work on another machine
- [ ] Conclusion / takeaway cell at the end

$ARGUMENTS
