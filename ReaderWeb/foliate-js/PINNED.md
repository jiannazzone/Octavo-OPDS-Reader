# foliate-js pin

- **Upstream:** https://github.com/johnfactotum/foliate-js (MIT, see `LICENSE`)
- **Commit:** `6b11e1744346f60504b727984f7d42f0fef3ab54` (`6b11e17`)
- **Commit date:** 2025-11-29, "Properly handle empty fragments for MOBI (#107)"
- **Vendored:** 2026-10-31, task 1a of the first spike
- **Modified:** no. Every `.js` file here is byte-identical to upstream at this commit.

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
2. Copy the new files in unmodified and update this file.
3. Re-run the CFI round-trip check from spike step 4 before merging.
