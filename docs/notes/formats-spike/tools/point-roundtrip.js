// Formats spike: how often does going back to a page's own point CFI (what
// the app saves and syncs) land on a different page? For every __STEP__th
// section: go there, turn __TURNS__ pages, take the page's range CFI and its
// collapsed start point, go elsewhere, then go to the point (and separately
// to the range, and to the BookOrbit-style text point) and compare the page
// that comes back. A function body, like
// collect.js. Also reports, for each miss, whether the point's caret rect
// sits at the end of a line (WebKit puts a caret at a soft line break on the
// line before it).
const CFI = await import('./foliate-js/epubcfi.js')
const view = document.querySelector('foliate-view')
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
const page = () => {
    const location = view.lastLocation
    return {
        cfi: location?.cfi ?? null,
        start: location?.cfi ? CFI.collapse(location.cfi) : null,
        words: (location?.range?.toString() ?? '').split(/\s+/).filter(Boolean).slice(0, 6).join(' '),
    }
}
const caret = async point => {
    // Where WebKit draws a caret for the point, against the line box of the
    // text that follows it.
    const { index, anchor } = view.resolveNavigation(point)
    const doc = view.renderer.getContents().find(c => c.index === index)?.doc
    if (!doc) return null
    const range = anchor(doc)
    if (!range?.getClientRects) return null
    const rects = range.getClientRects()
    const next = doc.createRange()
    next.setStart(range.startContainer, range.startOffset)
    try { next.setEnd(range.startContainer, Math.min(range.startOffset + 1, range.startContainer.length ?? 0)) } catch {}
    const r = rects[0] ?? range.getBoundingClientRect()
    const n = next.getClientRects()[0]
    return r && n ? { caretTop: Math.round(r.top), nextCharTop: Math.round(n.top), caretLeft: Math.round(r.left), nextCharLeft: Math.round(n.left) } : null
}
// The point BookOrbit's web reader would store for the page: when the range
// starts at an element, the first non-blank text node in it, at offset 0.
const textStart = () => {
    const location = view.lastLocation
    const range = location?.range
    if (!range) return null
    if (range.startContainer.nodeType === 3) return CFI.collapse(location.cfi)
    const doc = range.startContainer.ownerDocument
    const walker = doc.createTreeWalker(range.commonAncestorContainer, NodeFilter.SHOW_TEXT)
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!node.nodeValue.trim() || !range.intersectsNode(node)) continue
        const point = doc.createRange()
        point.setStart(node, 0)
        point.collapse(true)
        return view.getCFI(view.renderer.getContents().find(c => c.doc === doc)?.index, point)
    }
    return null
}
const out = { pages: 0, pointSame: 0, rangeSame: 0, textSame: 0, elementStarts: 0, misses: [] }
for (let i = 0; i < view.book.sections.length; i += __STEP__) {
    if (!view.book.sections[i].load || view.book.sections[i].linear === 'no') continue
    await view.goTo(i)
    await sleep(120)
    for (let t = 0; t < __TURNS__; t++) {
        await view.next()
        await sleep(120)
    }
    await sleep(200)
    const original = page()
    if (!original.start) continue
    const text = textStart()
    if (view.lastLocation?.range?.startContainer?.nodeType !== 3) out.elementStarts++
    out.pages++
    await view.goTo(0)
    await sleep(120)
    await view.goTo(original.start)
    await sleep(250)
    const byPoint = page()
    await view.goTo(0)
    await sleep(120)
    await view.goTo(original.cfi)
    await sleep(250)
    const byRange = page()
    if (byPoint.cfi === original.cfi) out.pointSame++
    else {
        await view.goTo(original.start)
        await sleep(250)
        out.misses.push({ section: i, original, byPoint, caret: await caret(original.start) })
    }
    if (byRange.cfi === original.cfi) out.rangeSame++
    if (text) {
        await view.goTo(0)
        await sleep(120)
        await view.goTo(text)
        await sleep(250)
        if (page().cfi === original.cfi) out.textSame++
    }
}
return out
