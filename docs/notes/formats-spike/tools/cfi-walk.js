// Formats spike: walks the open book and records, for every __STEP__th
// section, the CFI and first words after going to the section and turning
// __TURNS__ pages. Running it with and without harden.js shows whether the
// sanitizer changes positions (it must not). A function body, like collect.js.
const view = document.querySelector('foliate-view')
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
const out = []
for (let i = 0; i < view.book.sections.length; i += __STEP__) {
    if (!view.book.sections[i].load || view.book.sections[i].linear === 'no') continue
    await view.goTo(i)
    await sleep(150)
    for (let t = 0; t < __TURNS__; t++) {
        await view.next()
        await sleep(150)
    }
    await sleep(250)
    const location = view.lastLocation
    out.push({
        section: i,
        cfi: location?.cfi ?? null,
        words: (location?.range?.toString() ?? '').split(/\s+/).filter(Boolean).slice(0, 8).join(' '),
    })
}
return { harden: globalThis.__octavoHardenLog?.length ?? null, positions: out }
