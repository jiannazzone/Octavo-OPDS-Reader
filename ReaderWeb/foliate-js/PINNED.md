# foliate-js pin

- **Upstream:** https://github.com/johnfactotum/foliate-js (MIT, see `LICENSE`)
- **Commit:** `6b11e1744346f60504b727984f7d42f0fef3ab54` (`6b11e17`)
- **Commit date:** 2025-11-29, "Properly handle empty fragments for MOBI (#107)"
- **Vendored:** 2026-10-31, task 1a of the first spike
- **Modified:** only `paginator.js`, by the numbered patches below. Every other `.js` file here is byte-identical to upstream at this commit. `epubcfi.js` is never patched: CFIs must stay identical to BookOrbit's.

## Local patches

Applied in order on top of upstream `6b11e17`. Each file in `patches/` has a header saying what it fixes and how it was checked. Applying them all to upstream's `paginator.js` must reproduce ours byte for byte:

```bash
git apply --directory=ReaderWeb/foliate-js ReaderWeb/foliate-js/patches/*.patch   # onto a clean upstream copy
```

| # | File | Fixes | Vetting | Upstream |
|---|---|---|---|---|
| 0001 | `patches/0001-blank-page-position.patch` | On a page with no visible node (a blank column left by forced breaks, a tall block, a `100vh` title), `getVisibleRange()` fell back to the section's `<body>`. The CFI then named only the section, and any re-layout (resize, fold, font load) or a restore jumped to the section's first page. The patch reports the next content's start as the location and anchors the page by fraction. CFIs on pages with content are unchanged (1,546 of 1,546 byte-identical). | `docs/notes/foliate-blank-page-upstream.md`, section "5. The fix"; harness and page-by-page comparison in `docs/notes/foliate-blank-page/` | Not reported. Draft issue and PR text are in the vetting doc, for the owner to send. |
| 0002 | `patches/0002-portrait-column-count.patch` | A portrait reader area always got one column: `--_max-column-count-portrait` had no attribute. Adds a `max-column-count-portrait` attribute so the host decides the column count (Octavo decides it from the hinge, not the aspect ratio). No effect unless the attribute is set. | `docs/notes/duo-spreads.md` (spike 2b): a 400×493 view asked for two columns gets one without the patch, two with it. | Not reported. |

## Why this commit

BookOrbit's web reader (and its Android app) are built on this exact upstream commit. Its `epubcfi.js` is identical to it. Using the same base keeps CFIs comparable with BookOrbit, which is the spike's main risk. Upstream commits after this one don't change EPUB CFIs either (the `nodeToParts` change in `b74d50e` only applies when a filter is passed, and `View.getCFI` never passes one). The full analysis is in `docs/notes/bookorbit-foliate.md`.

## What's included

Only what EPUB, MOBI/AZW3, FB2 and CBZ need:

`view.js`, `epub.js`, `epubcfi.js`, `paginator.js`, `fixed-layout.js`, `progress.js`, `overlayer.js`, `text-walker.js`, `search.js`, `tts.js`, `mobi.js`, `fb2.js`, `comic-book.js`, plus `vendor/zip.js` (zip.js 2.7.52, BSD-3-Clause) and `vendor/fflate.js` (fflate 0.8.2, MIT). These are the minified builds upstream committed, and their licenses are in `vendor/LICENSE-*.txt`.

Left out:

- `pdf.js` and `vendor/pdfjs/` (PDFs go to PDFKit). `view.js` imports `pdf.js` dynamically, and only for PDF input, which we never pass it.
- `opds.js`, `dict.js`, `footnotes.js`, `quote-image.js`, `uri-template.js`.
- The demo reader (`reader.html`, `reader.js`, `ui/`), tests and build files.

## Updating

foliate-js says its API is unstable. Update deliberately:

1. Diff `epubcfi.js`, `paginator.js` (`getVisibleRange`, `#getVisibleRange`) and `view.js` (`#onRelocate`, `getCFI`, `resolveCFI`) against this commit, and against whatever BookOrbit uses at that point.
2. Copy the new files in unmodified, re-apply each patch in `patches/` (drop any that upstream has absorbed), and update this file.
3. Re-run the CFI round-trip check from spike step 4 and the fold-continuity check from spike 2b (`docs/notes/duo-spreads.md`) before merging.
