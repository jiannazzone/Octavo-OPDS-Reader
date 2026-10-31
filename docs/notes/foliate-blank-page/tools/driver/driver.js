// Drives upstream foliate-js's own demo (reader.html / reader.js, unmodified) in a
// same-origin iframe, using only what the demo exposes (`globalThis.reader`).
// Query: ver, book, w, h, section | cfi, steps, interval, render=0|1, resize=0|1, label
const params = new URLSearchParams(location.search)
const ver = params.get('ver') ?? 'main'
const book = params.get('book')
const w = params.get('w') === 'auto' ? innerWidth : Number(params.get('w') ?? 390)
const h = params.get('h') === 'auto' ? innerHeight - 24 : Number(params.get('h') ?? 844)
const section = params.get('section')
const startCFI = params.get('cfi')
const steps = Number(params.get('steps') ?? 8)
const interval = Number(params.get('interval') ?? 1000)
const renderTest = params.get('render') !== '0'
const resizeTest = params.get('resize') === '1'
const label = params.get('label') ?? ''
const probe = params.get('probe')

const t0 = performance.now()
const now = () => Math.round(performance.now() - t0)
const sleep = ms => new Promise(r => setTimeout(r, ms))
const status = document.getElementById('status')
const say = s => status.textContent = s

const nodeDesc = n => {
    if (!n) return null
    if (n.nodeType === 3) return `#text("${n.nodeValue.replace(/\s+/g, ' ').trim().slice(0, 24)}")`
    let s = n.localName
    if (n.id) s += '#' + n.id
    if (typeof n.className === 'string' && n.className) s += '.' + n.className.trim().split(/\s+/).join('.')
    return s
}
const describe = range => range ? {
    collapsed: range.collapsed,
    start: `${nodeDesc(range.startContainer)}:${range.startOffset}`,
    end: `${nodeDesc(range.endContainer)}:${range.endOffset}`,
    text: range.toString().replace(/\s+/g, ' ').trim().slice(0, 60),
    isBodyFallback: range.collapsed && range.startContainer.nodeType === 1
        && range.startContainer.localName === 'body' && range.startOffset === 0,
} : null

const iframe = document.createElement('iframe')
iframe.style.cssText = `width:${w}px;height:${h}px;border:0;display:block`
iframe.src = `/${ver}/reader.html?url=${encodeURIComponent('/books/' + book)}`
document.getElementById('frame').append(iframe)

const result = {
    label, ver, book, w, h, section, startCFI, steps, interval,
    ua: navigator.userAgent, dpr: devicePixelRatio, vw: innerWidth, vh: innerHeight, steps_: [], events: [], errors: [],
}
const events = result.events

const post = () => fetch('/log', { method: 'POST', body: JSON.stringify(result) })
const beacon = stage => fetch('/log', { method: 'POST', body: JSON.stringify({ label: `${label}:${stage}`, t: now(), errors: result.errors }) })
iframe.addEventListener('load', () => {
    const win = iframe.contentWindow
    win.addEventListener('error', e => result.errors.push(`error: ${e.message} ${e.filename}:${e.lineno}`))
    win.addEventListener('unhandledrejection', e => result.errors.push(`rejection: ${e.reason?.stack ?? e.reason}`))
    const { error } = win.console
    win.console.error = (...a) => { result.errors.push('console.error: ' + a.map(String).join(' ')); error.apply(win.console, a) }
    beacon('iframe-load')
})

try {
    say('loading')
    let reader
    for (let i = 0; i < 1500; i++) {
        reader = iframe.contentWindow?.reader
        if (reader?.view?.renderer?.getContents?.().length) break
        await sleep(100)
    }
    if (!reader?.view) throw new Error('demo reader did not open the book')
    beacon('opened')
    iframe.contentWindow.addEventListener('error', e => result.errors.push(String(e.message)))
    const { view } = reader
    const r = view.renderer
    result.sections = view.book.sections.length
    const flow = params.get('flow')
    if (flow) r.setAttribute('flow', flow)
    // like a host app that shows the CFI in a status strip above the reader:
    // the strip wraps to more lines for longer CFIs, so the reader's height
    // depends on the location
    if (params.get('hoststrip') === '1') view.addEventListener('relocate', ({ detail }) => {
        const lines = Math.max(1, Math.min(3, Math.ceil((detail.cfi?.length ?? 0) / 24)))
        iframe.style.height = `${h - lines * 14}px`
    })

    const watchDoc = doc => {
        if (!doc?.body) return
        new ResizeObserver(entries => {
            for (const e of entries) events.push({
                t: now(), type: 'bodyResize',
                w: Math.round(e.contentRect.width), h: Math.round(e.contentRect.height),
            })
        }).observe(doc.body)
        for (const img of doc.images) if (!img.complete)
            img.addEventListener('load', () => events.push({ t: now(), type: 'imgLoad', src: img.src.slice(-30) }))
        doc.fonts?.addEventListener?.('loadingdone', () => events.push({ t: now(), type: 'fontsLoaded' }))
    }
    view.addEventListener('load', ({ detail: { doc, index } }) => {
        events.push({ t: now(), type: 'load', index })
        watchDoc(doc)
    })
    for (const { doc } of r.getContents()) watchDoc(doc)
    r.addEventListener('relocate', ({ detail }) => events.push({
        t: now(), type: 'relocate', reason: detail.reason, index: detail.index,
        fraction: detail.fraction, page: r.page, pages: r.pages,
        cfi: view.getCFI(detail.index, detail.range), range: describe(detail.range),
    }))
    r.addEventListener('scroll', () => {
        const last = events.at(-1)
        const page = r.page
        if (last?.type === 'scroll' && last.page === page) return
        events.push({ t: now(), type: 'scroll', page })
    })

    const mode = params.get('mode') ?? 'walk'
    const here = () => ({
        index: r.getContents()[0]?.index, page: r.page, pages: r.pages,
        cfi: view.lastLocation?.cfi, range: describe(view.lastLocation?.range),
    })
    await sleep(interval)

    if (mode === 'blank') {
        // land on page `page` of `section` by paging forward from its start,
        // then disturb the layout in different ways and see where we end up
        const page = Number(params.get('page'))
        const land = async () => {
            await view.goTo(Number(section))
            await sleep(interval)
            for (let i = 1; i < page; i++) {
                await view.next()
                await sleep(interval)
            }
            return here()
        }
        const t = result.blank = { page }
        const run = async (name, disturb) => {
            say(name)
            const mark = events.length
            const landed = await land()
            await disturb()
            await sleep(interval)
            t[name] = { landed, after: here(), events: events.slice(mark) }
        }
        await run('render', () => r.render())
        await run('resize', async () => {
            iframe.style.width = `${w + 1}px`
            await sleep(interval)
            iframe.style.width = `${w}px`
        })
        await run('bodyResize', async () => {
            // what a late image or font load does: the section's body changes size
            const div = r.getContents()[0].doc.createElement('div')
            div.style.height = '1px'
            r.getContents()[0].doc.body.append(div)
            await sleep(interval)
            div.remove()
        })
        await run('restoreCFI', async () => {
            const { cfi } = here()
            await view.goTo(Number(section) === 0 ? 1 : 0)
            await sleep(interval)
            await view.goTo(cfi)
        })
        await run('nextThenPrev', async () => {
            await view.next()
            await sleep(interval)
            t.nextThenPrev_next = here()
            await view.prev()
        })
        await run('nextThenPrevThenRender', async () => {
            await view.next()
            await sleep(interval)
            await view.prev()
            await sleep(interval)
            r.render()
        })
    }

    if (mode === 'dump') {
        // page quickly through the first `per` pages of every linear section
        const per = Number(params.get('per') ?? 12)
        const from = Number(params.get('from') ?? 0)
        const to = Math.min(Number(params.get('to') ?? Infinity), view.book.sections.length)
        result.dump = []
        for (let s = from; s < to; s++) {
            if (view.book.sections[s].linear === 'no') continue
            say(`section ${s}`)
            await view.goTo(s)
            await sleep(interval)
            for (let i = 0; i < per; i++) {
                const h = here()
                if (h.index !== s) break
                result.dump.push({ s, i, page: h.page, pages: h.pages, cfi: h.cfi, range: h.range })
                await view.next()
                await sleep(interval)
            }
        }
    }

    if (mode === 'walk') {
    say('navigating')
    if (section != null) await view.goTo(Number(section))
    else if (startCFI) await view.goTo(startCFI)
    await sleep(interval)
    result.start = { index: r.getContents()[0]?.index, page: r.page, pages: r.pages, cfi: view.lastLocation?.cfi }

    for (let i = 0; i < steps; i++) {
        say(`step ${i}`)
        const step = { i, before: { index: r.getContents()[0]?.index, page: r.page } }
        let mark = events.length
        step.tTurn = now()
        await view.goRight()
        step.afterTurn = { page: r.page }
        await sleep(interval)
        step.settled = {
            index: r.getContents()[0]?.index, page: r.page, pages: r.pages,
            cfi: view.lastLocation?.cfi, range: describe(view.lastLocation?.range),
        }
        step.events = events.slice(mark)
        step.landedOnBody = step.events.some(e => e.type === 'relocate' && e.range?.isBodyFallback)
        step.jumped = step.afterTurn.page !== step.settled.page
        if (renderTest) {
            mark = events.length
            const page = r.page, cfi = view.lastLocation?.cfi
            r.render()
            await sleep(500)
            step.render = { pageBefore: page, pageAfter: r.page, cfiBefore: cfi, cfiAfter: view.lastLocation?.cfi, events: events.slice(mark) }
        }
        if (resizeTest) {
            mark = events.length
            const page = r.page
            iframe.style.width = `${w + 1}px`
            await sleep(500)
            const mid = r.page
            iframe.style.width = `${w}px`
            await sleep(500)
            step.resize = { pageBefore: page, pageWide: mid, pageAfter: r.page, cfiAfter: view.lastLocation?.cfi, events: events.slice(mark) }
        }
        if (probe && step.landedOnBody && !result.probe) {
            const doc = r.getContents()[0].doc
            const rect = el => [...el.getClientRects()].map(q => [q.left, q.top, q.width, q.height].map(Math.round))
            result.probe = {
                page: r.page, size: r.size, start: r.start, end: r.end,
                html: rect(doc.documentElement), body: rect(doc.body),
                columnHeight: doc.documentElement.clientHeight,
                elements: [...doc.querySelectorAll(probe)].slice(0, 12).map(el => ({
                    el: nodeDesc(el), rects: rect(el),
                    margin: getComputedStyle(el).margin,
                    breakBefore: getComputedStyle(el).breakBefore, breakAfter: getComputedStyle(el).breakAfter,
                })),
            }
        }
        result.steps_.push(step)
    }
    }
} catch (e) {
    result.errors.push(String(e?.stack ?? e))
}
result.done = now()
await post()
document.getElementById('out').textContent = JSON.stringify(result)
document.title = 'DONE'
say('done')
