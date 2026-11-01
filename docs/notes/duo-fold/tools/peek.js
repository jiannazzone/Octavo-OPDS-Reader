// Function body for js.sh: how many events instrument.js holds, and when the last was.
const F = window.__fold
if (!F) return null
return { n: F.events.length, last: F.events.length ? F.events[F.events.length - 1].t : null, now: Math.round(performance.now()) }
