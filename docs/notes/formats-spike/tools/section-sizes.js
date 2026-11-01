// Formats spike: foliate's size for the book's first section, against the
// whole book. Percentages come from these sizes. A function body, like
// collect.js; run it with probe.swift.
const view = document.querySelector('foliate-view')
const sizes = view.book.sections.map(section => section.size ?? 0)
const total = sizes.reduce((a, b) => a + b, 0)
return { first: sizes[0], total, share: sizes[0] / total }
