Create, edit, analyze, or format spreadsheets (`.xlsx`, `.csv`, `.tsv`) with formula-aware workflows and visual review.

## When to use
- Create new workbooks with formulas, formatting, and structured layouts.
- Read or analyze tabular data (filter, aggregate, pivot, compute metrics).
- Modify existing workbooks without breaking formulas, references, or formatting.
- Visualize data with charts, summary tables, and spreadsheet styling.

## Workflow
1. Confirm the file type and goal: create, edit, analyze, or visualize.
2. Prefer `openpyxl` for `.xlsx` editing and formatting. Use `pandas` for analysis and CSV/TSV workflows.
3. Use formulas for derived values instead of hardcoding results.
4. If layout matters, render for visual review and inspect the output.
5. Save outputs, keep filenames stable, and clean up intermediate files.

## Rendering and visual checks
If LibreOffice and Poppler are available, render sheets for visual review:
```
soffice --headless --convert-to pdf --outdir $OUTDIR $INPUT_XLSX
pdftoppm -png $OUTDIR/$BASENAME.pdf $OUTDIR/$BASENAME
```
Claude Code can read the rendered PNGs directly for visual verification.

## Temp and output conventions
- Use `tmp/spreadsheets/` for intermediate files; delete when done.
- Write final artifacts under `output/spreadsheet/`.

## Dependencies (install if missing)
Prefer `uv` for dependency management.
```
uv pip install openpyxl pandas
```
Optional:
```
uv pip install matplotlib
```
System tools (for rendering):
```
brew install libreoffice poppler
```

## Formula requirements
- Use formulas for derived values rather than hardcoding results.
- Do NOT use dynamic array functions (`FILTER`, `XLOOKUP`, `SORT`, `SEQUENCE`).
- Keep formulas simple and legible; use helper cells for complex logic.
- Avoid volatile functions (`INDIRECT`, `OFFSET`) unless required.
- Prefer cell references over magic numbers.
- Use absolute (`$B$4`) or relative (`B4`) references carefully.
- Guard against `#REF!`, `#DIV/0!`, `#VALUE!`, `#N/A`, `#NAME?` errors.

## Formatting requirements (new or unstyled spreadsheets)
- Appropriate number and date formats (dates render as dates, not numbers).
- Percentages: 1 decimal place by default.
- Headers visually distinct from raw inputs and derived cells.
- Use fill colors, borders, spacing sparingly and intentionally.
- Set row heights and column widths for readability.
- Do not apply borders around every filled cell.
- Ensure text does not spill into adjacent cells.

## Color conventions (if no style guidance)
- Blue: user input
- Black: formulas and derived values
- Green: linked or imported values
- Gray: static constants
- Orange: review or caution
- Light red: error or flag
- Teal: visualization anchors and KPI highlights

## Finance-specific requirements
- Format zeros as `-`.
- Negative numbers: red and in parentheses.
- Multiples as `5.2x`.
- Always specify units in headers (e.g., `Revenue ($mm)`).
- Cite sources in cell comments for raw inputs.

## Citation requirements
- Cite sources inside the spreadsheet using plain-text URLs.
- For financial models, cite model inputs in cell comments.

$ARGUMENTS
