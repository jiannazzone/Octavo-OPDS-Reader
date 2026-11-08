/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// Octavo's bridge between Swift and foliate-js.
//
// JS → Swift: every message is a JSON string posted to the `octavo` script
// message handler, shaped `{ type, ...payload }`. Swift decodes it in
// `ReaderMessage.swift`; keep the two in step.
//
// Swift → JS: `window.octavo.open/goTo/goToFraction/next/prev/setLayout/
// turn/visibleText/...`, called with `WebPage.callJavaScript`. Each returns a
// promise that Swift awaits.

import { makeBook } from './foliate-js/view.js'
import * as CFI from './foliate-js/epubcfi.js'
import { Overlayer } from './foliate-js/overlayer.js'
import { searchMatcher } from './foliate-js/search.js'
import { textWalker } from './foliate-js/text-walker.js'

const HANDLER = 'octavo'

// How taps behave (Swift's `ReaderTapMode`). In every posture a tap left of
// the middle goes back and right of it goes forward, the side column (where
// the page runs under it) with the right; the controls come up only from the
// column's own button (Adam, 2026-11-02). `dismisses` means the controls
// cover the page, so any tap hides them.
let tapMode = { dismisses: false }

const post = (type, payload = {}) => {
    const handler = window.webkit?.messageHandlers?.[HANDLER]
    if (!handler) return
    try {
        handler.postMessage(JSON.stringify({ type, ...payload }))
    } catch (e) {
        handler.postMessage(JSON.stringify({ type: 'error', phase: 'post', message: String(e) }))
    }
}

const describe = error => error instanceof Error
    ? { message: error.message, name: error.name, stack: error.stack ?? null }
    : { message: String(error) }

const finiteOrNull = x => typeof x === 'number' && Number.isFinite(x) ? x : null

// The page's size, which can be larger than the SwiftUI view's frame (the
// web view draws under the safe areas). Swift lays out against it.
//
// It's the root element's size, which `foliate-view` (fixed to the viewport)
// fills. After a cold launch WebKit lays the page out at its full size while
// `innerWidth` still reports the SwiftUI frame's, then corrects `innerWidth`
// with only a `visualViewport` resize; reading `innerWidth` on `resize` left
// Swift laying out for the smaller size until the next fold.
let lastViewport = null
const postViewport = () => {
    const { clientWidth: width, clientHeight: height } = document.documentElement
    if (`${width}x${height}` === lastViewport) return
    lastViewport = `${width}x${height}`
    post('viewport', { width, height })
}
new ResizeObserver(postViewport).observe(document.documentElement)

window.addEventListener('error', e =>
    post('error', { phase: 'script', message: e.message, source: e.filename ?? null, line: e.lineno ?? null }))
window.addEventListener('unhandledrejection', e =>
    post('error', { phase: 'promise', ...describe(e.reason) }))

// foliate-js reports recoverable problems (a section that won't load, a CFI
// that won't resolve) with console.error/warn. Forward them so they show up
// in Xcode's console.
for (const level of ['error', 'warn']) {
    const original = console[level].bind(console)
    console[level] = (...args) => {
        original(...args)
        post('log', { level, message: args.map(a => a instanceof Error ? a.message : String(a)).join(' ') })
    }
}

// Metadata titles are a string or a `{ lang: string }` map.
const plainText = value => {
    if (typeof value === 'string') return value
    if (value && typeof value === 'object') return Object.values(value).find(v => typeof v === 'string') ?? null
    return null
}

let view = null
// The page layout Swift asked for (`ReaderLayout`), kept across books.
let layout = null

// foliate reports the visible page as a range CFI. BookOrbit's web reader
// stores a collapsed point at the start of the page instead. This is the same
// point for pages that start in text, which is most of them.
const startOf = cfi => {
    try {
        return cfi ? CFI.collapse(cfi) : null
    } catch {
        return null
    }
}

// On a page with no visible node (a blank column after a forced break),
// stock foliate falls back to the section's <body>, so the CFI only names the
// section and reopening it lands on the section's first page. Our patch 0001
// (foliate-js/PINNED.md) reports the next content instead, so this only
// matters if that patch is ever dropped.
const isBlankPage = range => {
    const container = range?.startContainer
    return Boolean(container && container === container.ownerDocument?.body)
}

// Where a fixed-layout page sits in the book, to save and sync. foliate
// reports the section's end, which is the next section's start: going back by
// it lands a page late, and BookOrbit's web reader only goes by this number on
// these books (`docs/notes/fixed-layout.md`). So it's a point just inside the
// section, past what its percentage's rounding can move. The last page is 1.
const FIXED_PAGE_MARGIN = 1e-5
const fixedPageFraction = detail => {
    const index = detail.section?.current
    const fractions = view.getSectionFractions()
    const [start, end] = [fractions[index], fractions[index + 1]]
    if (start === undefined || end === undefined) return finiteOrNull(detail.fraction)
    if (index === fractions.length - 2) return 1
    return finiteOrNull(end - Math.min((end - start) / 2, FIXED_PAGE_MARGIN))
}

// The sections on screen in fixed layout: the spread's pages, or just the one
// while one shows (foliate's own rule; `applyAttributes` sets `spread`).
const fixedPagesShown = () => {
    const { renderer, book } = view
    const current = renderer.index
    const { width, height } = renderer.getBoundingClientRect()
    if (renderer.spread !== 'both' && renderer.spread !== 'portrait' && height > width) return [current]
    const spread = renderer.getSpreadOf(book.sections[current])?.index
    return [current - 1, current, current + 1]
        .filter(index => book.sections[index] && renderer.getSpreadOf(book.sections[index])?.index === spread)
}

// A fixed-layout page's relocation. For the footer, the bar and the panels:
// the book's own pages, as foliate's locations count bytes, with the place at
// the end of the last page on screen, like a reflowing page's. To save and
// sync: foliate's page in the spread, except that a spread holding the book's
// last page has no further turn, so reading it is finishing the book, whichever
// side foliate is on.
const fixedPlace = detail => {
    const shown = fixedPagesShown()
    const total = view.book.sections.length
    const last = shown.at(-1)
    return {
        ...(last === total - 1 ? { cfi: view.getCFI(last), fraction: 1 } : { fraction: fixedPageFraction(detail) }),
        location: { current: shown[0], next: last, total },
        pageFraction: (last + 1) / total,
    }
}

// Where each section starts, for those same places. On fixed layout it's a
// hair inside the page, so a page's place (its end) falls before the next
// page's start.
const FIXED_PAGE_START = 1e-7
const sectionFractions = () => {
    if (!view.isFixedLayout) return view.getSectionFractions()
    const total = view.book.sections.length
    return Array.from({ length: total + 1 }, (_, index) => index / total + FIXED_PAGE_START)
}

// While a fold is held (see `hold`), relocations are kept back and only the
// last one is posted once the new layout has settled.
let held = null
// Counts relocations, so `settle` can tell when the paginator has stopped
// moving.
let relocations = 0
// Called with each relocation's detail and message (`turn` waits on them).
const relocationWatchers = new Set()

// Why the renderer last moved ('page' and 'snap' are turns), which foliate's
// own relocate event leaves out.
let lastRelocateReason = null

// Whether there's a page to each side, for a curl under a finger, which
// UIKit asks about as the finger lands (`ReaderCurl`): the paginator's own
// ends, or on fixed layout whether the book's first or last page is shown.
const turnsFrom = r => {
    let atStart = r?.atStart
    let atEnd = r?.atEnd
    if (view.isFixedLayout) {
        const shown = fixedPagesShown()
        if (!shown.length) return {}
        atStart = shown[0] === 0
        atEnd = shown.at(-1) === view.book.sections.length - 1
    }
    if (typeof atStart !== 'boolean' || typeof atEnd !== 'boolean') return {}
    const forward = forwardSide()
    return {
        turnsLeft: forward === 'left' ? !atEnd : !atStart,
        turnsRight: forward === 'right' ? !atEnd : !atStart,
    }
}

const onRelocate = ({ detail }) => {
    relocations++
    const message = {
        cfi: detail.cfi ?? null,
        reason: lastRelocateReason,
        blankPage: isBlankPage(detail.range),
        fraction: finiteOrNull(detail.fraction),
        tocLabel: detail.tocItem?.label?.trim() || null,
        tocHref: detail.tocItem?.href ?? null,
        sectionIndex: detail.section?.current ?? null,
        sectionCount: detail.section?.total ?? null,
        location: detail.location
            ? {
                current: finiteOrNull(detail.location.current),
                next: finiteOrNull(detail.location.next),
                total: finiteOrNull(detail.location.total),
            }
            : null,
        ...(view.isFixedLayout ? fixedPlace(detail) : {}),
        ...turnsFrom(view.renderer),
    }
    message.startCFI = startOf(message.cfi)
    message.xpointer = writesXPointers && !view.isFixedLayout ? xpointerOf(detail.section?.current, startNodeOf(detail.range)) : null
    for (const watch of relocationWatchers) watch(detail, message)
    if (held) held.relocation = message
    else post('relocate', message)
}

// A tap is a short press that barely moves. Anything longer or further is a
// swipe (foliate's paginator handles those) or a text selection.
const TAP_SLOP = 10
const TAP_MAX_MS = 500

// Taps are detected from pointer events: iOS WebKit doesn't dispatch `click`
// to a document-level listener when the tapped element isn't itself
// clickable, which is most of a book. `onTap` gets the tap's x in the top
// window's coordinates.
const detectTaps = (doc, onTap) => {
    let down = null
    doc.addEventListener('pointerdown', e => {
        down = e.isPrimary ? { id: e.pointerId, x: e.screenX, y: e.screenY, time: e.timeStamp } : null
    })
    doc.addEventListener('pointercancel', () => down = null)
    doc.addEventListener('pointerup', e => {
        const start = down
        down = null
        if (!start || e.pointerId !== start.id) return
        if (Math.abs(e.screenX - start.x) > TAP_SLOP || Math.abs(e.screenY - start.y) > TAP_SLOP) return
        if (e.timeStamp - start.time > TAP_MAX_MS) return
        if (e.target?.closest?.('a[href]')) return
        if (!(doc.getSelection()?.isCollapsed ?? true)) return
        onTap(e)
    })
}

// Page turns (decision 27). With any Page Turn but None, Swift draws each
// turn from snapshots of the page: a tap, a key or the trackpad asks for one
// with a `turn` message (a finger's swipe is Swift's own), and Swift then
// turns the page under its snapshot with `turn` below. With None the page
// turns itself, at once, and a swipe drags it as foliate's paginator does.
let turnsAnimated = false

// Sides are physical: `right` is the right-hand page going (foliate's
// goRight), forward in a left-to-right book.
const forwardSide = () => view?.book?.dir === 'rtl' ? 'left' : 'right'
const backSide = () => forwardSide() === 'left' ? 'right' : 'left'
const askTurn = side => {
    if (!view) return
    if (!turnsAnimated) return side === 'left' ? view.goLeft() : view.goRight()
    post('turn', { side })
}

// Left and right turn pages the way the book reads (foliate's goLeft and
// goRight), so in a right-to-left book the left half goes forward. The
// middle is the middle of foliate's view: the spine of a spread, or the
// middle of the one page folded.
const tap = x => {
    if (tapMode.dismisses) return post('tap', { zone: 'dismiss' })
    const box = view?.getBoundingClientRect()
    const middle = box ? box.left + box.width / 2 : innerWidth / 2
    askTurn(x < middle ? 'left' : 'right')
}

// A hardware keyboard turns pages (step 10): ← and → the way the book reads,
// like the halves of the page; ↑, ↓, Page Up, Page Down and Space (Shift-Space
// back) through the book. Without this the web view scrolls the paginator by
// a few points and leaves the page between two. Shift with an arrow extends
// a selection, so it's left alone; while the controls cover the page a key
// hides them, as a tap does.
const KEY_TURNS = {
    ArrowLeft: () => askTurn('left'),
    ArrowRight: () => askTurn('right'),
    ArrowUp: () => askTurn(backSide()),
    PageUp: () => askTurn(backSide()),
    ArrowDown: () => askTurn(forwardSide()),
    PageDown: () => askTurn(forwardSide()),
}
const onKeyDown = e => {
    if (e.metaKey || e.ctrlKey || e.altKey || e.isComposing) return
    if (e.shiftKey && e.key !== ' ') return
    const turn = e.key === ' ' ? () => askTurn(e.shiftKey ? backSide() : forwardSide()) : KEY_TURNS[e.key]
    if (!turn) return
    e.preventDefault()
    if (tapMode.dismisses) return post('tap', { zone: 'dismiss' })
    turn()
}

// A trackpad's two-finger swipe (wheel events) turns one page per swipe, the
// way it points: sideways like the halves of the page, up and down through
// the book. A swipe is the run of events until they pause, or until a new
// push (a jump in speed during the last swipe's momentum) or a change of
// direction; the paginator's own scrolling would leave the page between
// two. Pinch (Ctrl) is left alone. While the controls cover the page a swipe
// hides them, as a tap does.
const WHEEL_DISTANCE = 30
const WHEEL_PAUSE_MS = 250
const WHEEL_PUSH = 1.5
let wheel = null
const onWheel = e => {
    if (e.ctrlKey) return
    e.preventDefault()
    const size = Math.hypot(e.deltaX, e.deltaY)
    const fresh = !wheel || e.timeStamp - wheel.last > WHEEL_PAUSE_MS
        || (wheel.turned && size > wheel.size * WHEEL_PUSH && size > 4)
        || (wheel.turned && e.deltaX * wheel.dx + e.deltaY * wheel.dy < 0)
    if (fresh) wheel = { dx: 0, dy: 0, turned: false, last: 0, size: 0 }
    wheel.last = e.timeStamp
    wheel.size = size
    if (wheel.turned) return
    wheel.dx += e.deltaX
    wheel.dy += e.deltaY
    const sideways = Math.abs(wheel.dx) >= Math.abs(wheel.dy)
    const distance = sideways ? wheel.dx : wheel.dy
    if (Math.abs(distance) < WHEEL_DISTANCE) return
    wheel.turned = true
    if (tapMode.dismisses) return post('tap', { zone: 'dismiss' })
    if (sideways) askTurn(distance > 0 ? 'right' : 'left')
    else askTurn(distance > 0 ? forwardSide() : backSide())
}

// A finger turning the page, while Swift draws the turns, is recognised in
// UIKit (`ReaderSwipeRecognizer`): once a turn starts under the finger,
// WebKit stops passing that touch to the page. Here foliate's own drag is
// kept out of it: its listeners (on the document and the paginator) never
// see a touch, and every move is prevented, as foliate does, so the page
// never scrolls. Swift is told when text is selected, so a finger moving a
// selection's handle doesn't turn the page.
const muteTouch = e => {
    if (!turnsAnimated) return
    e.stopPropagation()
    if (e.type === 'touchmove' && e.touches.length === 1) e.preventDefault()
}
// Capturing, on the section's document or the top window, so it runs
// before foliate's listeners.
const muteTouches = target => {
    const options = { capture: true, passive: false }
    for (const type of ['touchstart', 'touchmove', 'touchend', 'touchcancel']) target.addEventListener(type, muteTouch, options)
}
let selecting = false
const onSelectionChange = doc => () => {
    const now = hasSelection(doc)
    if (now === selecting) return
    selecting = now
    post('selection', { active: now })
}
const hasSelection = doc => !(doc?.getSelection?.()?.isCollapsed ?? true)

const listenForTurns = doc => {
    doc.addEventListener('keydown', onKeyDown)
    doc.addEventListener('wheel', onWheel, { passive: false })
}

// Forced page breaks that can only make a blank page (Project Gutenberg's
// chapters start `div.chapter > h2`, both breaking before):
// - At the very start of a section. foliate starts every section on a new
//   page already, and WebKit breaks anyway, leaving the first page blank.
// - Inside another, at its very start: the outer box's top margin moves the
//   inner one a little way down the new page, so WebKit breaks again.
// - After empty spacing (Gutenberg's `<div style="height: 4em">` before each
//   chapter heading): when the page before is full, the spacing spills onto a
//   page of its own, and the break then leaves that page blank (even spacing
//   collapsed to nothing lands there). The break moves up to before the
//   spacing, which then opens the chapter's page, as the book means it to;
//   an empty `<a id>` the contents point at moves with it.
// Runs once the section has loaded, before foliate lays it out. Styles only:
// the DOM, and so every CFI, stays as the book has it.
const FORCED_BREAKS = new Set(['page', 'column', 'left', 'right', 'recto', 'verso', 'always'])
const collapseBlankPageBreaks = doc => {
    const style = el => doc.defaultView?.getComputedStyle(el)
    const forced = el => FORCED_BREAKS.has(style(el)?.breakBefore) || FORCED_BREAKS.has(style(el)?.pageBreakBefore)
    // An element's first content: an element, or text with something in it
    // (not a comment). Stops at the first one, so each parent is cheap.
    const firstContent = el => {
        for (const node of el.childNodes) {
            if (node.nodeType === Node.ELEMENT_NODE) return node
            if ((node.nodeType === Node.TEXT_NODE || node.nodeType === Node.CDATA_SECTION_NODE) && node.textContent.trim()) return node
        }
        return null
    }
    const unbreak = el => {
        el.style.setProperty('break-before', 'auto', 'important')
        el.style.setProperty('page-break-before', 'auto', 'important')
    }
    // The section's first content, all the way down: a page starts there
    // already.
    const sectionStart = new Set()
    for (let el = doc.body && firstContent(doc.body); el?.nodeType === Node.ELEMENT_NODE; el = firstContent(el)) {
        sectionStart.add(el)
        if (forced(el)) unbreak(el)
    }
    // Nothing to see: no text, and nothing drawn (a rule or a picture is
    // something).
    const VISIBLE = 'img, svg, video, audio, canvas, iframe, object, embed, math, hr, table'
    const isSpacing = el => !el.textContent.trim() && !el.matches(VISIBLE) && !el.querySelector(VISIBLE)
    // The first of the spacing just before `el`: its empty previous
    // siblings, and its parent's while it's the parent's first content.
    const spacingBefore = el => {
        let first = null
        for (let box = el; box && box !== doc.body; box = box.parentElement) {
            let prev = box.previousElementSibling
            for (; prev && isSpacing(prev); prev = prev.previousElementSibling) first = prev
            if (prev || firstContent(box.parentElement) !== box) break
        }
        return first
    }
    // Each breaking box once, with its own first content: linear in the
    // section's size, give or take the spacing walked over.
    for (const parent of doc.body?.querySelectorAll('*') ?? []) {
        if (!forced(parent)) continue
        const spacing = spacingBefore(parent)
        if (spacing) {
            // The break as the page has it (foliate's columns make a page
            // break a column break).
            const value = style(parent)?.breakBefore
            unbreak(parent)
            if (!sectionStart.has(spacing)) {
                // `page-break-before` first: it sets `break-before` too, and
                // inside columns WebKit only honours a column break.
                spacing.style.setProperty('page-break-before', 'always', 'important')
                spacing.style.setProperty('break-before', FORCED_BREAKS.has(value) ? value : 'page', 'important')
                // An empty box (`<p><a id></a></p>`) collapses to nothing,
                // and WebKit ignores a break before it.
                spacing.style.setProperty('min-height', '1px', 'important')
            }
        }
        const first = firstContent(parent)
        if (first?.nodeType === Node.ELEMENT_NODE && forced(first)) unbreak(first)
    }
}

// Section documents live in iframes that are wider than the screen (one
// column per page) and scrolled by the paginator, or scaled to fit (fixed
// layout), so the tap is converted to the top window's coordinates before
// deciding which side it was on.
// Part of the hardening layer (`open`'s `harden`), so the DEBUG switch
// measures the layer whole.
let guardsLinks = true

// What BOOK_STYLES can't say, since it depends on the book's own value. A
// limit the book sets on a picture in points stays, but not past its box:
// foliate keeps a limit that's already set when it sizes pictures, which it
// does after this, and a percentage needs no help. A table box around a
// picture keeps its width the same way: WebKit ignores `max-width` on a table.
// A size this small fits any column, so it stays in points. A percentage can't
// size a float or an inline-block around the picture, which would grow to the
// column and push the text out from beside it. That leaves a limit of 0 to
// foliate too, which takes it to mean none.
const FITS_ANY_COLUMN = 200
const limitPicturesToTheirBoxes = doc => {
    const limit = (element, property, value) => {
        if (value.endsWith('px') && parseFloat(value) > FITS_ANY_COLUMN) element.style.setProperty(property, `min(${value}, 100%)`, 'important')
    }
    const style = element => doc.defaultView.getComputedStyle(element)
    for (const picture of doc.body?.querySelectorAll('img, svg, video') ?? []) limit(picture, 'max-inline-size', style(picture).maxInlineSize)
    for (const box of doc.body?.querySelectorAll(':has(img, svg, video)') ?? []) {
        const { display, inlineSize } = style(box)
        if (display === 'table' || display === 'inline-table') limit(box, 'inline-size', inlineSize)
    }
}

const onSectionLoad = ({ detail: { doc } }) => {
    // A click on a link foliate doesn't intercept (an SVG or MathML link,
    // an image map's area) goes nowhere: the hardening layer already took
    // their targets, and this holds if a target slipped through.
    if (guardsLinks) doc.addEventListener('click', e => {
        for (const el of e.composedPath()) {
            if (el.nodeType !== Node.ELEMENT_NODE) continue
            if (el.localName === 'a' && el.namespaceURI === XHTML_NS && el.hasAttribute('href')) return
            if (el.localName === 'area' || (el.localName !== 'image' && el.localName !== 'use'
                && (el.hasAttribute('href') || el.hasAttributeNS(XLINK, 'href')))) {
                e.preventDefault()
                return
            }
        }
    }, true)
    collapseBlankPageBreaks(doc)
    // A fixed-layout page places its pictures itself.
    if (!view.isFixedLayout) limitPicturesToTheirBoxes(doc)
    detectTaps(doc, async e => {
        const frame = doc.defaultView?.frameElement
        if (!frame) return
        const box = frame.getBoundingClientRect()
        const x = box.left + e.clientX * (view?.isFixedLayout && frame.offsetWidth ? box.width / frame.offsetWidth : 1)
        // A near miss on a note's tiny mark doesn't turn the page.
        const mark = tapMode.dismisses ? null : nearNoteMark(doc, e.clientX, e.clientY)
        if (mark && await openNote(mark, resolvedHref(mark, doc))) return
        tap(x)
    })
    listenForTurns(doc)
    muteTouches(doc)
    doc.addEventListener('selectionchange', onSelectionChange(doc))
}

// Taps outside the section's frame: the page's margins, and the side column
// where the page runs under it.
detectTaps(document, e => tap(e.clientX))
listenForTurns(document)
muteTouches(window)

// Styles every book gets (step 11), as foliate's [before, after] pair.
// Before the book's own, so a book that says otherwise wins: hyphenation in
// running text, so justified lines don't open wide gaps between words on a
// narrow page, and long words or web addresses breaking rather than running
// off it. After the book's own: preformatted text wraps. Project Gutenberg
// sets verse in <pre>, and a line that doesn't wrap runs out of its column,
// over the spine and onto the next page (and the page before's overflow
// shows at this one's edge). And a box around a picture stays inside its
// column: foliate limits a picture to 100% of its box, and Project Gutenberg's
// boxes are as wide as the printed picture (`docs/notes/reader-pictures.md`).
// Only boxes around pictures, so pages of text lay out as the book says.
const BOOK_STYLES = [`
p, li, blockquote, dd {
    -webkit-hyphens: auto;
    hyphens: auto;
    -webkit-hyphenate-limit-before: 3;
    -webkit-hyphenate-limit-after: 2;
    -webkit-hyphenate-limit-lines: 2;
}
html {
    overflow-wrap: break-word;
}
`, `
pre {
    white-space: pre-wrap !important;
}
body :has(img, svg, video) {
    max-inline-size: -webkit-fill-available !important;
}
`]

// The reader's Text and theme choices (Swift's `ReaderAppearance`): CSS that
// goes after the book's own, and the colour of the page around the text.
let appearance = { css: '', background: '' }
const applyAppearance = () => {
    // Fixed layout has no such thing: its pages are as the book drew them.
    view?.renderer.setStyles?.([BOOK_STYLES[0], BOOK_STYLES[1] + appearance.css])
    document.documentElement.style.background = appearance.background
}

// Lays pages out the way Swift's `ReaderLayout` says: column count, gap and
// text width through foliate's own attributes, and the view's insets, which
// keep it out of the system's areas (the page itself runs edge to edge) and
// put foliate's centred gap over the fold. `max-column-count-
// portrait` is our patch 0002; without it a portrait reader area always gets
// one column. Missing values fall back to foliate's defaults.
//
// Also ends a hold: the view gets its normal size back (inset from the
// window's edges) in the same step.
const applyAttributes = () => {
    const renderer = view.renderer
    const set = (name, value) => value === null || value === undefined
        ? renderer.removeAttribute(name)
        : renderer.setAttribute(name, String(value))
    Object.assign(view.style, {
        left: `${layout?.leftInset ?? 0}px`,
        right: `${layout?.rightInset ?? 0}px`,
        top: `${layout?.topInset ?? 0}px`,
        bottom: `${layout?.bottomInset ?? 0}px`,
        width: '', height: '',
    })
    set('max-column-count', layout?.columns)
    set('max-column-count-portrait', layout?.columns)
    set('gap', layout?.gapPercent === null || layout?.gapPercent === undefined ? null : `${layout.gapPercent}%`)
    set('max-inline-size', layout?.maxInlineSize === null || layout?.maxInlineSize === undefined ? null : `${layout.maxInlineSize}px`)
    // Fixed layout takes its page count from the view's shape and the book's
    // `rendition:spread`, and the hinge decides here: `landscape` is one page
    // in a portrait view, `both` is two in any. foliate reads `spread` on each
    // render. Folded and sideways still gets two, as the shape is landscape.
    if (view.isFixedLayout) {
        renderer.spread = layout?.columns === 1 ? 'landscape' : layout?.columns === 2 ? 'both' : view.book.rendition?.spread
    }
}

// The paginator's attributes and size, to tell whether anything changed.
const layoutState = () => {
    const renderer = view.renderer
    const { width, height } = renderer.getBoundingClientRect()
    const attributes = ['max-column-count', 'max-column-count-portrait', 'gap', 'max-inline-size']
        .map(name => renderer.getAttribute(name))
    return JSON.stringify([width, height, attributes])
}

// A page off screen draws no frames (its reader has closed), and a Swift call
// that never ends keeps the reader's model and web process alive for good
// (docs/notes/reader-release.md). So nothing waits long for one.
const nextFrame = () => new Promise(resolve => {
    const late = setTimeout(resolve, 1000)
    requestAnimationFrame(() => {
        clearTimeout(late)
        setTimeout(resolve, 0)
    })
})

// Waits until the paginator has stopped relocating for a few frames: after a
// render it re-scrolls to its anchor, and again once the section's body has
// been measured.
const settle = async () => {
    const start = performance.now()
    let seen = relocations
    for (let quiet = 0; quiet < 3 && performance.now() - start < 1000;) {
        await nextFrame()
        if (relocations === seen) quiet++
        else [seen, quiet] = [relocations, 0]
    }
}

// Applies `layout` with a single re-render. foliate re-renders on its own
// whenever `max-inline-size` changes and whenever its size changes (a
// ResizeObserver, one frame later); with our explicit render that's up to
// three re-layouts, each re-scrolling to the anchor. Those are skipped here:
// `render` is shadowed by a no-op on the instance until the ResizeObserver
// has fired, then foliate renders once. This relies on foliate calling
// `this.render()` from both places (paginator.js at the pinned commit).
const applyLayout = async () => {
    if (!view?.renderer) return false
    const renderer = view.renderer
    const before = layoutState()
    renderer.render = () => {}
    try {
        applyAttributes()
        if (layoutState() !== before) await nextFrame()
    } finally {
        delete renderer.render
    }
    const changed = layoutState() !== before
    // A changed column count doesn't always resize anything, so the render
    // is explicit. Re-rendering keeps the paginator's anchor. Fixed layout has
    // no `render`; setting its zoom (to what it's fitting already) does it.
    if (changed) {
        if (view.isFixedLayout) renderer.setAttribute('zoom', 'fit-page')
        else renderer.render()
    }
    return changed
}

// The hinge moved, and a fold's inputs (the hinge, the page's resize, the
// fold region) are about to arrive one by one. Until the next `setLayout`,
// the view keeps its current size, so the page's resize doesn't re-paginate,
// and relocations are kept back.
const hold = () => {
    if (!view?.renderer) return false
    const { width, height } = view.getBoundingClientRect()
    Object.assign(view.style, { width: `${width}px`, height: `${height}px`, right: 'auto', bottom: 'auto' })
    // A new object, so a `setLayout` still settling knows not to end it.
    held = { relocation: held?.relocation ?? null }
    return true
}

// Applies the layout, ends any hold, and posts the last relocation once the
// page has settled.
const setLayout = async newLayout => {
    layout = newLayout
    const ending = held
    const rendered = await applyLayout()
    if (rendered) await settle()
    // Fixed layout reports nothing when it re-lays out, and the pages on
    // screen may have changed.
    if (rendered && view.isFixedLayout && view.lastLocation) onRelocate({ detail: view.lastLocation })
    // Held again meanwhile (folded back): the next `setLayout` ends it.
    if (held !== ending) return rendered
    const pending = held?.relocation
    held = null
    if (pending) post('relocate', pending)
    return rendered
}

// Turns the page to `side` at once (foliate's paginator isn't `animated`),
// under the snapshot Swift has laid over it, and resolves once the new page
// is drawn: whether it moved (not at the book's start or end) and its
// relocation, as JSON, for its footer. Across a section break that's the
// new section's first relocation, not the blank page foliate scrolls to
// while it loads the section.
//
// `hold` (a swipe, which may yet fall back) keeps the relocations back
// until `endTurn`, so a turn that falls back is never saved or synced.
//
// One turn at a time: foliate ignores a turn while the last one finishes
// (its paginator stays locked 100 ms after a turn), so each waits for the
// one before.
let turnQueue = Promise.resolve()
let turnHeld = null
const turn = (side, hold) => {
    const ready = turnQueue.then(() => turnOnce(side, hold))
    turnQueue = ready.then(result => result.done).catch(() => {})
    const result = ready.then(({ moved, relocation }) => ({ moved, relocation }))
    if (hold) turnHeld = { side, ready: result, held: null }
    return result
}
const turnOnce = async (side, hold) => {
    const v = requireView()
    const r = v.renderer
    const forward = (side === 'right') !== (v.book.dir === 'rtl')
    if (forward ? r.atEnd : r.atStart) return { moved: false, relocation: null, done: Promise.resolve() }
    // foliate goes to the next section from its last page, through the blank
    // page after it (`#scrollNext`), and to the one before from its first.
    const crossing = forward ? r.page + 1 >= r.pages - 1 : r.page - 1 <= 0
    const section = v.lastLocation?.section?.current ?? null
    if (hold) {
        held = { relocation: held?.relocation ?? null }
        if (turnHeld) Object.assign(turnHeld, { held, page: r.index })
    }
    let relocation = null
    let watch
    const relocated = new Promise(resolve => {
        watch = (detail, message) => {
            relocation = message
            if (!crossing || (detail.section?.current ?? null) !== section) resolve(true)
        }
        relocationWatchers.add(watch)
    })
    const done = Promise.resolve(side === 'left' ? v.goLeft() : v.goRight())
    const moved = await Promise.race([
        relocated,
        done.then(() => relocation !== null),
        new Promise(resolve => setTimeout(() => resolve(relocation !== null), 2000)),
    ])
    // Two frames, so the new page has reached the screen. A new section's
    // first relocation can still be measuring it, so the latest is sent.
    if (moved) {
        await nextFrame()
        await nextFrame()
    }
    relocationWatchers.delete(watch)
    return { moved, relocation: relocation ? JSON.stringify(relocation) : null, done }
}

// Ends a swipe's turn. `keep` posts the relocation `turn` held back;
// otherwise the page turns back, still held, and as it's where it was,
// nothing is posted. A fold's hold since (`hold`) keeps its own.
const endTurn = async keep => {
    const holding = turnHeld
    turnHeld = null
    if (!holding) return false
    const { moved } = await holding.ready.catch(() => ({ moved: false }))
    if (!keep && moved) {
        await turnQueue
        const back = holding.side === 'left' ? 'right' : 'left'
        // On fixed layout, turning back lands on the spread's other side.
        if (view?.isFixedLayout) await view.goTo(holding.page)
        else await (back === 'left' ? view?.goLeft() : view?.goRight())
        await settle()
    }
    if (holding.held && held === holding.held) {
        const pending = keep ? held.relocation : null
        held = null
        if (pending) post('relocate', pending)
    }
    // Whether the held turn moved (`ReaderModel.curlEnded`).
    return moved
}

// Text boxes of the visible page in the top window's coordinates. Text only:
// a range's element boxes can include fragments from other pages.
const visibleTextRects = () => {
    const range = view?.lastLocation?.range
    if (!range) return []
    const doc = range.startContainer.ownerDocument
    const frameLeft = doc?.defaultView?.frameElement?.getBoundingClientRect().left ?? 0
    const root = range.commonAncestorContainer
    const walker = doc.createTreeWalker(root.nodeType === 3 ? root.parentNode : root, NodeFilter.SHOW_TEXT)
    const rects = []
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!range.intersectsNode(node) || !node.nodeValue.trim()) continue
        const part = doc.createRange()
        part.selectNodeContents(node)
        if (node === range.startContainer) part.setStart(node, range.startOffset)
        if (node === range.endContainer) part.setEnd(node, range.endOffset)
        for (const r of part.getClientRects())
            if (r.width > 0 && r.height > 0) rects.push({ left: r.left + frameLeft, right: r.right + frameLeft })
    }
    return rects
}

// The page's safe-area insets (CSS `env()`), in CSS px.
const safeAreaInsets = () => {
    const probe = document.createElement('div')
    probe.style.cssText = 'position: fixed; visibility: hidden; padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)'
    document.body.append(probe)
    const style = getComputedStyle(probe)
    const insets = ['top', 'right', 'bottom', 'left'].map(side => parseFloat(style[`padding-${side}`]) || 0)
    probe.remove()
    return insets
}

// Where the visible text sits relative to the fold, for checking layouts.
const layoutReport = () => {
    const box = requireView().getBoundingClientRect()
    const rects = visibleTextRects()
    const fold = layout?.fold ?? null
    const mid = fold ? (fold[0] + fold[1]) / 2 : innerWidth / 2
    const left = rects.filter(r => r.right <= mid)
    const right = rects.filter(r => r.left >= mid)
    const edge = (list, f, key) => list.length ? f(...list.map(r => r[key])) : null
    return {
        innerWidth,
        innerHeight,
        scale: visualViewport?.scale ?? null,
        safeArea: safeAreaInsets(),
        view: { left: box.left, width: box.width, height: box.height },
        columns: view.renderer.heads?.length ?? null,
        textLeft: edge(rects, Math.min, 'left'),
        textRight: edge(rects, Math.max, 'right'),
        leftPageRight: edge(left, Math.max, 'right'),
        rightPageLeft: edge(right, Math.min, 'left'),
        fold,
        // Text boxes that touch the fold region (or straddle the middle).
        crossing: rects.filter(r => fold ? r.left < fold[1] && r.right > fold[0] : r.left < mid && r.right > mid).length,
        textBoxes: rects.length,
    }
}

// Whether the visible page contains `cfi`'s start point: compared with the
// page's start and end through foliate's own CFI ordering.
const locate = cfi => {
    const current = requireView().lastLocation?.cfi
    if (!current || !cfi) return null
    if (view.isFixedLayout) {
        const contains = onPage([cfi])[0]
        return { contains, afterStart: contains, beforeEnd: contains }
    }
    const point = CFI.collapse(cfi)
    const afterStart = CFI.compare(CFI.collapse(current), point) <= 0
    const beforeEnd = CFI.compare(point, CFI.collapse(current, true)) <= 0
    return { contains: afterStart && beforeEnd, afterStart, beforeEnd }
}

// After a jump by fraction, foliate keeps the fraction itself as the page's
// anchor, so the next re-layout (a fold, a font change) maps that fraction
// onto the new layout and can land a page or a spread away from the text that
// was showing. Re-anchoring on the visible page's own range keeps that text
// in view, the same as after a page turn. A blank page (collapsed range, see
// patch 0001) keeps its page-fraction anchor.
const anchorToPage = async () => {
    const range = view?.lastLocation?.range
    const cfi = view?.lastLocation?.cfi
    if (!cfi || !range || range.collapsed || view.isFixedLayout) return
    await view.renderer.goTo(view.resolveNavigation(cfi))
}

// The table of contents in reading order, each entry with where its section
// starts in the book (0...1), for naming the chapter at any point of the
// progress bar, and its href and depth for the Contents panel. Entries whose
// target doesn't resolve are left out.
const tocFractions = () => {
    const fractions = sectionFractions()
    const entries = []
    const walk = (items, depth) => {
        for (const item of items ?? []) {
            const label = plainText(item.label)?.trim()
            let index = null
            try {
                index = item.href ? view.resolveNavigation(item.href)?.index : null
            } catch {
                index = null
            }
            if (label && Number.isInteger(index)) {
                entries.push({ label, fraction: finiteOrNull(fractions[index]), href: item.href, depth })
            }
            walk(item.subitems, depth + 1)
        }
    }
    walk(view.book.toc, 0)
    return entries
}

// Whether `value` is a Range. Not `instanceof`: a section on screen lives in
// its own frame, whose Range isn't this window's.
const isRange = value => Boolean(value && typeof value === 'object' && 'startContainer' in value && 'collapsed' in value)

// A Range for whatever a navigation anchor gives (a Range, or a node).
const toRange = (doc, found) => {
    if (isRange(found)) return found
    const range = doc.createRange()
    range.selectNodeContents(found)
    return range
}

// The section on screen, if `index` is it.
const loadedDoc = index => view?.renderer?.getContents?.()?.find(content => content.index === index)?.doc ?? null

// Where a point falls in the section on screen, by the page it's on in the
// current layout: the footer's own count (foliate's paginator places a rect
// on page floor(left / size) + 1, and reports (page - 1) / (pages - 2)).
// `null` for layouts it doesn't map this way (scrolled, vertical,
// right-to-left), which then fall back to counting characters.
const layoutFraction = range => {
    const renderer = view.renderer
    if (renderer.scrolled || view.book.dir === 'rtl' || renderer.hasAttribute?.('vertical')) return null
    const { pages, size } = renderer
    if (!(pages > 2) || !(size > 0)) return null
    const rect = range.getClientRects()[0] ?? range.getBoundingClientRect()
    if (!rect) return null
    return Math.min(Math.max(Math.floor(rect.left / size) / (pages - 2), 0), 1)
}

// Where a point falls in its section by characters: a section that isn't
// laid out has no pages to count.
const characterFraction = (doc, range) => {
    const body = doc.body ?? doc.documentElement
    const before = doc.createRange()
    before.setStart(body, 0)
    before.setEnd(range.startContainer, range.startOffset)
    const length = (body.textContent ?? '').length
    return length > 0 ? Math.min(before.toString().length / length, 1) : 0
}

// A section's place in the book: its start, plus `within` of its share.
const bookFraction = (index, within) => {
    const fractions = sectionFractions()
    const start = fractions[index] ?? 0
    const end = fractions[index + 1] ?? 1
    return finiteOrNull(Math.min(Math.max(start + within * (end - start), 0), 1))
}

// Where each contents entry starts. Many books (Project Gutenberg's among
// them) put several chapters in one section, which alone would give them all
// the section's start. Entries in the section on screen are placed by its
// layout, so they match the footer; the rest by characters, each section
// read once and counted in one pass (`parse`; without it they're left as
// they are).
const refineContents = async (entries, parse = true) => {
    const v = requireView()
    const bySection = new Map()
    entries.forEach((entry, i) => {
        let resolved = null
        try {
            resolved = entry.href ? v.resolveNavigation(entry.href) : null
        } catch {
            resolved = null
        }
        if (!Number.isInteger(resolved?.index) || typeof resolved.anchor !== 'function') return
        if (!bySection.has(resolved.index)) bySection.set(resolved.index, [])
        bySection.get(resolved.index).push([i, resolved.anchor])
    })
    const refined = entries.map(entry => ({ ...entry }))
    for (const [index, items] of bySection) {
        const loaded = loadedDoc(index)
        if (loaded) {
            for (const [i, anchor] of items) {
                try {
                    const within = layoutFraction(toRange(loaded, anchor(loaded))) ?? characterFraction(loaded, toRange(loaded, anchor(loaded)))
                    refined[i].fraction = bookFraction(index, within)
                } catch {
                    // Left where it was.
                }
            }
            continue
        }
        if (!parse) continue
        let doc
        try {
            doc = await v.book.sections[index].createDocument()
        } catch {
            continue
        }
        const body = doc.body ?? doc.documentElement
        const targets = new Map()
        for (const [i, anchor] of items) {
            let node = null
            try {
                node = anchor(doc)
            } catch {
                node = null
            }
            if (isRange(node)) node = node.startContainer
            if (!node) continue
            if (!targets.has(node)) targets.set(node, [])
            targets.get(node).push(i)
        }
        const offsets = new Map()
        let count = 0
        const walker = doc.createTreeWalker(body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT)
        for (let node = walker.currentNode; node; node = walker.nextNode()) {
            if (targets.has(node)) offsets.set(node, count)
            if (node.nodeType === Node.TEXT_NODE) count += node.length
        }
        if (count === 0) continue
        for (const [node, list] of targets) {
            const offset = offsets.get(node)
            if (offset === undefined) continue
            for (const i of list) refined[i].fraction = bookFraction(index, offset / count)
        }
    }
    return refined
}

// Which of `cfis` fall on the visible page (both pages of a spread), through
// foliate's own CFI ordering: from the page's start up to, not including, the
// point where the next page begins.
const onPage = cfis => {
    const current = requireView().lastLocation?.cfi
    const list = Array.isArray(cfis) ? cfis : []
    if (!current) return list.map(() => false)
    // A fixed-layout page's CFI names only its section, so it has no range to
    // fall in.
    if (view.isFixedLayout) {
        const shown = fixedPagesShown()
        return list.map(cfi => {
            try {
                return shown.includes(view.resolveCFI(String(cfi)).index)
            } catch {
                return false
            }
        })
    }
    const start = CFI.collapse(current)
    const end = CFI.collapse(current, true)
    return list.map(cfi => {
        try {
            const point = CFI.collapse(String(cfi))
            return CFI.compare(start, point) <= 0 && CFI.compare(point, end) < 0
        } catch {
            return false
        }
    })
}

// What a bookmark shows in the Contents panel: where it falls in the book
// (0...1, placed like the contents), its chapter, and the words it starts
// at. A section that isn't on screen is read on its own (scripts never run
// in a parsed document), so this works for any page.
const describePlace = async cfi => {
    const v = requireView()
    const { index, anchor } = v.resolveCFI(String(cfi))
    const loaded = loadedDoc(index)
    const doc = loaded ?? await v.book.sections[index].createDocument()
    // A fixed-layout page's CFI names only its section: the whole page.
    const range = toRange(doc, v.isFixedLayout ? doc.body ?? doc.documentElement : anchor(doc))
    const within = (loaded ? layoutFraction(range) : null) ?? characterFraction(doc, range)
    const body = doc.body ?? doc.documentElement
    const after = doc.createRange()
    after.setStart(range.startContainer, range.startOffset)
    after.setEnd(body, body.childNodes.length)
    const excerpt = after.toString().replace(/\s+/g, ' ').trim().slice(0, 160)
    const tocItem = v.isFixedLayout ? v.getProgressOf(index)?.tocItem : await v.getTOCItemOf(String(cfi))
    return {
        fraction: bookFraction(index, within),
        chapter: plainText(tocItem?.label)?.trim() || null,
        excerpt: excerpt || null,
    }
}

// Bookmarks in the section on screen, placed by its layout like the footer
// (`null` for the rest, which keep their place).
const placeOnScreen = cfis => (Array.isArray(cfis) ? cfis : []).map(cfi => {
    try {
        const { index, anchor } = requireView().resolveCFI(String(cfi))
        const doc = loadedDoc(index)
        if (!doc) return null
        const within = layoutFraction(toRange(doc, anchor(doc)))
        return within === null ? null : bookFraction(index, within)
    } catch {
        return null
    }
})

// KOReader's places (`docs/notes/koreader-sync.md`, "On real KOReader"): an
// xpointer such as `/body/DocFragment[6]/body/div/p[9]/text()[2].212`. The
// fragment is the spine item, from 1; each step counts the element's
// same-named siblings; the offset counts characters as crengine does.
// Measured against KOReader v2026.07.1, which opens a book at page 1 for a
// place it can't read.

// Whether relocations carry KOReader's place (`open`'s `koreaderPlaces`).
let writesXPointers = false

// Where KOReader's DOM may not be the browser's: a place inside one is the
// whole table, picture or formula.
const XPOINTER_STOPS = new Set(['table', 'svg', 'math'])

// The node a range starts at: a text node, or the child an element offset
// points to.
const startNodeOf = range => {
    const node = range?.startContainer
    if (!node) return null
    if (node.nodeType === 3) return node
    return node.childNodes?.[range.startOffset] ?? node
}

// What Octavo sends: the element `node` is in, as `…/p[9].0`. KOReader
// opened all 150 such places on the sample books; word level was 149, and a
// place it can't read is page 1, so this costs at most part of a page.
// `null` outside the section's body.
const xpointerOf = (index, node) => {
    let el = node?.nodeType === 1 ? node : node?.parentElement
    const body = el?.ownerDocument?.body
    if (!Number.isInteger(index) || !el || !body || !(el === body || body.contains(el))) return null
    for (let up = el; up && up !== body; up = up.parentElement) {
        if (XPOINTER_STOPS.has(up.localName.toLowerCase())) el = up
    }
    const steps = []
    for (let step = el; step !== body; step = step.parentElement) {
        const name = step.localName.toLowerCase()
        if (!/^[a-z][\w-]*$/.test(name)) return null
        const same = [...step.parentElement.children].filter(child => child.localName.toLowerCase() === name)
        steps.unshift(same.length > 1 ? `${name}[${same.indexOf(step) + 1}]` : name)
    }
    return `/body/DocFragment[${index + 1}]${steps.length ? `/body/${steps.join('/')}` : ''}.0`
}

// The fragment, the steps from <body>, the text node and the offset. Each
// part is optional after the fragment, as KOReader writes them.
const XPOINTER = /^\/body\/DocFragment\[(\d{1,5})\](?:\/body((?:\/[A-Za-z][\w-]{0,63}(?:\[\d{1,6}\])?){0,64}?)(?:\/text\(\)(?:\[(\d{1,6})\])?)?)?(?:\.(\d{1,9}))?$/
const XPOINTER_STEP = /^([A-Za-z][\w-]*)(?:\[(\d+)\])?$/
const CSS_SPACE = /[ \t\n\r\f]/
// Anything but CSS whitespace: a no-break space is text to KOReader (measured),
// though `\S` would call it blank.
const HAS_TEXT = /[^ \t\n\r\f]/

// Text nodes as `text()[n]` counts them: a blank one only among a
// paragraph's own words, after something in it (not the line break before a
// drop cap, as in Sherlock Holmes), never between blocks.
const creTexts = el => {
    const nodes = [...el.childNodes]
    const keepsBlanks = nodes.some(node => node.nodeType === 3 && HAS_TEXT.test(node.data))
    let started = false
    return nodes.filter(node => {
        const hasText = node.nodeType === 3 && HAS_TEXT.test(node.data)
        const counts = node.nodeType === 3 && (hasText || (keepsBlanks && started))
        if (node.nodeType === 1 || hasText) started = true
        return counts
    })
}

// crengine's offset into `text` as a UTF-16 index: a run of CSS whitespace
// counts as one character (not inside <pre>), and so does a character
// outside the BMP.
const creToDOM = (text, offset, keepsSpaces) => {
    let index = 0
    for (let count = 0; index < text.length && count < offset; count++) {
        if (!keepsSpaces && CSS_SPACE.test(text[index])) {
            while (index < text.length && CSS_SPACE.test(text[index])) index++
        } else {
            index += text.codePointAt(index) > 0xffff ? 2 : 1
        }
    }
    return index
}

// Where KOReader's place falls in the book: its CFI, fraction and chapter.
// Words that don't resolve fall back to their element; an element that
// doesn't exist is `null`, never a guess, and so is one foliate can't place.
// The string is only matched and walked, never evaluated.
const resolveXPointer = async xpointer => {
    try {
        return await findXPointer(xpointer)
    } catch {
        return null
    }
}
const findXPointer = async xpointer => {
    const v = requireView()
    const match = typeof xpointer === 'string' && xpointer.length <= 2048 ? XPOINTER.exec(xpointer) : null
    if (!match || v.isFixedLayout) return null
    const [, fragment, steps = '', textIndex, offset] = match
    const index = Number(fragment) - 1
    const section = v.book.sections[index]
    if (!section) return null
    const loaded = loadedDoc(index)
    const doc = loaded ?? await section.createDocument()
    let el = doc.body
    for (const step of steps.split('/').filter(Boolean)) {
        const [, name, position = '1'] = XPOINTER_STEP.exec(step)
        const same = [...el.children].filter(child => child.localName.toLowerCase() === name.toLowerCase())
        el = same[Number(position) - 1]
        if (!el) return null
    }
    const range = doc.createRange()
    const words = xpointer.includes('/text()') ? creTexts(el)[Number(textIndex ?? 1) - 1] : null
    if (words) {
        const at = creToDOM(words.data, Number(offset ?? 0), Boolean(words.parentElement?.closest('pre')))
        range.setStart(words, at)
        range.setEnd(words, Math.min(at + 1, words.data.length))
    } else {
        range.selectNodeContents(el)
    }
    const within = (loaded ? layoutFraction(range) : null) ?? characterFraction(doc, range)
    range.collapse(true)
    const cfi = v.getCFI(index, range)
    const tocItem = await v.getTOCItemOf(cfi)
    return { cfi, fraction: bookFraction(index, within), chapter: plainText(tocItem?.label)?.trim() || null }
}

// KOReader's place for where `cfi` starts, for a place saved before.
const xpointerAt = async cfi => {
    const v = requireView()
    if (v.isFixedLayout) return null
    const { index, anchor } = v.resolveCFI(String(cfi))
    const doc = loadedDoc(index) ?? await v.book.sections[index].createDocument()
    return xpointerOf(index, startNodeOf(toRange(doc, anchor(doc))))
}

// A second layer against book scripts, for every format (formats check,
// step 15; `docs/notes/formats-check.md`). The reader's CSP is the first: it
// blocks them on its own, and the section documents inherit it. This one
// works on each section before foliate puts it in an iframe, so a lost or
// weakened CSP still runs nothing. EPUB alone also has foliate's `load` hook
// (in `open`); MOBI, KF8 and FB2 don't fire it.
//
// - Sanitize: every <script> (HTML or SVG) gets an inert type and loses its
//   source; on* attributes and javascript:/vbscript: URLs go; frames,
//   objects and embeds lose what they would load; SVG animations can't
//   target a link or a handler; meta refresh, <base href> and XSLT
//   stylesheets are disarmed. No node is added, removed or moved under
//   <html>, so every CFI stays the same.
// - A Content-Security-Policy <meta> first in <head>: no scripts, frames,
//   objects or network at all. Only <head> changes, and CFIs go through
//   <body>. Fonts as in the reader's CSP: the bundled ones (Swift's
//   `ReaderSchemeHandler.fontsURL`) and the book's own.
const SCRIPT_TYPE_BLOCKED = 'application/x-octavo-blocked'
const XLINK = 'http://www.w3.org/1999/xlink'
const XHTML_NS = 'http://www.w3.org/1999/xhtml'
const MATHML_NS = 'http://www.w3.org/1998/Math/MathML'
const SECTION_POLICY = [
    "default-src 'self' blob: data:",
    "script-src 'none'",
    "style-src 'self' 'unsafe-inline' blob: data:",
    "img-src 'self' blob: data:",
    `font-src ${new URL('fonts/', import.meta.url).href} blob: data:`,
    "media-src 'self' blob: data:",
    "connect-src 'none'",
    "object-src 'none'",
    "frame-src 'none'",
    "worker-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
].join('; ')
const FRAMES = new Set(['iframe', 'frame', 'object', 'embed', 'applet', 'portal', 'fencedframe'])
const FRAME_SOURCES = ['src', 'srcdoc', 'data', 'code', 'codebase', 'archive']
const SVG_ANIMATIONS = new Set(['animate', 'set', 'animatemotion', 'animatetransform', 'discard'])
// Control characters and spaces, which URL parsing strips anywhere in a
// scheme (`java\tscript:`).
const isScriptURL = value => /^(javascript|vbscript):/i.test(String(value).replace(/[\u0000- ]/g, ''))

const sanitizeSection = doc => {
    // <?xml-stylesheet?> outside the root: XSLT could build a new document.
    for (const node of [...doc.childNodes])
        if (node.nodeType === Node.PROCESSING_INSTRUCTION_NODE) node.remove()
    sanitizeTree(doc, doc.contentType === 'text/html')
}

// A <template>'s content is a fragment of its own, which neither
// getElementsByTagName nor querySelectorAll reaches, so it's walked too.
// Its shadowroot attributes go: the iframe's parser would turn a
// `<template shadowrootmode>` into a live shadow root (declarative shadow
// DOM) that DOMParser here never made, so its markup would arrive unchecked.
const TEMPLATE_SHADOW = ['shadowrootmode', 'shadowroot', 'shadowrootdelegatesfocus', 'shadowrootclonable', 'shadowrootserializable']
const sanitizeTree = (root, isHTML) => {
    // HTML only: DOMParser reads a <noscript>'s content with scripting off,
    // as markup, but the iframe reads it with scripting on, as text up to
    // the first `</noscript>`, which an attribute or a comment inside can
    // carry (mutation XSS: what's checked here isn't what the iframe gets).
    // With scripting on it shows nothing, so no position is ever inside it,
    // and emptying it moves no CFI.
    if (isHTML)
        for (const el of root.querySelectorAll('noscript')) el.replaceChildren()
    for (const el of root.querySelectorAll('*')) {
        const name = el.localName.toLowerCase()
        if (name === 'template') {
            for (const attr of TEMPLATE_SHADOW) el.removeAttribute(attr)
            if (el.content) sanitizeTree(el.content, isHTML)
        }
        // Links foliate doesn't catch (it handles clicks on HTML a[href]
        // only): an image map's area, an SVG link, MathML's href. A target
        // inside the page (a fragment) stays; any other goes, so the frame
        // can't navigate itself to a document this layer never saw (a data:
        // page, or another section as foliate built it). Forms can't
        // submit anywhere either. Attributes move no CFI.
        if (isNavigating(el, name)) {
            for (const attr of ['href', 'action', 'formaction']) {
                if (el.hasAttribute(attr) && !el.getAttribute(attr).trim().startsWith('#')) el.removeAttribute(attr)
            }
            const xlink = el.getAttributeNS(XLINK, 'href')
            if (xlink !== null && !xlink.trim().startsWith('#')) el.removeAttributeNS(XLINK, 'href')
        }
        if (el.hasAttribute('formaction')) el.removeAttribute('formaction')
        if (name === 'param') el.removeAttribute('value')
        for (const attr of [...el.attributes]) {
            if (/^on/i.test(attr.localName) || isScriptURL(attr.value)) el.removeAttributeNode(attr)
        }
        if (name === 'script') {
            el.setAttribute('type', SCRIPT_TYPE_BLOCKED)
            el.removeAttribute('src')
            el.removeAttribute('href')
            el.removeAttributeNS(XLINK, 'href')
        } else if (FRAMES.has(name)) {
            for (const attr of FRAME_SOURCES) el.removeAttribute(attr)
        } else if (SVG_ANIMATIONS.has(name)) {
            // `<animate attributeName="href" values="…;javascript:…">`.
            const target = el.getAttribute('attributeName') ?? ''
            if (/(^|:)href$|^on/i.test(target)) el.removeAttribute('attributeName')
        } else if (name === 'meta' && /refresh/i.test(el.getAttribute('http-equiv') ?? '')) {
            el.removeAttribute('http-equiv')
        } else if (name === 'base') {
            el.removeAttribute('href')
        }
    }
}

// Elements whose href (or action) would navigate the frame when clicked or
// submitted, other than the HTML links foliate intercepts.
const isNavigating = (el, name) => {
    if (el.namespaceURI === XHTML_NS) return name === 'area' || name === 'form'
    if (el.namespaceURI === MATHML_NS) return el.hasAttribute('href')
    return name === 'a'
}

// Only a real <head>, first in <html>: a `head` elsewhere (another
// namespace, the body) would hold a policy WebKit ignores, and inserting
// there would move CFIs. Markup before it would load before the policy.
// Without one the section keeps the sanitizer and the reader's CSP.
const addSectionPolicy = doc => {
    const head = doc.documentElement?.firstElementChild
    if (!head || head.localName !== 'head' || head.namespaceURI !== XHTML_NS) return false
    const meta = doc.createElementNS(head.namespaceURI, 'meta')
    meta.setAttribute('http-equiv', 'Content-Security-Policy')
    meta.setAttribute('content', SECTION_POLICY)
    head.prepend(meta)
    return true
}

// HTML is written back as HTML: an XML serialization escapes `>` in
// <style>, which an HTML parser then reads as text.
const serializeSection = (doc, type) => {
    if (type !== 'text/html') return new XMLSerializer().serializeToString(doc)
    const doctype = doc.doctype ? new XMLSerializer().serializeToString(doc.doctype) : ''
    return doctype + doc.documentElement.outerHTML
}

const hardenSection = async (url, sectionIndex) => {
    const blob = await (await fetch(url)).blob()
    let type = blob.type || 'application/xhtml+xml'
    const text = await blob.text()
    let doc
    try {
        doc = new DOMParser().parseFromString(text, type)
    } catch (e) {
        // A type DOMParser can't read is no document foliate would render.
        post('log', { level: 'warn', message: `Section ${sectionIndex}: not a document (${type})` })
        return null
    }
    // Not well-formed XML. foliate's EPUB and KF8 loaders already switch such
    // a section to HTML before it gets here, so this is a section they
    // didn't. It's read as HTML too, the way foliate would, rather than
    // left unsanitized: no section reaches an iframe without both layers.
    if (doc.querySelector('parsererror') || !doc.documentElement) {
        post('log', { level: 'warn', message: `Section ${sectionIndex}: not well-formed ${type}, read as HTML` })
        type = 'text/html'
        doc = new DOMParser().parseFromString(text, type)
    }
    sanitizeSection(doc)
    addSectionPolicy(doc)
    const hardened = serializeSection(doc, type)
    // Written out and read back, the section must still hold nothing live:
    // a serializer/parser disagreement (mutation XSS) is refused, not shown.
    if (hasLiveContent(new DOMParser().parseFromString(hardened, type))) {
        post('log', { level: 'warn', message: `Section ${sectionIndex}: live content after hardening, refused` })
        return null
    }
    return URL.createObjectURL(new Blob([hardened], { type }))
}

const hasLiveContent = root => {
    for (const el of root.querySelectorAll('*')) {
        const name = el.localName.toLowerCase()
        if (name === 'template') {
            if (TEMPLATE_SHADOW.some(attr => el.hasAttribute(attr))) return true
            if (el.content && hasLiveContent(el.content)) return true
        }
        if (name === 'script' && (el.getAttribute('type') !== SCRIPT_TYPE_BLOCKED || el.hasAttribute('src'))) return true
        for (const attr of el.attributes) {
            if (/^on/i.test(attr.localName) || isScriptURL(attr.value)) return true
        }
    }
    return false
}

// Wraps each section's `load` and `unload`. foliate's paginator loads a
// section once on the way in and unloads it on the way out; EPUB's loader
// revokes the section's resources then, so the hardened copy goes with it
// and is made again from foliate's new one next time.
const hardenBook = book => {
    const release = ({ from, url }) => url.then(made => {
        if (made && made !== from) URL.revokeObjectURL(made)
    })
    for (const [index, section] of (book.sections ?? []).entries()) {
        if (typeof section.load !== 'function') continue
        const load = section.load.bind(section)
        const unload = section.unload?.bind(section)
        // foliate's URL, the hardened one (a promise, so two loads at once
        // share it) and how many loads it has had.
        let made = null
        section.load = async () => {
            const from = await load()
            if (typeof from !== 'string') return from
            if (made?.from !== from) {
                if (made) release(made)
                made = { from, url: hardenSection(from, index).catch(() => null), refs: 0 }
            }
            made.refs++
            const url = await made.url
            if (url === null) throw new Error(`Section ${index} isn't a document`)
            return url
        }
        section.unload = () => {
            if (made && --made.refs <= 0) {
                release(made)
                made = null
            }
            unload?.()
        }
    }
}

// After going to a saved point, the page that comes back can end just
// before it (KF8, formats spike: the point was the page's first line, and
// page breaks moved by a line between saving and going back). The point is
// then on the next page.
const isCFI = target => typeof target === 'string' && target.startsWith('epubcfi(')
const showPoint = async cfi => {
    await settle()
    const page = view.lastLocation?.cfi
    if (!page) return
    try {
        if (CFI.compare(CFI.collapse(page, true), CFI.collapse(cfi)) < 0) {
            await view.next()
            await settle()
        }
    } catch {
        // A CFI foliate can't compare: leave the page foliate chose.
    }
}
const goToPoint = async target => {
    const done = await view.goTo(target)
    // Fixed layout says nothing when the book has no such section.
    if (view.isFixedLayout) return view.book.sections[done?.index] ? done : undefined
    if (done && isCFI(target)) await showPoint(target)
    return done
}

// FB2 has no `isExternal`, so foliate hands every link to `link`, and a web
// address becomes an internal jump that goes nowhere. Anything with a scheme
// (not one of foliate's own blob: URLs) is reported like the other formats'
// external links instead. A link inside the book is a jump, which Swift makes,
// as your place has to hold before the page moves (decision 33).
const hasScheme = href => /^[a-z][a-z0-9+.-]*:/i.test(String(href).trim()) && !/^blob:/i.test(String(href).trim())
const onLink = e => {
    e.preventDefault()
    const { a, href } = e.detail
    if (!view?.book?.isExternal && hasScheme(href)) return post('externalLink', { href })
    openNote(a, href).then(opened => {
        if (!opened) post('link', { href })
    })
}

// Footnotes (decision 34, `docs/notes/footnotes.md`). A note's mark opens the
// note in Swift's card, and the page doesn't move. Any other link is a jump,
// and so is a note with something only the page can draw (a picture, a table).
//
// Which links: the ones a book marks as notes, and ones that look like a note's
// mark in running text and point at the start of a block that isn't a heading.
// A wrong guess costs one more tap, as the card has Go to Note.
//
// Only the note's words and which are italic and such go to Swift, so nothing
// of the book's runs there. A section read for its note is only parsed, like
// `describePlace`'s, and never put in a frame.
const EPUB_NS = 'http://www.idpf.org/2007/ops'
const wordsIn = value => (value ?? '').split(/\s+/).filter(Boolean)
const hasType = (el, types, roles) =>
    wordsIn(el.getAttributeNS(EPUB_NS, 'type') ?? el.getAttribute('epub:type')).some(word => types.includes(word))
    || wordsIn(el.getAttribute('role')).some(word => roles.includes(word))

const BLOCK_NAMES = new Set(['address', 'article', 'aside', 'blockquote', 'body', 'center', 'dd', 'details', 'div', 'dl', 'dt',
    'figcaption', 'figure', 'footer', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'li', 'main', 'nav', 'ol', 'p', 'pre',
    'section', 'td', 'th', 'tr', 'ul'])
const HEADING_SELECTOR = 'h1, h2, h3, h4, h5, h6'
const isBlock = el => BLOCK_NAMES.has(el.localName)
const blockOf = el => {
    while (el && !isBlock(el)) el = el.parentElement
    return el
}
const textBefore = (el, block) => {
    const range = el.ownerDocument.createRange()
    range.setStart(block, 0)
    range.setEndBefore(el)
    return range.toString().trim()
}

// `12`, `12.`, `*`, `†`, `²`, `[A]`, `(iv)`, or any short text that's raised.
const BARE_MARK = /^(\d{1,4}\.?|[*†‡§¶#]{1,3}|[⁰¹²³⁴-⁹]{1,4})$/u
const BRACKETED_MARK = /^[\[({<][^\s\])}>]{1,5}[\])}>]\.?$/
const MARK_MAX_LENGTH = 8
const isRaised = a => {
    if (a.closest('sup') || a.querySelector('sup')) return true
    return a.ownerDocument.defaultView?.getComputedStyle(a).verticalAlign === 'super'
}
const looksLikeMark = a => {
    const text = a.textContent.trim()
    if (!text || text.length > MARK_MAX_LENGTH) return false
    return BARE_MARK.test(text) || BRACKETED_MARK.test(text) || isRaised(a)
}

const isExternalHref = href => view?.book?.isExternal ? view.book.isExternal(href) : hasScheme(href)
const isInContents = a => {
    for (let el = a.parentElement; el; el = el.parentElement) {
        if (el.localName === 'nav' || hasType(el, ['toc', 'index', 'landmarks'], ['doc-toc', 'doc-index'])) return true
    }
    return false
}
const BACKLINK = [['backlink'], ['doc-backlink']]
// `marked`, `looks`, or `null` for a link that's no note's mark. The note's own
// way back starts its block, with nothing before it, so it isn't one.
const markKind = a => {
    const href = a.getAttribute('href')
    if (!href || isExternalHref(href) || hasType(a, ...BACKLINK) || isInContents(a)) return null
    if (hasType(a, ['noteref'], ['doc-noteref'])) return 'marked'
    const block = blockOf(a)
    return block && looksLikeMark(a) && textBefore(a, block) ? 'looks' : null
}

const isNoteItem = el => hasType(el, ['footnote', 'endnote', 'rearnote', 'note'], ['doc-footnote', 'doc-endnote'])
// A box that holds one note of several paragraphs.
const isNoteBox = el => {
    if (['li', 'aside', 'dd'].includes(el.localName)) return true
    return ['div', 'section'].includes(el.localName) && /note|foot|^fn/i.test(`${el.getAttribute('class') ?? ''} ${el.id}`)
}
const holdsOnlyNote = (box, note) => [...box.children].every(child =>
    child === note || !(child.id || child.querySelector('[id]') || child.matches(HEADING_SELECTOR)))

// The note at a link's target, or `null` if what's there isn't one.
const noteElement = (target, marked) => {
    const body = target.ownerDocument.body
    if (target === body || target === target.ownerDocument.documentElement) return null
    for (let el = target; el && el !== body; el = el.parentElement) {
        if (isNoteItem(el)) return el
    }
    if (target.matches(HEADING_SELECTOR) || hasType(target, ['pagebreak'], ['doc-pagebreak'])) return null
    // An empty anchor just before the note.
    const next = target.nextElementSibling
    if (!target.textContent.trim() && next && isBlock(next)) target = next
    let note = blockOf(target)
    if (!note || note === body) return null
    if (note !== target && !marked && textBefore(target, note)) return null
    while (note.parentElement !== body && isNoteBox(note.parentElement)
        && !textBefore(note, note.parentElement) && holdsOnlyNote(note.parentElement, note)) note = note.parentElement
    return !marked && note.querySelector(HEADING_SELECTOR) ? null : note
}

const ONLY_THE_PAGE_DRAWS = new Set(['img', 'image', 'svg', 'math', 'table', 'video', 'audio', 'canvas', 'object', 'embed', 'iframe'])
const DRAWN_SELECTOR = [...ONLY_THE_PAGE_DRAWS].join(', ')

// A link in the note that only leads back: left out of the card, whatever it
// holds if it's plainly the way back. Otherwise its words are the note's, and
// a picture in it means the card can't draw the note.
const leadsBack = (a, mark, note) => {
    if (hasType(a, ...BACKLINK)) return true
    const fragment = (a.getAttribute('href') ?? '').split('#')[1]
    if (fragment && mark.id === fragment) return true
    if (a.querySelector(DRAWN_SELECTOR)) return false
    if (/^[\s↩↑⤴⏎⬆\uFE0E\uFE0F]*$/u.test(a.textContent)) return true
    if (a.textContent.trim().length > MARK_MAX_LENGTH) return false
    // To a box around the mark.
    if (fragment) {
        for (let el = mark.parentElement; el; el = el.parentElement) {
            if (el.id === fragment) return true
        }
    }
    // The note's own number, where it links to.
    return looksLikeMark(a) && !textBefore(a, note)
}

// More than a note could be: a wrong guess, or a book trying to make the card
// do too much.
const NOTE_MAX_LENGTH = 20000
const NOTE_MAX_BLOCKS = 200
const NOTE_MAX_INDENT = 4
const NOT_SHOWN = new Set(['script', 'style', 'template', 'noscript', 'head', 'title'])
const RUN_STYLES = {
    i: 'italic', em: 'italic', cite: 'italic', dfn: 'italic', var: 'italic',
    b: 'bold', strong: 'bold', sup: 'sup', sub: 'sub',
    code: 'code', tt: 'code', kbd: 'code', samp: 'code',
}
const STYLE_NAMES = ['italic', 'bold', 'sup', 'sub', 'code']
const isHidden = el => el.hasAttribute('hidden') || /display\s*:\s*none/i.test(el.getAttribute('style') ?? '')
    || hasType(el, ['pagebreak'], ['doc-pagebreak'])

// The note's words as blocks of styled runs. `null` if it has anything the card
// can't draw, or is more than a note could be.
const noteBlocks = (note, mark) => {
    const blocks = []
    let block = null
    let length = 0
    const endBlock = () => {
        if (!block) return
        const { runs } = block
        while (runs.length) {
            const last = runs[runs.length - 1]
            last.text = last.text.trimEnd()
            if (last.text) break
            runs.pop()
        }
        if (runs.length) blocks.push(block)
        block = null
    }
    const add = (text, style, indent, preformatted) => {
        block ??= { runs: [], indent }
        const last = block.runs[block.runs.length - 1]
        if (!preformatted && (!last || /\s$/.test(last.text))) text = text.replace(/^[ \t\r\n\f]+/, '')
        if (!text) return
        length += text.length
        if (last && STYLE_NAMES.every(name => last[name] === style[name])) last.text += text
        else block.runs.push({ text, ...style })
    }
    // Whether all of it can be drawn. It stops as soon as there's too much.
    const walk = (parent, style, indent, preformatted) => {
        for (const node of parent.childNodes) {
            if (length > NOTE_MAX_LENGTH || blocks.length > NOTE_MAX_BLOCKS) return false
            if (node.nodeType === Node.TEXT_NODE || node.nodeType === Node.CDATA_SECTION_NODE) {
                add(preformatted ? node.data : node.data.replace(/[ \t\r\n\f]+/g, ' '), style, indent, preformatted)
                continue
            }
            if (node.nodeType !== Node.ELEMENT_NODE) continue
            const name = node.localName.toLowerCase()
            if (ONLY_THE_PAGE_DRAWS.has(name)) return false
            if (NOT_SHOWN.has(name) || isHidden(node)) continue
            if (name === 'a' && node.hasAttribute('href') && leadsBack(node, mark, note)) continue
            if (name === 'br') {
                const last = block?.runs[block.runs.length - 1]
                if (last) last.text = `${last.text.replace(/[ \t]+$/, '')}\n`
                continue
            }
            const isOwnBlock = isBlock(node)
            if (isOwnBlock) endBlock()
            const inner = RUN_STYLES[name] ? { ...style, [RUN_STYLES[name]]: true } : style
            const innerIndent = Math.min(indent + (name === 'blockquote' ? 1 : 0), NOTE_MAX_INDENT)
            if (!walk(node, inner, innerIndent, preformatted || name === 'pre')) return false
            if (isOwnBlock) endBlock()
        }
        return true
    }
    if (!walk(note, {}, 0, false)) return null
    endBlock()
    return blocks.length && blocks.length <= NOTE_MAX_BLOCKS && length <= NOTE_MAX_LENGTH ? blocks : null
}

// What a tap on `a` would show, if it's a note.
const noteAt = async (a, href) => {
    const kind = markKind(a)
    if (!kind) return null
    const resolved = await view.book.resolveHref(href)
    const section = view.book.sections[resolved?.index]
    const doc = section && (loadedDoc(resolved.index) ?? await section.createDocument?.())
    const target = doc && resolved.anchor(doc)
    if (target?.nodeType !== Node.ELEMENT_NODE) return null
    const note = noteElement(target, kind === 'marked')
    return note && noteBlocks(note, a)
}

// Whether the note opened.
const openNote = async (a, href) => {
    try {
        const blocks = await noteAt(a, href)
        const mark = blocks && markBox(a)
        if (!mark) return false
        post('note', { href, mark, font: noteFont(a), blocks })
        return true
    } catch (e) {
        post('log', { level: 'warn', message: `Couldn't read a note: ${e}` })
        return false
    }
}

const frameScale = frame => view.isFixedLayout && frame.offsetWidth ? frame.getBoundingClientRect().width / frame.offsetWidth : 1

// Where the mark is in the top window's coordinates, which are the screen's.
const markBox = a => {
    const frame = a.ownerDocument.defaultView?.frameElement
    if (!frame) return null
    const box = frame.getBoundingClientRect()
    const scale = frameScale(frame)
    const rects = [...a.getClientRects()].map(rect => ({
        x: box.left + rect.left * scale,
        y: box.top + rect.top * scale,
        width: rect.width * scale,
        height: rect.height * scale,
    }))
    return rects.find(rect => rect.x + rect.width > 0 && rect.x < innerWidth) ?? null
}

// How far apart the lines of `block` are drawn: `line-height: normal` doesn't
// say. The closest two lines, leaving out a raised mark's smaller box, which
// has a top of its own. Shorter than the block's own text's box, that is: in a
// font with tall lines (OpenDyslexic's) a mark's box is taller than the font
// size.
const linePitch = (block, size) => {
    const range = block.ownerDocument.createRange()
    const own = [...block.childNodes].find(node => node.nodeType === Node.TEXT_NODE && node.textContent.trim())
    if (own) range.selectNodeContents(own)
    const text = Math.max(size, ((own && range.getClientRects()[0]?.height) || 0) - 0.5)
    range.selectNodeContents(block)
    const tops = [...range.getClientRects()].filter(rect => rect.height >= text).map(rect => rect.top).sort((a, b) => a - b)
    const gaps = tops.slice(1).map((top, index) => top - tops[index]).filter(gap => gap >= size * 0.9)
    return gaps.length ? Math.min(...gaps) : null
}

// The text around the mark, whatever set it (the book, or Text and Theme).
const noteFont = a => {
    const { defaultView, documentElement } = a.ownerDocument
    const block = blockOf(a) ?? documentElement
    const style = defaultView.getComputedStyle(block)
    const scale = frameScale(defaultView.frameElement)
    const size = parseFloat(style.fontSize)
    const lineHeight = parseFloat(style.lineHeight) || linePitch(block, size)
    return { family: style.fontFamily, size: size * scale, lineHeight: lineHeight ? lineHeight * scale : null }
}

// How far a tap can miss a mark and still count, in points around its box.
const NEAR_MARK_X = 16
const NEAR_MARK_Y = 12
const nearNoteMark = (doc, x, y) => {
    let nearest = null
    let distance = Infinity
    for (const a of doc.querySelectorAll('a[href]')) {
        for (const rect of a.getClientRects()) {
            const dx = Math.max(rect.left - x, 0, x - rect.right)
            const dy = Math.max(rect.top - y, 0, y - rect.bottom)
            if (dx > NEAR_MARK_X || dy > NEAR_MARK_Y) continue
            const d = Math.hypot(dx, dy)
            if (d < distance && markKind(a)) {
                nearest = a
                distance = d
            }
        }
    }
    return nearest
}

// A link's address as foliate resolves it for its `link` event.
const resolvedHref = (a, doc) => {
    const index = view.renderer.getContents().find(content => content.doc === doc)?.index
    const raw = a.getAttribute('href')
    return view.book.sections[index]?.resolveHref?.(raw) ?? raw
}

// Try the CFI first, then the fraction, then the start of the book. A
// fixed-layout page's CFI names its section, so it's exact there too, whatever
// BookOrbit's web reader makes of it (`docs/notes/fixed-layout.md`). A fraction
// on a section's end, within a server's rounding, is that section's page.
const SECTION_END_ROUNDING = 1e-6
const restore = async (cfi, fraction) => {
    const byFraction = async () => {
        if (fraction === null || fraction <= 0) return false
        const target = Math.min(fraction, 1)
        await view.goToFraction(view.isFixedLayout ? Math.max(target - SECTION_END_ROUNDING, 0) : target)
        await anchorToPage()
        return true
    }
    if (cfi && await goToPoint(cfi)) return 'cfi'
    if (await byFraction()) return 'fraction'
    await view.init({ showTextStart: false })
    return 'start'
}

// `xpointer`: a KOReader place to open at when there's no `cfi`, else the
// fraction. `koreaderPlaces`: relocations carry KOReader's place (an EPUB
// that syncs with KOReader).
const open = async ({ url, name, cfi = null, fraction = null, xpointer = null, koreaderPlaces = false, layout: initialLayout = undefined, appearance: initialAppearance = undefined, harden = true }) => {
    if (view) {
        view.close()
        view.remove()
    }
    view = document.createElement('foliate-view')
    view.addEventListener('relocate', onRelocate)
    view.addEventListener('load', onSectionLoad)
    view.addEventListener('draw-annotation', onDrawAnnotation)
    view.addEventListener('create-overlay', onCreateOverlay)
    search = null
    shownMatch = null
    selecting = false
    turnHeld = null
    // foliate would `window.open` external links; hand them to Swift instead.
    view.addEventListener('external-link', e => {
        e.preventDefault()
        post('externalLink', { href: e.detail.href })
    })
    view.addEventListener('link', onLink)
    document.body.append(view)

    const response = await fetch(url)
    if (!response.ok) throw new Error(`Couldn't load the book (${response.status})`)
    const type = response.headers.get('Content-Type') ?? ''
    await view.open(new File([await response.blob()], name, { type }))
    // Never load a book's own scripts. The CSP blocks them too; see
    // ReaderSchemeHandler.contentSecurityPolicy and foliate-js's README.
    view.book.transformTarget?.addEventListener('load', ({ detail }) => {
        if (detail.isScript) detail.allow = false
    })
    // Before the first section loads. `harden: false` comes only from a
    // DEBUG build's `-readerWithoutHarden` (the formats check's controls).
    guardsLinks = harden !== false
    if (guardsLinks) hardenBook(view.book)
    view.renderer.setAttribute('flow', 'paginated')
    view.renderer.addEventListener('relocate', e => { lastRelocateReason = e.detail?.reason ?? null }, { capture: true })
    if (initialAppearance) appearance = { css: String(initialAppearance.css ?? ''), background: String(initialAppearance.background ?? '') }
    applyAppearance()
    if (initialLayout !== undefined) layout = initialLayout
    held = null
    writesXPointers = Boolean(koreaderPlaces)
    // Nothing is rendered yet, so the attributes are all it takes.
    applyAttributes()

    const opening = cfi ?? (xpointer ? (await resolveXPointer(xpointer))?.cfi ?? null : null)
    const restoredFrom = await restore(opening, finiteOrNull(fraction))
    const result = {
        restoredFrom,
        title: plainText(view.book.metadata?.title),
        sectionCount: view.book.sections?.length ?? 0,
        isFixedLayout: view.isFixedLayout,
        toc: tocFractions(),
    }
    post('opened', result)
    refineContents(result.toc)
        .then(toc => post('contents', { toc }))
        .catch(e => post('error', { phase: 'contents', ...describe(e) }))
    return result
}

const requireView = () => {
    if (!view) throw new Error('No book is open')
    return view
}

// Search in book (decision 19). foliate's own `search` groups matches by
// section, and Project Gutenberg books keep every chapter in one or two, so
// the bridge walks the book itself with foliate's matcher: each section read
// once (the one on screen as it's laid out), each match named after the
// contents entry it falls under and placed in the book like the contents.
// Matches go to Swift a section at a time, tagged with the search's token; a
// newer search, or `cancelSearch`, stops the walk at the next section.
const SEARCH_LIMIT = 1000
let search = null
// A match can run over a line break in the source.
const words = text => String(text ?? '').replace(/\s+/g, ' ')
const runSearch = async (query, token) => {
    const v = requireView()
    search = { token }
    const current = () => search?.token === token
    const matcher = searchMatcher(textWalker, { defaultLocale: v.language?.canonical })
    // The contents' targets by section, in reading order, for naming matches.
    const entries = tocFractions()
    const marks = new Map()
    for (const entry of entries) {
        let resolved = null
        try {
            resolved = entry.href ? v.resolveNavigation(entry.href) : null
        } catch {
            resolved = null
        }
        if (!Number.isInteger(resolved?.index)) continue
        if (!marks.has(resolved.index)) marks.set(resolved.index, [])
        marks.get(resolved.index).push({ label: entry.label, anchor: resolved.anchor })
    }
    let chapter = null
    let count = 0
    let truncated = false
    const sections = v.book.sections ?? []
    for (let index = 0; index < sections.length && !truncated; index++) {
        const section = sections[index]
        if (!section?.createDocument || section.linear === 'no') continue
        const loaded = loadedDoc(index)
        let doc
        try {
            doc = loaded ?? await section.createDocument()
        } catch {
            continue
        }
        if (!current()) return
        // Where each text node starts, counted in one pass, for placing
        // matches in a section that isn't laid out (the one on screen is
        // placed by its layout).
        const offsets = new Map()
        let length = 0
        if (!loaded) {
            const walker = doc.createTreeWalker(doc.body ?? doc.documentElement, NodeFilter.SHOW_TEXT)
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                offsets.set(node, length)
                length += node.length
            }
        }
        // The section's contents entries where they start, in order.
        const starts = []
        for (const mark of marks.get(index) ?? []) {
            let at = null
            try {
                at = typeof mark.anchor === 'function' ? mark.anchor(doc) : null
            } catch {
                at = null
            }
            starts.push({ label: mark.label, range: at ? toRange(doc, at) : null })
        }
        let next = 0
        const matches = []
        for (const { range, excerpt } of matcher(doc, query)) {
            // A section's entry with no target in it starts it.
            while (next < starts.length && (!starts[next].range
                || range.compareBoundaryPoints(Range.START_TO_START, starts[next].range) >= 0)) {
                chapter = starts[next].label
                next++
            }
            const within = (loaded ? layoutFraction(range) : null)
                ?? (loaded ? characterFraction(doc, range)
                    : length > 0 ? ((offsets.get(range.startContainer) ?? 0) + range.startOffset) / length : 0)
            matches.push({
                cfi: v.getCFI(index, range),
                pre: words(excerpt?.pre),
                match: words(excerpt?.match),
                post: words(excerpt?.post),
                chapter,
                fraction: bookFraction(index, Math.min(within, 1)),
            })
            if (++count >= SEARCH_LIMIT) {
                truncated = true
                break
            }
        }
        // Entries after the last match still name what comes next.
        if (starts.length) chapter = starts[starts.length - 1].label
        if (!current()) return
        if (matches.length) post('searchResults', { token, matches, done: false, truncated: false })
    }
    if (current()) post('searchResults', { token, matches: [], done: true, truncated })
}

// The match being shown, highlighted until the next one or the search's end.
// foliate draws an annotation only in a section that's laid out, so it's
// drawn again whenever its section is.
let shownMatch = null
const HIGHLIGHT = 'rgb(255, 204, 0)'
const onDrawAnnotation = ({ detail: { draw, annotation } }) => {
    if (annotation?.value === shownMatch) draw(Overlayer.highlight, { color: HIGHLIGHT })
}
const onCreateOverlay = ({ detail: { index } }) => {
    if (!shownMatch) return
    try {
        if (view.resolveCFI(shownMatch).index === index) view.addAnnotation({ value: shownMatch })
    } catch {
        // Not a CFI this book has.
    }
}
const showMatch = async cfi => {
    const v = requireView()
    if (shownMatch) {
        await v.deleteAnnotation({ value: shownMatch }).catch(() => {})
        shownMatch = null
    }
    if (!cfi) return true
    shownMatch = String(cfi)
    await v.goTo(shownMatch)
    await v.addAnnotation({ value: shownMatch })
    return true
}

// An imported file's details (Swift's `BookInspector`): what foliate reads
// from it, in the same page and under the same CSP as the reader, without
// laying anything out, so no section is ever rendered. foliate's shapes
// differ by format (`docs/notes/formats-spike.md`, Metadata and covers):
// strings, `{ lang: string }` maps, `{ name, sortAs }` people, arrays of
// any of them.
const COVER_LIMIT = 16 << 20
const names = value => (Array.isArray(value) ? value : value ? [value] : [])
    .map(person => typeof person === 'object' && person && 'name' in person ? plainText(person.name) : plainText(person))
    .map(name => name?.trim())
    .filter(Boolean)
const firstText = value => Array.isArray(value) ? names(value)[0] ?? null : names([value])[0] ?? null
const base64 = bytes => {
    let text = ''
    for (let i = 0; i < bytes.length; i += 0x2000) text += String.fromCharCode(...bytes.subarray(i, i + 0x2000))
    return btoa(text)
}
const coverOf = async book => {
    try {
        const blob = await book.getCover?.()
        if (!blob || !blob.size || blob.size > COVER_LIMIT) return null
        return { data: base64(new Uint8Array(await blob.arrayBuffer())), type: blob.type || null }
    } catch {
        // FB2's cover is a data: URL foliate fetches, which the reader's CSP
        // blocks; Swift reads that one from the file itself.
        return null
    }
}
// An EPUB whose encryption.xml lists anything but font obfuscation (which
// foliate undoes) is locked by a store: Kobo's DRM, say, which leaves no
// file of its own beside the book for `BookFileCheck` to see. foliate would
// open it as scrambled text without an error.
const FONT_OBFUSCATION = new Set(['http://www.idpf.org/2008/embedding', 'http://ns.adobe.com/pdf/enc#RC'])
const XMLENC = 'http://www.w3.org/2001/04/xmlenc#'
const isLocked = async book => {
    if (!book.resources?.opf || typeof book.loadText !== 'function') return false
    const text = await Promise.resolve(book.loadText('META-INF/encryption.xml')).catch(() => null)
    if (!text) return false
    const doc = new DOMParser().parseFromString(text, 'application/xml')
    return Array.from(doc.getElementsByTagNameNS(XMLENC, 'EncryptionMethod'), el => el.getAttribute('Algorithm'))
        .some(algorithm => !FONT_OBFUSCATION.has(algorithm))
}

// What a book file says about itself is the book's: capped before it's sent,
// so a crafted title or description can't stall the app's parse.
const short = (value, limit) => typeof value === 'string' ? value.slice(0, limit) : value
const shortNames = value => names(Array.isArray(value) ? value.slice(0, 50) : value)
    .map(name => name.slice(0, 500))

const inspect = async ({ url, name }) => {
    const response = await fetch(url)
    if (!response.ok) throw new Error(`Couldn't load the book (${response.status})`)
    const type = response.headers.get('Content-Type') ?? ''
    const book = await makeBook(new File([await response.blob()], name, { type }))
    try {
        if (await isLocked(book)) return { drm: true }
        const metadata = book.metadata ?? {}
        const description = metadata.description
        return {
            title: short(plainText(short(metadata.title, 4000))?.trim(), 1000) || null,
            subtitle: short(plainText(short(metadata.subtitle, 4000))?.trim(), 1000) || null,
            authors: shortNames(metadata.author),
            publisher: short(firstText(metadata.publisher), 500),
            language: short(firstText(metadata.language), 64),
            published: typeof metadata.published === 'string' ? metadata.published.trim().slice(0, 64) || null : null,
            description: short(typeof description === 'string' ? description : plainText(description), 100_000),
            sectionCount: book.sections?.length ?? 0,
            cover: await coverOf(book),
        }
    } finally {
        book.destroy?.()
    }
}

// Swift awaits these; a rejection surfaces there as a thrown error, and is
// also posted so it reaches the same error path as everything else.
const reported = f => async (...args) => {
    try {
        return await f(...args)
    } catch (e) {
        post('error', { phase: f.name || 'call', ...describe(e) })
        throw e
    }
}

window.octavo = Object.freeze({
    open: reported(open),
    inspect: reported(inspect),
    goTo: reported(async function goTo(cfi) {
        requireView()
        return Boolean(await goToPoint(cfi))
    }),
    goToFraction: reported(async function goToFraction(fraction) {
        const target = Math.max(0, Math.min(1, fraction))
        const v = requireView()
        // From the bar and the contents, which count a fixed-layout book's
        // pages (`fixedPlace`), not from a saved position, which counts bytes
        // (`restore`).
        if (v.isFixedLayout) {
            const total = v.book.sections.length
            await v.goTo(Math.min(Math.floor(target * total), total - 1))
            return true
        }
        await v.goToFraction(target)
        await anchorToPage()
        return true
    }),
    next: reported(async function next() {
        await requireView().next()
        return true
    }),
    prev: reported(async function prev() {
        await requireView().prev()
        return true
    }),
    // Resolves to whether the page was re-rendered.
    setLayout: reported(async function setLayout_(newLayout) {
        return setLayout(newLayout)
    }),
    hold: reported(async function hold_() {
        return hold()
    }),
    setAppearance: reported(async function setAppearance(next) {
        appearance = { css: String(next?.css ?? ''), background: String(next?.background ?? '') }
        applyAppearance()
        return true
    }),
    setTapMode: reported(async function setTapMode(mode) {
        tapMode = { dismisses: Boolean(mode?.dismisses) }
        return true
    }),
    // Whether Swift draws page turns (any Page Turn but None).
    setTurnMode: reported(async function setTurnMode(mode) {
        turnsAnimated = Boolean(mode?.animated)
        return true
    }),
    // Resolves to `{ moved, relocation }` once the new page is drawn.
    turn: reported(async function turn_(side, hold) {
        return turn(side === 'left' ? 'left' : 'right', Boolean(hold))
    }),
    endTurn: reported(async function endTurn_(keep) {
        return endTurn(Boolean(keep))
    }),
    layoutReport: reported(async function layoutReport_() {
        return layoutReport()
    }),
    locate: reported(async function locate_(cfi) {
        return locate(cfi)
    }),
    // Runs in the background; matches arrive as `searchResults` messages.
    search: reported(async function search_(query, token) {
        const text = String(query ?? '').trim()
        if (!text) return false
        runSearch(text, token).catch(e => post('error', { phase: 'search', ...describe(e) }))
        return true
    }),
    cancelSearch: reported(async function cancelSearch() {
        search = null
        return true
    }),
    showMatch: reported(async function showMatch_(cfi) {
        return showMatch(cfi)
    }),
    onPage: reported(async function onPage_(cfis) {
        return onPage(cfis)
    }),
    describe: reported(async function describe_(cfi) {
        return describePlace(cfi)
    }),
    // A KOReader place's `{ cfi, fraction, chapter }`, or `null`.
    resolveXPointer: reported(async function resolveXPointer_(xpointer) {
        return resolveXPointer(xpointer)
    }),
    // KOReader's place for where `cfi` starts, or `null`.
    xpointerAt: reported(async function xpointerAt_(cfi) {
        return xpointerAt(cfi)
    }),
    // The contents and bookmarks placed again in the current layout, for the
    // Contents panel's page numbers.
    contentsOnScreen: reported(async function contentsOnScreen(entries) {
        return refineContents(Array.isArray(entries) ? entries : [], false)
    }),
    bookmarksOnScreen: reported(async function bookmarksOnScreen(cfis) {
        return placeOnScreen(cfis)
    }),
    // Every link in the book and what a tap on it does, for tuning which links
    // are notes (`docs/notes/footnotes.md`).
    noteLinks: reported(async function noteLinks() {
        const links = []
        for (const [index, section] of requireView().book.sections.entries()) {
            const doc = loadedDoc(index) ?? await section.createDocument?.()
            for (const a of doc?.querySelectorAll('a[href]') ?? []) {
                const raw = a.getAttribute('href')
                const href = section.resolveHref?.(raw) ?? raw
                const blocks = isExternalHref(href) ? null : await noteAt(a, href)
                links.push({ section: index, text: a.textContent.trim().slice(0, 40), href: raw, kind: markKind(a), note: blocks })
            }
        }
        return JSON.stringify(links)
    }),
    // The text of the visible page, whitespace collapsed, for debugging and
    // for checking positions against another reader.
    visibleText: reported(async function visibleText(limit = 300) {
        const text = requireView().lastLocation?.range?.toString() ?? ''
        return text.replace(/\s+/g, ' ').trim().slice(0, limit)
    }),
})

post('ready')
postViewport()
