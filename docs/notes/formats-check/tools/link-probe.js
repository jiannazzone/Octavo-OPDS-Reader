const frameDoc = () => document.querySelector('foliate-view')?.renderer?.getContents?.()[0]?.doc
await new Promise(r => setTimeout(r, 1500))
const doc = frameDoc()
const before = doc?.defaultView?.location?.href
const attrs = id => { const el = doc?.getElementById(id); return el ? [...el.attributes].map(a => `${a.name}=${a.value.slice(0, 20)}`) : null }
const report = { svg: attrs('svg-a'), area: attrs('area'), math: attrs('math'), form: attrs('form'), param: doc ? [...doc.querySelectorAll('param')].map(p => [...p.attributes].map(a => a.name)) : null }
const clicks = {}
for (const id of ['svg-a', 'area', 'math', 'button']) {
  const el = frameDoc()?.getElementById(id)
  if (!el) { clicks[id] = 'gone'; continue }
  const ev = new (el.ownerDocument.defaultView.MouseEvent)('click', { bubbles: true, cancelable: true, composed: true })
  const notCancelled = el.dispatchEvent(ev)
  await new Promise(r => setTimeout(r, 700))
  clicks[id] = { defaultAllowed: notCancelled, frameURL: (frameDoc()?.defaultView?.location?.href ?? 'no frame').slice(0, 30) }
}
return { before: before?.slice(0, 30), nav: window.__nav ?? null, report, clicks }
