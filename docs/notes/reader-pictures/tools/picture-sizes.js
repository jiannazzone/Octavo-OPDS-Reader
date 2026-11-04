// Function body for ReaderRemote's `js` command, with SECTION replaced by a
// section index. Opens that section and measures every picture against the
// text column it sits in. `over` is how far a picture or a box around it runs
// past the column's sides, in points; `tall` how far past the page's height.
const view = document.querySelector('foliate-view')
const renderer = view.renderer
const index = SECTION
const sections = view.book.sections
if (index >= sections.length) return { done: true }
if (sections[index].linear === 'no') return { index, skipped: true }
await renderer.goTo({ index })
const content = renderer.getContents().find(c => c.index === index)
if (!content) return { index, skipped: true }
const doc = content.doc
const pictures = [...doc.body.querySelectorAll('img, svg, video')]
await Promise.all(pictures.map(p => p.decode?.().catch(() => {})))
await new Promise(resolve => setTimeout(resolve, 200))

const style = doc.defaultView.getComputedStyle(doc.documentElement)
const root = doc.documentElement.getBoundingClientRect()
const gap = parseFloat(style.columnGap) || 0
const columns = renderer.heads?.length || 1
const pitch = root.width / columns
const columnWidth = pitch - gap
const top = parseFloat(style.paddingTop) || 0
const round = x => Math.round(x * 10) / 10
// A box that breaks across columns has a rect in each.
const overBy = b => {
    const left = Math.floor(b.left / pitch + 0.001) * pitch + gap / 2
    return Math.max(b.right - (left + columnWidth), left - b.left, 0)
}
const measure = picture => {
    const box = picture.getBoundingClientRect()
    // A picture that breaks across columns (Pride and Prejudice's drop caps,
    // by their negative top margin) has one rect over both: it isn't wide.
    const split = box.width > parseFloat(doc.defaultView.getComputedStyle(picture).width) + 1
    let wrapperOver = 0
    for (let up = picture.parentElement; up && up !== doc.body; up = up.parentElement) {
        for (const b of up.getClientRects()) if (b.width) wrapperOver = Math.max(wrapperOver, overBy(b))
    }
    return {
        id: picture.id || null,
        src: (picture.getAttribute('src') ?? picture.tagName).replace(/^.*[/_]/, ''),
        parentWidth: picture.parentElement?.style?.width || null,
        width: round(box.width),
        height: round(box.height),
        split,
        over: split ? 0 : round(overBy(box)),
        wrapperOver: round(wrapperOver),
        tall: round(Math.max(box.height - root.height, 0)),
    }
}
return {
    index,
    pages: Math.round(renderer.pages ?? 0),
    columns,
    columnWidth: round(columnWidth),
    pageHeight: round(root.height),
    wrappers: doc.body.querySelectorAll(':has(img, svg, video)').length,
    pictures: pictures.map(measure),
}
