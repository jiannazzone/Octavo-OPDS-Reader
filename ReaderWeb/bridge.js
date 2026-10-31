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
// visibleText/...`, called with `WebPage.callJavaScript`. Each returns a
// promise that Swift awaits.

import './foliate-js/view.js'
import * as CFI from './foliate-js/epubcfi.js'

const HANDLER = 'octavo'

// Fraction of the page width that counts as a "previous/next page" tap zone,
// on each side. Taps in the middle are reported to Swift instead.
const TAP_ZONE = 0.3

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
const postViewport = () => post('viewport', { width: innerWidth, height: innerHeight })
window.addEventListener('resize', postViewport)

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

const onRelocate = ({ detail }) => {
    post('relocate', {
        cfi: detail.cfi ?? null,
        startCFI: startOf(detail.cfi),
        blankPage: isBlankPage(detail.range),
        fraction: finiteOrNull(detail.fraction),
        tocLabel: detail.tocItem?.label?.trim() || null,
        sectionIndex: detail.section?.current ?? null,
        sectionCount: detail.section?.total ?? null,
        location: detail.location
            ? { current: finiteOrNull(detail.location.current), total: finiteOrNull(detail.location.total) }
            : null,
    })
}

// A tap is a short press that barely moves. Anything longer or further is a
// swipe (foliate's paginator handles those) or a text selection.
const TAP_SLOP = 10
const TAP_MAX_MS = 500

// Taps are detected from pointer events: iOS WebKit doesn't dispatch `click`
// to a document-level listener when the tapped element isn't itself
// clickable, which is most of a book.
//
// Section documents live in iframes that are wider than the screen (one
// column per page) and scrolled by the paginator, so the tap is converted to
// the top window's coordinates before deciding which side it was on.
const onSectionLoad = ({ detail: { doc } }) => {
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
        const frame = doc.defaultView?.frameElement
        if (!frame) return
        const x = frame.getBoundingClientRect().left + e.clientX
        const width = window.innerWidth
        if (x < width * TAP_ZONE) view?.goLeft()
        else if (x > width * (1 - TAP_ZONE)) view?.goRight()
        else post('tap', { zone: 'middle' })
    })
}

// Lays pages out the way Swift's `ReaderLayout` says: column count, gap and
// text width through foliate's own attributes, and the view's left/right
// insets so foliate's centred gap sits over the fold. `max-column-count-
// portrait` is our patch 0002; without it a portrait reader area always gets
// one column. Missing values fall back to foliate's defaults.
const applyLayout = () => {
    if (!view?.renderer) return
    const renderer = view.renderer
    const set = (name, value) => value === null || value === undefined
        ? renderer.removeAttribute(name)
        : renderer.setAttribute(name, String(value))
    view.style.left = `${layout?.leftInset ?? 0}px`
    view.style.right = `${layout?.rightInset ?? 0}px`
    set('max-column-count', layout?.columns)
    set('max-column-count-portrait', layout?.columns)
    set('gap', layout?.gapPercent === null || layout?.gapPercent === undefined ? null : `${layout.gapPercent}%`)
    set('max-inline-size', layout?.maxInlineSize === null || layout?.maxInlineSize === undefined ? null : `${layout.maxInlineSize}px`)
    // A changed column count doesn't always resize anything, so foliate
    // wouldn't notice. Re-rendering keeps the paginator's anchor.
    renderer.render()
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

// Try the CFI first, then the fraction, then the start of the book.
// Fixed-layout books go by fraction first, like BookOrbit does.
const restore = async (cfi, fraction) => {
    const byFraction = async () => {
        if (fraction === null || fraction <= 0) return false
        await view.goToFraction(Math.min(fraction, 1))
        await anchorToPage()
        return true
    }
    if (view.isFixedLayout && await byFraction()) return 'fraction'
    if (cfi && await view.goTo(cfi)) return 'cfi'
    if (await byFraction()) return 'fraction'
    await view.init({ showTextStart: false })
    return 'start'
}

const open = async ({ url, name, cfi = null, fraction = null, layout: initialLayout = undefined }) => {
    if (view) {
        view.close()
        view.remove()
    }
    view = document.createElement('foliate-view')
    view.addEventListener('relocate', onRelocate)
    view.addEventListener('load', onSectionLoad)
    // foliate would `window.open` external links; hand them to Swift instead.
    view.addEventListener('external-link', e => {
        e.preventDefault()
        post('externalLink', { href: e.detail.href })
    })
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
    view.renderer.setAttribute('flow', 'paginated')
    if (initialLayout !== undefined) layout = initialLayout
    applyLayout()

    const restoredFrom = await restore(cfi, finiteOrNull(fraction))
    const result = {
        restoredFrom,
        title: plainText(view.book.metadata?.title),
        sectionCount: view.book.sections?.length ?? 0,
        isFixedLayout: view.isFixedLayout,
    }
    post('opened', result)
    return result
}

const requireView = () => {
    if (!view) throw new Error('No book is open')
    return view
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
    goTo: reported(async function goTo(cfi) {
        return Boolean(await requireView().goTo(cfi))
    }),
    goToFraction: reported(async function goToFraction(fraction) {
        await requireView().goToFraction(Math.max(0, Math.min(1, fraction)))
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
    setLayout: reported(async function setLayout(newLayout) {
        layout = newLayout
        applyLayout()
        return true
    }),
    layoutReport: reported(async function layoutReport_() {
        return layoutReport()
    }),
    locate: reported(async function locate_(cfi) {
        return locate(cfi)
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
