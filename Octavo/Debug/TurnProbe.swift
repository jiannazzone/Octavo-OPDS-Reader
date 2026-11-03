#if DEBUG
import SwiftUI
import UIKit
import WebKit

/// DEBUG ONLY. Measures what a page turn drawn from snapshots needs
/// (decision 27, `docs/notes/page-turns.md`): how long a snapshot of the
/// page takes, and how soon after an instant turn the new page shows in a
/// snapshot, with the page uncovered or under a cover of itself.
/// `ReaderRemote`'s `turnProbe` command runs it in a few seconds; results go
/// to `Documents/turn-probe.json`, the snapshots it judged to
/// `Documents/turn-probe-*.png`.
enum TurnProbe {
    struct Report: Encodable {
        var host: String?
        /// Milliseconds per call.
        var snapshotView: [Double] = []
        var halfSnapshotView: [Double] = []
        var exportedImage: [Double] = []
        var turns: [Turn] = []
    }

    struct Turn: Encodable {
        var kind: String
        var cover: String
        var crossesSection = false
        /// From the turn's call to its first relocation reaching Swift.
        var relocatedAfter: Double?
        /// Milliseconds after the call → what the snapshot shows: the page
        /// before the turn, after it, or neither (blank, or in between).
        var snapshots: [String: String] = [:]
    }

    static let reportURL = URL.documentsDirectory.appending(path: "turn-probe.json")
    /// When each turn's snapshots are taken, in milliseconds after the call.
    static let times: [Double] = [0, 20, 40, 70, 100, 150, 250, 400]

    static func run(_ reader: ReaderModel) async -> String? {
        guard let window = keyWindow(), let web = webView(in: window) else { return "no web view" }
        guard reader.toc.count > 10 else { return "needs a book with contents" }
        let host = hostingAncestor(of: web) ?? web
        var report = Report()
        report.host = "\(type(of: host)) \(host.convert(host.bounds, to: window))"
        for _ in 0..<5 {
            report.snapshotView.append(time { _ = host.snapshotView(afterScreenUpdates: false) })
            let half = CGRect(x: host.bounds.midX, y: 0, width: host.bounds.width / 2, height: host.bounds.height)
            report.halfSnapshotView.append(time { _ = host.resizableSnapshotView(from: half, afterScreenUpdates: false, withCapInsets: .zero) })
        }
        for _ in 0..<3 {
            let start = ContinuousClock.now
            _ = try? await reader.page.exported(as: .image(afterScreenUpdates: false))
            report.exportedImage.append(milliseconds(since: start))
        }
        var chapter = 6
        for cover in ["none", "opaque", "translucent"] {
            // The third page of a chapter, then a chapter's last page.
            await go(reader, to: chapter)
            await step(reader, forward: true)
            await step(reader, forward: true)
            report.turns.append(await turn(reader, host: host, window: window, kind: "within", cover: cover))
            await go(reader, to: chapter + 1)
            await step(reader, forward: false)
            report.turns.append(await turn(reader, host: host, window: window, kind: "across", cover: cover))
            chapter += 2
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: reportURL, options: .atomic)
        return nil
    }

    /// Snapshots the page at `times` after an instant turn, with the page
    /// uncovered or under a snapshot of itself, and judges each against the
    /// pages before and after.
    private static func turn(_ reader: ReaderModel, host: UIView, window: UIWindow, kind: String, cover mode: String) async -> Turn {
        var result = Turn(kind: kind, cover: mode)
        let section = reader.relocation?.sectionIndex
        let before = image(of: host)
        let cover = host.snapshotView(afterScreenUpdates: false) ?? UIView()
        cover.frame = host.convert(host.bounds, to: window)
        if mode == "translucent" { cover.alpha = 0.99 }
        if mode != "none" { window.addSubview(cover) }
        defer { cover.removeFromSuperview() }

        var shots: [(Double, UIView?)] = []
        let relocations = reader.relocationCount
        let start = ContinuousClock.now
        reader.next()
        for time in times {
            while milliseconds(since: start) < time {
                if result.relocatedAfter == nil, reader.relocationCount != relocations {
                    result.relocatedAfter = milliseconds(since: start)
                }
                try? await Task.sleep(for: .milliseconds(2))
            }
            shots.append((milliseconds(since: start), host.snapshotView(afterScreenUpdates: false)))
        }
        try? await Task.sleep(for: .milliseconds(300))
        result.crossesSection = reader.relocation?.sectionIndex != section
        cover.removeFromSuperview()
        try? await Task.sleep(for: .milliseconds(150))
        let after = image(of: host)
        save(before, "\(kind)-\(mode)-before")
        save(after, "\(kind)-\(mode)-after")
        for (time, shot) in shots {
            guard let shot else { continue }
            shot.frame = host.bounds
            let drawn = image(of: shot, in: window)
            result.snapshots[String(format: "%03.0f", time)] = judge(drawn, before: before, after: after)
            save(drawn, "\(kind)-\(mode)-\(Int(time))")
        }
        return result
    }

    /// The start of contents entry `index`.
    private static func go(_ reader: ReaderModel, to index: Int) async {
        guard reader.toc.indices.contains(index), let href = reader.toc[index].href else { return }
        await settle(reader) { reader.goTo(target: href) }
    }

    private static func step(_ reader: ReaderModel, forward: Bool) async {
        await settle(reader) { forward ? reader.next() : reader.previous() }
    }

    /// Runs `move`, then waits for its relocations to stop.
    private static func settle(_ reader: ReaderModel, _ move: () -> Void) async {
        let count = reader.relocationCount
        move()
        let start = ContinuousClock.now
        while reader.relocationCount == count, milliseconds(since: start) < 2000 { try? await Task.sleep(for: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(400))
    }

    // MARK: Helpers

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
    }

    private static func webView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap(webView).first
    }

    private static func hostingAncestor(of view: UIView) -> UIView? {
        var current = view.superview
        while let view = current {
            if String(describing: type(of: view)).contains("HostingView") { return view }
            current = view.superview
        }
        return nil
    }

    private static func time(_ body: () -> Void) -> Double {
        let start = ContinuousClock.now
        body()
        return milliseconds(since: start)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = (ContinuousClock.now - start).components
        return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    }

    /// The view as the screen shows it, at half size.
    private static func image(of view: UIView, in window: UIWindow? = nil) -> UIImage {
        var added = false
        if view.window == nil, let window {
            window.addSubview(view)
            added = true
        }
        defer { if added { view.removeFromSuperview() } }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.5
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    private static func save(_ image: UIImage, _ name: String) {
        try? image.pngData()?.write(to: URL.documentsDirectory.appending(path: "turn-probe-\(name).png"))
    }

    /// "before", "after" or "neither", by mean grey-level difference.
    private static func judge(_ image: UIImage, before: UIImage, after: UIImage) -> String {
        guard let shot = grey(image), let b = grey(before), let a = grey(after), shot.count == b.count, b.count == a.count else {
            return "unsized"
        }
        let toBefore = difference(shot, b), toAfter = difference(shot, a)
        let word = toBefore < 1 ? "before" : toAfter < 1 ? "after" : "neither"
        return String(format: "%@ (%.1f / %.1f)", word, toBefore, toAfter)
    }

    private static func difference(_ x: [UInt8], _ y: [UInt8]) -> Double {
        var total = 0
        for i in x.indices { total += abs(Int(x[i]) - Int(y[i])) }
        return Double(total) / Double(max(x.count, 1))
    }

    private static func grey(_ image: UIImage) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? data : nil
    }
}
#endif
