# ReaderWeb

Web side of the EPUB reader. Bundled into the app as a **folder reference**, so the directory structure is kept and foliate-js's relative ES-module imports resolve. The app serves this folder to the `WebView` through a custom URL scheme handler.

- `foliate-js/` is upstream [foliate-js](https://github.com/johnfactotum/foliate-js) (MIT), vendored at a pinned commit plus a small numbered patch set in `foliate-js/patches/` (`paginator.js` only). `foliate-js/PINNED.md` records the commit, the patches and why. Update it deliberately.
- Everything else here (the host page and our Swift ↔ JS bridge) is ours, MPL-2.0.

Never copy BookOrbit's `bridge.js` or its modified foliate files into this folder. See CLAUDE.md "Licensing rules".
