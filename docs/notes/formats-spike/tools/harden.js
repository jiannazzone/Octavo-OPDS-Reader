/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// Formats spike PROTOTYPE (not shipped): a second, format-independent layer
// against book scripts, for bridge.js to apply between `view.open()` and the
// first page. It wraps every section's `load()` so each section document is
// neutralized before foliate's paginator puts it in an iframe:
//
// - sanitize: every <script> (HTML or SVG) gets an inert type and loses its
//   src; on* attributes and javascript:/vbscript: URLs are dropped; nested
//   frames, objects and embeds lose what they would load; meta refresh and
//   <base href> are disarmed. Nodes are never added, removed or moved in the
//   body, so CFIs stay identical (checked by cfi-walk.js).
// - meta: a Content-Security-Policy <meta> goes first in <head>, so the
//   section blocks scripts on its own even if the CSP it inherits from the
//   reader page were ever lost. Only <head> changes; CFIs go through <body>.
//
// harness.py serves this at /foliate-js/octavo-harden.js and patches the
// bridge to call harden() in its `+sanitize`/`+meta` modes.

const XLINK = 'http://www.w3.org/1999/xlink'
const XHTML = 'http://www.w3.org/1999/xhtml'
const INERT = 'application/x-octavo-blocked'
// Like the reader page's policy, but no scripts at all and no nested frames.
// 'self' is the reader's origin, which blob: section documents inherit.
export const SECTION_POLICY = [
    "default-src 'self' blob: data:",
    "script-src 'none'",
    "style-src 'self' 'unsafe-inline' blob: data:",
    "img-src 'self' blob: data:",
    "font-src 'self' blob: data:",
    "media-src 'self' blob: data:",
    "connect-src 'none'",
    "object-src 'none'",
    "frame-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
].join('; ')

const isScriptURL = value => /^(javascript|vbscript):/i.test(value.replace(/[\u0000- ]/g, ''))

export const sanitize = doc => {
    const changes = []
    for (const el of doc.querySelectorAll('*')) {
        const name = el.localName.toLowerCase()
        for (const attr of [...el.attributes]) {
            if (/^on/i.test(attr.localName) || isScriptURL(attr.value)) {
                el.removeAttributeNode(attr)
                changes.push(`${name}@${attr.name}`)
            }
        }
        if (name === 'script') {
            el.setAttribute('type', INERT)
            el.removeAttribute('src')
            el.removeAttribute('href')
            el.removeAttributeNS(XLINK, 'href')
            changes.push('script')
        } else if (['iframe', 'frame', 'object', 'embed', 'applet', 'portal'].includes(name)) {
            for (const attr of ['src', 'srcdoc', 'data', 'code', 'codebase', 'archive'])
                el.removeAttribute(attr)
            changes.push(name)
        } else if (name === 'meta' && el.getAttribute('http-equiv')?.toLowerCase() === 'refresh') {
            el.removeAttribute('http-equiv')
            changes.push('meta-refresh')
        } else if (name === 'base' && el.hasAttribute('href')) {
            el.removeAttribute('href')
            changes.push('base')
        }
    }
    return changes
}

export const addPolicy = doc => {
    const head = doc.querySelector('head')
    if (!head) return false
    const meta = doc.createElementNS(head.namespaceURI ?? XHTML, 'meta')
    meta.setAttribute('http-equiv', 'Content-Security-Policy')
    meta.setAttribute('content', SECTION_POLICY)
    head.prepend(meta)
    return true
}

export const harden = (book, { sanitize: doSanitize = true, meta = true } = {}) => {
    const log = []
    for (const section of book.sections ?? []) {
        if (!section.load) continue
        const load = section.load.bind(section)
        let cached = null
        section.load = async () => {
            if (cached) return cached
            const url = await load()
            const blob = await (await fetch(url)).blob()
            const type = blob.type || 'application/xhtml+xml'
            const doc = new DOMParser().parseFromString(await blob.text(), type)
            if (doc.querySelector('parsererror')) return url // leave what foliate made
            const changes = doSanitize ? sanitize(doc) : []
            const policy = meta ? addPolicy(doc) : false
            log.push({ id: section.id, changes: changes.length, policy })
            cached = URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(doc)], { type }))
            return cached
        }
    }
    globalThis.__octavoHardenLog = log
    return log
}
