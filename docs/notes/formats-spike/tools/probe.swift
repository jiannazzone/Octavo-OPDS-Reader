// Formats spike: opens a book with the real bridge.js + foliate-js in a plain
// macOS WKWebView (system WebKit), runs collect.js, prints its JSON, exits.
//
//   swiftc -o probe probe.swift
//   [PROBE_SECTIONS='[0,2]' PROBE_STEP=3 ...] probe BASE BOOK SCRIPT_JS [WAIT_MS] [click]
//
// BASE is harness.py's origin (http://localhost:8798). The window is the
// folded Duo's reader size.
import AppKit
import WebKit

let args = CommandLine.arguments
let base = args[1], book = args[2]
let wait = args.count > 4 ? args[4] : "2500"
let click = args.count > 5 && args[5] == "click"
// __NAME__ placeholders come from PROBE_NAME environment variables.
var collector = try! String(contentsOfFile: args[3], encoding: .utf8)
    .replacingOccurrences(of: "__WAIT__", with: wait)
    .replacingOccurrences(of: "__CLICK__", with: click ? "true" : "false")
for (key, value) in ProcessInfo.processInfo.environment where key.hasPrefix("PROBE_") {
    collector = collector.replacingOccurrences(of: "__\(key.dropFirst(6))__", with: value)
}
collector = collector.replacingOccurrences(of: "__SECTIONS__", with: "null")

func emit(_ object: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])) ?? Data("\(object)".utf8)
    print(String(decoding: data, as: UTF8.self))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 466, height: 678),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let config = WKWebViewConfiguration()
    config.preferences.inactiveSchedulingPolicy = .none
    let web = WKWebView(frame: window.contentView!.bounds, configuration: config)
    web.autoresizingMask = [.width, .height]
    window.contentView!.addSubview(web)
    window.orderFrontRegardless()
    web.load(URLRequest(url: URL(string: base + "/reader.html")!))
    Task { @MainActor in
        do {
            for _ in 0..<150 {
                if (try? await web.evaluateJavaScript("typeof window.octavo")) as? String == "object" { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            let started = Date()
            let opened = try await web.callAsyncJavaScript(
                "return await window.octavo.open({ url, name })",
                arguments: ["url": base + "/book/" + book, "name": book], contentWorld: .page)
            let openSeconds = Date().timeIntervalSince(started)
            let report = try await web.callAsyncJavaScript(collector, contentWorld: .page)
            emit(["book": book, "opened": opened ?? NSNull(), "openSeconds": openSeconds, "report": report ?? NSNull()])
            exit(0)
        } catch {
            emit(["book": book, "error": String(describing: error)])
            exit(1)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 300) { emit(["book": book, "error": "timeout"]); exit(2) }
    app.run()
}
