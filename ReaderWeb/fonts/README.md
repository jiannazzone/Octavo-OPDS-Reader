# Bundled fonts

The two fonts Text and Theme's Font menu adds to the ones iOS ships (decision 16, #83). `ReaderSchemeHandler` serves this folder at `octavo://app/fonts/`, the only place the reader's CSP lets a font load from apart from a book's own (`blob:` and `data:`). `ReaderFont.fontFaces` has the `@font-face` rules.

Both are the projects' own WOFF2 files, unchanged apart from Atkinson's file names: the SIL Open Font License allows a WOFF2 copy under the font's own name only if its data is unchanged. Each family's licence is next to it.

- **Atkinson Hyperlegible Next** (Braille Institute, version 2.66), from [googlefonts/atkinson-hyperlegible-next](https://github.com/googlefonts/atkinson-hyperlegible-next) at `7925f50`: `fonts/webfonts/AtkinsonHyperlegibleNext[wght].woff2` and `AtkinsonHyperlegibleNext-Italic[wght].woff2`, and `OFL.txt`. Chosen over the 2020 Atkinson Hyperlegible: it looks the same, has a few more Latin letters, and comes as one variable file per style, so a book's semibold is semibold. 101 KB.
- **OpenDyslexic** (Abbie Gonzalez), the four WOFF2 files in the [v0.91.12 release](https://github.com/antijingoist/opendyslexic/releases/tag/v0.91.12) of [antijingoist/opendyslexic](https://github.com/antijingoist/opendyslexic) (`opendyslexic-0.910.12-rc2-2019.10.17.zip`, SHA-256 `b92d7fcb…eb486`), and `OFL.txt` at that tag (`449a41b`). Its licence reserves the name OpenDyslexic, another reason the files stay as they are. 464 KB.
  - The project's main branch has newer files (2025, "Testing"), but there the regular is spaced much wider than the italic. The release's four styles match.
  - Its "fi" and "ffi" ligatures leave a gap in every version, so `ReaderFont` turns ligatures off (the main branch's regular dropped them too).

```
abde1ad5cf78b9ac575ef90d991f2e9101eb0b3b6668bde9a00e2e1e27d99afd  AtkinsonHyperlegibleNext.woff2
34491c5a87f711d314637962f69267d28c7df3ed498082c990cdfbbc02ebf3f2  AtkinsonHyperlegibleNext-Italic.woff2
aca6a428580965d2297d1b718042dd427c2a9443ece3b0d02d758e161e0c4030  AtkinsonHyperlegibleNext-OFL.txt
f007004af3cda5d8076e57c943f8cc8d00a0da25988b1ae1048683d60e7cac1a  OpenDyslexic-Regular.woff2
dd9fa9c7991113b0dddefe9506a30ad26b48e302b7a8fb91719a4726e8fde85b  OpenDyslexic-Bold.woff2
eb6a1bacf7e7c87a08116af4cd00a82064fbe61647b9a0d4d70a339890268f88  OpenDyslexic-Italic.woff2
a20d82c2a1a0a6ab74796529aca31bfbae93e3e58f5a7360cba854dd98a15214  OpenDyslexic-Bold-Italic.woff2
caafcccfb70fc72458fcbda812ec8f0a06cb300cbabb87eabbb30b946124394b  OpenDyslexic-OFL.txt
```

The footnote card draws the same files, registered with Core Text (`docs/notes/footnotes.md`), and asks for them by the family name inside them (`ReaderFont.bundledFamily`).

To update one, download it from the same place, check its licence is still SIL OFL 1.1, replace the files and the lines above, and look at a page in it, with italics and bold, folded and unfolded, and at a footnote card in it.
