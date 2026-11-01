// Function body for js.sh: returns and clears what instrument.js recorded.
const F = window.__fold
if (!F) return null
const out = { renders: F.renders, events: F.events }
F.events = []; F.renders = 0
return out
