Read, create, or edit `.docx` documents with formatting and layout fidelity using `python-docx`.

## When to use
- Read or review DOCX content where layout matters (tables, diagrams, pagination).
- Create or edit DOCX files with professional formatting.
- Validate visual layout before delivery.

## Workflow
1. **Visual review first** (layout, tables, diagrams):
   - Convert DOCX -> PDF -> PNGs if `soffice` and `pdftoppm` are available.
   - Claude Code can read images natively — render and inspect the PNGs directly.
   - If tools are missing, ask the user to install them.
2. Use `python-docx` for edits and structured creation (headings, styles, tables, lists).
3. After each meaningful change, re-render and inspect the pages.
4. If visual review is not possible, extract text with `python-docx` as a fallback and call out layout risk.
5. Keep intermediate outputs organized and clean up after final approval.

## Temp and output conventions
- Use `tmp/docs/` for intermediate files; delete when done.
- Write final artifacts under `output/doc/`.
- Keep filenames stable and descriptive.

## Dependencies (install if missing)
Prefer `uv` for dependency management.

Python packages:
```
uv pip install python-docx pdf2image
```
If `uv` is unavailable:
```
python3 -m pip install python-docx pdf2image
```
System tools (for rendering):
```
# macOS (Homebrew)
brew install libreoffice poppler

# Ubuntu/Debian
sudo apt-get install -y libreoffice poppler-utils
```

## Rendering commands
DOCX -> PDF:
```
soffice -env:UserInstallation=file:///tmp/lo_profile_$$ --headless --convert-to pdf --outdir $OUTDIR $INPUT_DOCX
```

PDF -> PNGs:
```
pdftoppm -png $OUTDIR/$BASENAME.pdf $OUTDIR/$BASENAME
```

## Quality expectations
- Client-ready document: consistent typography, spacing, margins, and clear hierarchy.
- No formatting defects: clipped/overlapping text, broken tables, unreadable characters, or default-template styling.
- Charts, tables, and visuals must be legible in rendered pages with correct alignment.
- Use ASCII hyphens only. Avoid Unicode dashes.
- Citations and references must be human-readable.

## Final checks
- Re-render and inspect every page at 100% zoom before final delivery.
- Fix any spacing, alignment, or pagination issues and repeat the render loop.
- Clean up temp files unless the user asks to keep them.

$ARGUMENTS
