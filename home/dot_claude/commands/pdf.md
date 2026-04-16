Read, create, or review PDF files. Use `reportlab` for generation, `pdfplumber`/`pypdf` for extraction, and visual verification via rendering.

## When to use
- Read or review PDF content where layout and visuals matter.
- Create PDFs programmatically with reliable formatting.
- Validate final rendering before delivery.

## Workflow
1. **Visual review first**: render PDF pages to PNGs and inspect them.
   - Use `pdftoppm -png $INPUT_PDF $OUTPUT_PREFIX` if Poppler is available.
   - Claude Code can read images natively — render and inspect the PNGs directly.
   - If tools are missing, ask the user to install them.
2. Use `reportlab` to generate PDFs when creating new documents.
3. Use `pdfplumber` (or `pypdf`) for text extraction and quick checks; do not rely on it for layout fidelity.
4. After each meaningful update, re-render pages and verify alignment, spacing, and legibility.

## Temp and output conventions
- Use `tmp/pdfs/` for intermediate files; delete when done.
- Write final artifacts under `output/pdf/`.
- Keep filenames stable and descriptive.

## Dependencies (install if missing)
Prefer `uv` for dependency management.

Python packages:
```
uv pip install reportlab pdfplumber pypdf
```
If `uv` is unavailable:
```
python3 -m pip install reportlab pdfplumber pypdf
```
System tools (for rendering):
```
# macOS (Homebrew)
brew install poppler

# Ubuntu/Debian
sudo apt-get install -y poppler-utils
```

## Rendering command
```
pdftoppm -png $INPUT_PDF $OUTPUT_PREFIX
```

## Quality expectations
- Polished visual design: consistent typography, spacing, margins, and section hierarchy.
- No rendering issues: clipped text, overlapping elements, broken tables, black squares, or unreadable glyphs.
- Charts, tables, and images must be sharp, aligned, and clearly labeled.
- Use ASCII hyphens only. Avoid U+2011 (non-breaking hyphen) and other Unicode dashes.
- Citations and references must be human-readable.

## Final checks
- Do not deliver until the latest PNG inspection shows zero visual or formatting defects.
- Confirm headers/footers, page numbering, and section transitions look polished.
- Clean up intermediate files after final approval.

$ARGUMENTS
