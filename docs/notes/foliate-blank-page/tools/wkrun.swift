// Loads one driver URL in a plain macOS WKWebView (system WebKit) and exits when the
// page sets its title to DONE. Usage: wkrun URL WIDTH HEIGHT [TIMEOUT] [hidden]
import AppKit
import WebKit

let args = CommandLine.arguments
let url = URL(string: args[1])!
let w = Double(args[2])!, h = Double(args[3])!
let timeout = args.count > 4 ? Double(args[4])! : 120
let hidden = args.count > 5 && args[5] == "hidden"

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w + 40, height: h + 80),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let config = WKWebViewConfiguration()
    // keep timers and rendering running even if the window is covered
    config.preferences.inactiveSchedulingPolicy = .none
    let web = WKWebView(frame: window.contentView!.bounds, configuration: config)
    web.autoresizingMask = [.width, .height]
    window.contentView!.addSubview(web)
    if !hidden { window.orderFrontRegardless() }
    web.load(URLRequest(url: url))
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        MainActor.assumeIsolated {
            if web.title == "DONE" { exit(0) }
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { exit(1) }
    app.run()
}
