// Function body for js.sh: counts foliate renders (patched on the paginator's
// prototype, so the bridge's own no-op shadowing is not counted), relocations,
// page resizes, layout attribute changes and painted states, into window.__fold.
if (window.__fold) return 'already'
const view = document.querySelector('foliate-view')
const r = view.renderer
const F = window.__fold = { events: [], renders: 0 }
const now = () => Math.round(performance.now())
const log = (type, extra = {}) => F.events.push({ t: now(), wall: Date.now(), type, w: innerWidth, h: innerHeight, ...extra })
addEventListener('resize', () => log('resize'))
const proto = Object.getPrototypeOf(r)
const original = proto.render
proto.render = function (...a) {
  F.renders++
  const stack = (new Error().stack || '').split('\n').slice(1, 4).map(s => s.split('@')[0]).join('<')
  log('render', { by: stack, cols: getComputedStyle(r).getPropertyValue('--_max-column-count') })
  return original.apply(this, a)
}
r.addEventListener('relocate', e => log('relocate', { reason: e.detail.reason }))
new MutationObserver(ms => ms.forEach(m => log('attr', { name: m.attributeName, value: m.target.getAttribute(m.attributeName) }))).observe(r, { attributes: true, attributeFilter: ['max-column-count', 'gap', 'max-inline-size', 'max-column-count-portrait'] })
new MutationObserver(() => log('insets', { style: view.getAttribute('style') })).observe(view, { attributes: true, attributeFilter: ['style'] })
let last = ''
const frame = () => {
  const key = `${innerWidth}x${innerHeight} heads=${r.heads?.length} start=${r.start} cfi=${view.lastLocation?.cfi ?? ''}`
  if (key !== last) { log('paint', { key }); last = key }
  requestAnimationFrame(frame)
}
requestAnimationFrame(frame)
return 'installed'
