# Script-test runs (`tools/summarize.py` output)

## macOS WebKit: no CSP (positive control) and the app's CSP

```
csp-script-test.azw3: opened in 0.1s, 6 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 7, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 30}
csp-script-test.epub: opened in 0.2s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 2, 'objectEmbed': 2, 'remote': 8, 'script': 9, 'svgScript': 1, 'vectors': 30}
csp-script-test.joint.mobi: opened in 0.2s, 6 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 7, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 30}
csp-script-test.mobi: opened in 0.2s, 7 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 2, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 0}
nocsp-script-test.azw3: opened in 0.2s, 6 sections
  scripts ran (13): css-onanimationstart, details-ontoggle, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, resource-script, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  beacon (42 requests, 25 vectors): base-href, css-onanimationstart, details-ontoggle, embed-svg-data-url, iframe-data-url, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, meta-refresh-remote, object-data-url, remote-audio, remote-css-background, remote-css-import, remote-font, remote-img, remote-stylesheet, remote-video-poster, resource-script, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  of which script beacons: css-onanimationstart, details-ontoggle, embed-svg-data-url, iframe-data-url, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, object-data-url, resource-script, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 7, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 30}
nocsp-script-test.epub: opened in 0.2s, 5 sections
  scripts ran (13): css-onanimationstart, details-ontoggle, epub-head-script, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  beacon (51 requests, 25 vectors): base-href, css-onanimationstart, details-ontoggle, embed-svg-data-url, epub-head-script, iframe-data-url, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, meta-refresh-remote, object-data-url, remote-audio, remote-css-background, remote-css-import, remote-font, remote-img, remote-stylesheet, remote-video-poster, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  of which script beacons: css-onanimationstart, details-ontoggle, embed-svg-data-url, epub-head-script, iframe-data-url, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, object-data-url, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 2, 'objectEmbed': 2, 'remote': 8, 'script': 9, 'svgScript': 1, 'vectors': 30}
nocsp-script-test.joint.mobi: opened in 0.3s, 6 sections
  scripts ran (13): css-onanimationstart, details-ontoggle, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, resource-script, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  beacon (42 requests, 25 vectors): base-href, css-onanimationstart, details-ontoggle, embed-svg-data-url, iframe-data-url, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, meta-refresh-remote, object-data-url, remote-audio, remote-css-background, remote-css-import, remote-font, remote-img, remote-stylesheet, remote-video-poster, resource-script, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  of which script beacons: css-onanimationstart, details-ontoggle, embed-svg-data-url, iframe-data-url, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, object-data-url, resource-script, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 7, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 30}
nocsp-script-test.mobi: opened in 0.2s, 7 sections
  scripts ran (13): css-onanimationstart, details-ontoggle, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, resource-script, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  beacon (41 requests, 25 vectors): base-href, css-onanimationstart, details-ontoggle, embed-svg-data-url, iframe-data-url, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, meta-refresh-remote, object-data-url, remote-audio, remote-css-background, remote-css-import, remote-font, remote-img, remote-stylesheet, remote-video-poster, resource-script, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  of which script beacons: css-onanimationstart, details-ontoggle, embed-svg-data-url, iframe-data-url, iframe-javascript-url, iframe-srcdoc, img-onerror, inline-script, inline-script-typed, input-autofocus, object-data-url, resource-script, svg-animate-onbegin, svg-onload, svg-script, video-source-onerror
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 2, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 0}
csp-script-test-xxe.fb2: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
csp-script-test.fb2: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
csp-script-test.fbz: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
nocsp-script-test-xxe.fb2: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (2 requests, 2 vectors): fb2-cover-remote, fb2-image-remote
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
nocsp-script-test.fb2: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (2 requests, 2 vectors): fb2-cover-remote, fb2-image-remote
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
nocsp-script-test.fbz: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (2 requests, 2 vectors): fb2-cover-remote, fb2-image-remote
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
```

The FB2 rows are from a re-run on the final FB2 files; that run's collect.js also calls `getCover()`.

## macOS WebKit: the harden.js prototype, CSP switched off

```
csp+sanitize+meta-script-test.azw3: opened in 0.1s, 6 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 11, 'objectEmbed': 2, 'remote': 7, 'script': 4, 'svgScript': 1, 'vectors': 30}
csp+sanitize+meta-script-test.epub: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 5, 'objectEmbed': 2, 'remote': 7, 'script': 9, 'svgScript': 1, 'vectors': 30}
csp+sanitize+meta-script-test.fb2: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 0, 'metaRefresh': 5, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
csp+sanitize+meta-script-test.joint.mobi: opened in 0.1s, 6 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 11, 'objectEmbed': 2, 'remote': 7, 'script': 4, 'svgScript': 1, 'vectors': 30}
csp+sanitize+meta-script-test.mobi: opened in 0.1s, 7 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 7, 'objectEmbed': 2, 'remote': 7, 'script': 4, 'svgScript': 1, 'vectors': 0}
nocsp+sanitize-script-test.azw3: opened in 0.1s, 6 sections
  scripts ran (0): none
  beacon (8 requests, 7 vectors): remote-audio, remote-css-background, remote-css-import, remote-font, remote-img, remote-stylesheet, remote-video-poster
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 5, 'objectEmbed': 2, 'remote': 7, 'script': 4, 'svgScript': 1, 'vectors': 30}
nocsp+sanitize-script-test.epub: opened in 0.2s, 5 sections
  scripts ran (0): none
  beacon (8 requests, 7 vectors): remote-audio, remote-css-background, remote-css-import, remote-font, remote-img, remote-stylesheet, remote-video-poster
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 0, 'objectEmbed': 2, 'remote': 7, 'script': 9, 'svgScript': 1, 'vectors': 30}
nocsp+sanitize-script-test.fb2: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (2 requests, 2 vectors): fb2-cover-remote, fb2-image-remote
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 0, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
nocsp+sanitize-script-test.joint.mobi: opened in 0.2s, 6 sections
  scripts ran (0): none
  beacon (8 requests, 7 vectors): remote-audio, remote-css-background, remote-css-import, remote-font, remote-img, remote-stylesheet, remote-video-poster
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 5, 'objectEmbed': 2, 'remote': 7, 'script': 4, 'svgScript': 1, 'vectors': 30}
nocsp+sanitize-script-test.mobi: opened in 0.1s, 7 sections
  scripts ran (0): none
  beacon (8 requests, 7 vectors): remote-audio, remote-css-background, remote-css-import, remote-font, remote-img, remote-stylesheet, remote-video-poster
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 0, 'objectEmbed': 2, 'remote': 7, 'script': 4, 'svgScript': 1, 'vectors': 0}
nocsp+meta-script-test.azw3: opened in 0.1s, 6 sections
  scripts ran (0): none
  beacon (1 requests, 1 vectors): meta-refresh-remote
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 13, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 30}
nocsp+meta-script-test.epub: opened in 0.2s, 5 sections
  scripts ran (0): none
  beacon (1 requests, 1 vectors): meta-refresh-remote
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 7, 'objectEmbed': 2, 'remote': 8, 'script': 9, 'svgScript': 1, 'vectors': 30}
nocsp+meta-script-test.fb2: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (1 requests, 1 vectors): fb2-cover-remote
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 5, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
nocsp+meta-script-test.joint.mobi: opened in 0.1s, 6 sections
  scripts ran (0): none
  beacon (1 requests, 1 vectors): meta-refresh-remote
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 13, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 30}
nocsp+meta-script-test.mobi: opened in 0.1s, 7 sections
  scripts ran (0): none
  beacon (1 requests, 1 vectors): meta-refresh-remote
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 9, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 0}
nocsp+sanitize+meta-script-test.azw3: opened in 0.1s, 6 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 11, 'objectEmbed': 2, 'remote': 7, 'script': 4, 'svgScript': 1, 'vectors': 30}
nocsp+sanitize+meta-script-test.epub: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 5, 'objectEmbed': 2, 'remote': 7, 'script': 9, 'svgScript': 1, 'vectors': 30}
nocsp+sanitize+meta-script-test.fb2: opened in 0.1s, 5 sections
  scripts ran (0): none
  beacon (1 requests, 1 vectors): fb2-cover-remote
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 0, 'metaRefresh': 5, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
nocsp+sanitize+meta-script-test.joint.mobi: opened in 0.1s, 6 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 11, 'objectEmbed': 2, 'remote': 7, 'script': 4, 'svgScript': 1, 'vectors': 30}
nocsp+sanitize+meta-script-test.mobi: opened in 0.1s, 7 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 0, 'iframe': 3, 'jsURL': 0, 'metaRefresh': 7, 'objectEmbed': 2, 'remote': 7, 'script': 4, 'svgScript': 1, 'vectors': 0}
```

The `nocsp+meta` and `nocsp+sanitize+meta` rows use the final section policy (which also blocks remote loads).

## The app on 'Octavo Formats Duo' (iOS 27.1), `octavo://` scheme

```
app-script-test-xxe.fb2: opened in 0.0s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
app-script-test.azw3: opened in 0.0s, 6 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 7, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 30}
app-script-test.epub: opened in 0.0s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 2, 'objectEmbed': 2, 'remote': 8, 'script': 9, 'svgScript': 1, 'vectors': 30}
app-script-test.fb2: opened in 0.0s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
app-script-test.fbz: opened in 0.0s, 5 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 0, 'handlers': 0, 'iframe': 0, 'jsURL': 2, 'metaRefresh': 0, 'objectEmbed': 0, 'remote': 2, 'script': 0, 'svgScript': 0, 'vectors': 0}
app-script-test.joint.mobi: opened in 0.0s, 6 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 7, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 30}
app-script-test.mobi: opened in 0.0s, 7 sections
  scripts ran (0): none
  beacon (0 requests, 0 vectors): none
  payload elements present: {'base': 1, 'handlers': 7, 'iframe': 3, 'jsURL': 2, 'metaRefresh': 2, 'objectEmbed': 2, 'remote': 8, 'script': 4, 'svgScript': 1, 'vectors': 0}
```
