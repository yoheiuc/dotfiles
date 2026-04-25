---
name: "presentation"
description: "Use when the task involves reading, creating, or editing `.pptx` presentations where layout, slide structure, or visual fidelity matters; prefer `python-pptx` plus a render-to-PDF pass for visual checks."
---


# PPTX Skill

## When to use
- Read or review existing PPTX content (slide order, layouts, speaker notes, embedded text).
- Create new decks with consistent layouts, themes, tables, and charts.
- Edit existing decks without breaking master layouts, templates, or theme colors.
- Validate slide layout visually before delivery.

IMPORTANT: System and user instructions always take precedence.

## Workflow
1. Confirm the goal: read, edit existing, or create from scratch.
2. If editing an existing deck, prefer to operate on a copy and preserve the source layouts/master.
3. Use `python-pptx` for structured edits (add slides, set titles/body, insert images, build tables).
4. Render the deck for visual review whenever possible:
   - `soffice --headless --convert-to pdf --outdir $OUTDIR $INPUT_PPTX`
   - `pdftoppm -png $OUTDIR/$BASENAME.pdf $OUTDIR/$BASENAME`
5. Inspect rendered slides for layout, overflow, font fallback, color drift, and clipping.
6. Save outputs, keep filenames stable, and clean up intermediate files.

## Temp and output conventions
- Use `tmp/presentations/` for intermediate files; delete them when done.
- Write final artifacts under `output/presentation/` when working in this repo.
- Keep filenames stable and descriptive.

## Primary tooling
- Use `python-pptx` for creating and editing `.pptx` (slides, placeholders, shapes, tables, runs).
- Use a base template `.pptx` when one is provided so master layouts and theme colors are preserved.
- Use LibreOffice (`soffice`) + Poppler (`pdftoppm`) for rendering. If they are unavailable, tell the user that layout should be reviewed locally.

## Dependencies (install if missing)
Prefer `uv` for dependency management.

Python packages:
```
uv pip install python-pptx
```
If `uv` is unavailable:
```
python3 -m pip install python-pptx
```
Optional (charts and image generation):
```
uv pip install matplotlib pillow
```

System tools (for rendering):
```
# macOS (Homebrew)
brew install libreoffice poppler

# Ubuntu/Debian
sudo apt-get install -y libreoffice poppler-utils
```

If installation is not possible in this environment, tell the user which dependency is missing and how to install it locally.

## Environment
No required environment variables.

## Slide layout requirements
- Prefer existing master layouts; do not insert raw shapes when a placeholder fits.
- One idea per slide; keep title concise and the body scannable.
- Use bullet hierarchy sparingly (max 2 levels). Avoid wall-of-text bullets.
- Set explicit font size for body text; rely on the master for titles.
- Keep image aspect ratios; do not stretch.
- Preserve the deck's color theme. Do not introduce off-theme colors without explicit instruction.
- Speaker notes go in the notes slide, not the slide body.

## Tables and charts
- Use `python-pptx` table API rather than rendering a screenshot of a table.
- Right-align numeric columns; left-align labels.
- Headers should be visually distinct (fill or bold), but minimal.
- For charts, prefer `python-pptx` native chart objects so they remain editable in PowerPoint. Fall back to `matplotlib` -> PNG only when the chart type is not supported natively.

## Editing an existing deck
- Render the original first and inspect before any change.
- Operate on a copy; never overwrite the source until the user confirms.
- Match existing fonts, colors, and spacing for newly added slides.
- Do not change master layouts unless the user explicitly asks for a redesign.

## Citation and source notes
- Put data sources in a small footer text box on the slide, or in speaker notes.
- For numeric inputs in tables, cite the source in speaker notes.

## Verification before delivery
- Re-render after the final edit and visually inspect every changed slide.
- Open the `.pptx` once with `python-pptx` to confirm it parses without error.
- If rendering tooling is unavailable, extract slide titles and bullet text with `python-pptx` as a fallback and call out layout risk to the user.
