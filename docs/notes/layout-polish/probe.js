// Turns N pages (20 by default) and counts the text edges each page shows:
// one key per distinct "textLeft leftPageRight rightPageLeft textRight", in
// points. A whole foliate page gives one key (or one per page with a short
// last line); a fractional one drifts by up to a point from page to page.
// `size` is foliate's page width, `start` its scroll offset.
const N = globalThis.N ?? 20
const view = document.querySelector('foliate-view')
const renderer = view.renderer
const seen = {}
for (let k = 0; k < N; k++) {
    const report = await window.octavo.layoutReport()
    const key = [report.textLeft, report.leftPageRight, report.rightPageLeft, report.textRight]
        .map(x => x == null ? null : +x.toFixed(3)).join(' ')
    seen[key] = (seen[key] || 0) + 1
    await window.octavo.next()
    await new Promise(resolve => setTimeout(resolve, 120))
}
return { size: renderer.size, start: renderer.start, seen }
