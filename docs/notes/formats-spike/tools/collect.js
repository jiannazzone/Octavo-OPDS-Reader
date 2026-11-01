// Formats spike: visits sections of the open book and reports, for each, the
// marks left by book scripts that ran (Scripts/make-script-test-books.py) and
// whether the payload elements are there at all (if they aren't, a missing
// mark proves nothing). A function body: run it with the app's `js` debug
// command or WKWebView.callAsyncJavaScript (probe.swift). Before running,
// replace __SECTIONS__ (an array of section indexes, or null for all),
// __WAIT__ (ms to wait in each section) and __CLICK__ (true to also click
// every link in the section, the way a tap would).
const view = document.querySelector('foliate-view')
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
const only = __SECTIONS__
const marks = doc => doc?.documentElement
    ? doc.documentElement.getAttributeNames().filter(name => name.startsWith('data-ran-')).map(name => name.slice(9))
    : []
const out = { sections: view.book.sections.length, visits: [] }
// Metadata, cover and TOC as foliate extracts them.
const meta = view.book.metadata ?? {}
const short = x => x === undefined || x === null ? null : (typeof x === 'string' ? x : JSON.stringify(x)).slice(0, 300)
out.metadata = Object.fromEntries(['title', 'author', 'language', 'identifier', 'publisher', 'published', 'description', 'subject']
    .map(key => [key, short(meta[key])]))
try {
    const cover = await view.book.getCover?.()
    out.cover = cover ? { size: cover.size, type: cover.type } : null
} catch (e) {
    out.cover = { error: String(e) }
}
out.toc = { items: view.book.toc?.length ?? 0, first: (view.book.toc ?? []).slice(0, 3).map(item => item.label?.trim?.() ?? null) }
out.landmarks = (view.book.landmarks ?? []).map(l => l.type?.join?.(' ') ?? null)
out.dir = view.book.dir ?? null
out.layout = view.book.rendition?.layout ?? null
for (let i = 0; i < view.book.sections.length; i++) {
    if (only && !only.includes(i)) continue
    if (!view.book.sections[i].load) continue
    try {
        await view.goTo(i)
    } catch (e) {
        out.visits.push({ index: i, error: String(e) })
        continue
    }
    await sleep(__WAIT__)
    for (const { doc, index } of view.renderer.getContents()) {
        if (index !== i) continue
        const count = selector => doc.querySelectorAll(selector).length
        const handlers = [...doc.querySelectorAll('*')]
            .flatMap(el => el.getAttributeNames().filter(name => /^on/i.test(name)).map(name => `${el.localName}[${name}]`))
        const nested = [...doc.querySelectorAll('iframe, object, embed')].map(frame => {
            try {
                const inner = frame.contentDocument ?? frame.getSVGDocument?.() ?? null
                return { tag: frame.localName, url: inner?.URL?.slice(0, 60) ?? null, marks: marks(inner) }
            } catch (e) {
                return { tag: frame.localName, error: String(e) }
            }
        })
        const visit = {
            index,
            contentType: doc.contentType,
            url: doc.URL.slice(0, 60),
            text: doc.body?.textContent.replace(/\s+/g, ' ').trim().slice(0, 80) ?? null,
            marks: marks(doc),
            present: {
                vectors: count('.vector'),
                script: count('script'),
                svgScript: doc.getElementsByTagNameNS('http://www.w3.org/2000/svg', 'script').length,
                handlers,
                jsURL: count('[href^="javascript:"], [src^="javascript:"]'),
                iframe: count('iframe'),
                objectEmbed: count('object, embed'),
                metaRefresh: count('meta[http-equiv]'),
                base: count('base'),
                remote: count('[src^="http"], [href^="http"], [poster^="http"]'),
            },
            nested,
        }
        if (__CLICK__) {
            visit.clicked = []
            for (const a of doc.querySelectorAll('a[href]')) {
                visit.clicked.push(a.getAttribute('href').slice(0, 40))
                a.click()
                await sleep(300)
            }
            visit.marksAfterClicks = marks(doc)
        }
        out.visits.push(visit)
    }
}
out.topMarks = window.__bookScriptRan ?? []
return out
