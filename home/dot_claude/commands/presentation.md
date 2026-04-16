Create, edit, or review PowerPoint (`.pptx`) presentations with professional formatting using `python-pptx`.

## When to use
- Create slide decks from scratch or from an outline.
- Edit existing presentations (add/reorder slides, update content, fix styling).
- Convert documents or data into presentation format.
- Validate visual layout before delivery.

## Workflow
1. **Outline first**: agree on slide structure before building. Each slide needs a clear purpose.
2. Use `python-pptx` for all creation and editing.
3. **Visual review**: render PPTX -> PDF -> PNGs if `soffice` and `pdftoppm` are available.
   ```
   soffice -env:UserInstallation=file:///tmp/lo_profile_$$ --headless --convert-to pdf --outdir $OUTDIR $INPUT_PPTX
   pdftoppm -png $OUTDIR/$BASENAME.pdf $OUTDIR/$BASENAME
   ```
   Inspect rendered PNGs directly — Claude Code can read images natively.
4. After each meaningful change, re-render and verify layout.
5. Clean up intermediate files after final approval.

## Slide design principles
- **One idea per slide**. If a slide needs more than 3 bullet points, split it.
- **Title + content** is the default layout. Use blank/section header sparingly.
- **Consistent hierarchy**: title font > subtitle > body > caption.
- **Whitespace matters**: don't fill every pixel. 10-15% margin minimum.
- **Limit text**: slides support the speaker, they are not a document.
- **Visual alignment**: all elements on a grid. No eyeballed placement.
- **Color palette**: 2-3 primary colors max. Dark text on light bg, or light text on dark bg.

## Layout patterns
- **Title slide**: title + subtitle + optional logo/date
- **Content slide**: title + bullet points (max 5)
- **Two-column**: side-by-side comparison or text + visual
- **Full-image**: background image + overlay text
- **Data slide**: title + chart/table (keep clean, label axes)
- **Section divider**: bold title, minimal content, visual break
- **Summary/CTA**: key takeaways or next steps

## Dependencies (install if missing)
```
uv pip install python-pptx
```
System tools (for rendering):
```
brew install libreoffice poppler
```

## Temp and output conventions
- Use `tmp/presentations/` for intermediate files; delete when done.
- Write final artifacts under `output/presentation/`.

## Quality expectations
- Consistent font family and size hierarchy across all slides.
- No text overflow, clipping, or overlapping elements.
- Charts and tables legible at presentation resolution (1920x1080).
- Proper aspect ratio: 16:9 (default) or 4:3 if specified.
- Speaker notes included when the content warrants them.

$ARGUMENTS
