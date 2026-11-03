await new Promise(r => setTimeout(r, 1500))
const contents = document.querySelector('foliate-view')?.renderer?.getContents?.() ?? []
const doc = contents[0]?.doc
return {
  ran1: window.__tpl1 ?? null, ran2: window.__tpl2 ?? null,
  shadow: Boolean(doc?.getElementById('host')?.shadowRoot),
  templates: doc ? [...doc.querySelectorAll('template')].map(t => ({ attrs: [...t.attributes].map(a => a.name), inner: t.innerHTML.slice(0, 120) })) : null,
  text: doc?.body?.textContent?.replace(/\s+/g, ' ').trim().slice(0, 80) ?? null,
}
