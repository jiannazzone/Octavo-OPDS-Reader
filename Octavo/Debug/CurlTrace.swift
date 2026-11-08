import Foundation
import QuartzCore

/// The curl's steps (`ReaderCurl`), for chasing what only the Duo does:
/// printed in DEBUG when Octavo is launched with `OCTAVO_CURL_TRACE` set,
/// which a device's console shows (`docs/notes/curl.md`). Nothing in
/// Release.
func curlTrace(_ message: @autoclosure () -> String) {
    #if DEBUG
    guard tracesCurl else { return }
    print("[curl \(String(format: "%.3f", CACurrentMediaTime()))] \(message())")
    // A pipe buffers, and a crash would lose the last lines.
    fflush(stdout)
    #endif
}

#if DEBUG
private let tracesCurl = ProcessInfo.processInfo.environment["OCTAVO_CURL_TRACE"] != nil
#endif
