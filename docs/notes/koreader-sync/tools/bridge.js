// Run in the reader page by bridge-check.sh, through the debug remote's `js`
// command (a function body). KO (KOReader's own places, [xpointer, words])
// and SEED are put in front of it. Returns JSON:
// - places: 30 places Octavo's bridge would send, at word starts spread over
//   the book, each with the words the bridge itself says it names.
// - ko: each of KOReader's places with the words the bridge resolves it to.
let seed = SEED
const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const view = document.querySelector('foliate-view')
const words = async cfi => (await window.octavo.describe(cfi))?.excerpt ?? ''
const candidates = []
for (const [index, section] of view.book.sections.entries()) {
    const doc = await section.createDocument()
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (node.data.trim().length > 20) candidates.push([index, node])
    }
}
const places = []
for (let k = 0; k < 30 && candidates.length; k++) {
    const [index, node] = candidates.splice(Math.floor(random() * candidates.length), 1)[0]
    const starts = [...node.data.matchAll(/(?<!\S)\S/g)].map(m => m.index)
    const range = node.ownerDocument.createRange()
    range.setStart(node, starts[Math.floor(random() * starts.length)])
    range.collapse(true)
    const xpointer = await window.octavo.xpointerAt(view.getCFI(index, range))
    const found = xpointer ? await window.octavo.resolveXPointer(xpointer) : null
    places.push({ id: String(k), xpointer, words: found ? await words(found.cfi) : null })
}
const ko = []
for (const [xpointer, text] of KO) {
    const found = await window.octavo.resolveXPointer(xpointer)
    ko.push({ xpointer, text, words: found ? await words(found.cfi) : null })
}
return JSON.stringify({ places, ko })
