// Formats spike: the one KF8 restore miss, and the guard that fixes it.
// Finds "FEW days after this visit" (P&P, chapter LV), shows the page that
// starts there, leaves, goes back to that page's point CFI, and if the page
// that comes back ends before the point, turns one page (the guard). Run on
// pride-and-prejudice.{azw3,epub,mobi,fb2} with probe.swift.
const CFI = await import('./foliate-js/epubcfi.js')
const view = document.querySelector('foliate-view')
const sleep = ms => new Promise(r => setTimeout(r, ms))
for (let i = 0; i < view.book.sections.length; i++) {
    const s = view.book.sections[i]
    if (!s.createDocument) continue
    const doc = await s.createDocument()
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        const at = n.nodeValue.indexOf('FEW days after this visit')
        if (at < 0) continue
        const range = doc.createRange(); range.setStart(n, at); range.setEnd(n, at + 3)
        const target = view.getCFI(i, range)
        await view.goTo(target); await sleep(400)
        const page = view.lastLocation
        const start = CFI.collapse(page.cfi)
        const words = page.range.toString().split(/\s+/).filter(Boolean).slice(0, 6).join(' ')
        await view.goTo(0); await sleep(200)
        await view.goTo(start); await sleep(400)
        let back = view.lastLocation
        // Guard: if the page ends before the point, the point is on a later page.
        const endsBefore = CFI.compare(CFI.collapse(back.cfi, true), start) < 0
        if (endsBefore) { await view.next(); await sleep(400); back = view.lastLocation }
        return { endsBefore,  section: i, page: page.cfi, words, back: back.cfi, backWords: back.range.toString().split(/\s+/).filter(Boolean).slice(0, 6).join(' '), same: back.cfi === page.cfi }
    }
}
return 'not found'
