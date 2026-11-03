const o = window.octavo
await o.goToFraction(0)
await new Promise(r => setTimeout(r, 400))
const pages = []
let same = 0, before = null
for (let i = 0; i < 4000 && same < 3; i++) {
  const text = await o.visibleText(80)
  const report = await o.layoutReport()
  const page = { i, text, boxes: report?.textBoxes ?? null, images: document.querySelector('foliate-view')?.renderer?.getContents?.().reduce((n, c) => n + c.doc.images.length, 0) ?? null }
  pages.push(page)
  const key = text + '|' + page.boxes
  same = key === before ? same + 1 : 0
  before = key
  await o.next()
  await new Promise(r => setTimeout(r, 120))
}
return { count: pages.length, blank: pages.filter(p => !p.text && !p.boxes), pages }
