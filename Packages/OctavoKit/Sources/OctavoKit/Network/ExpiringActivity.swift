import Foundation

/// Keeps the app running for a little while if it goes to the background
/// before `end()`, so work like saving a rotated token isn't cut off by
/// suspension. The system may still end it early; then it just stops holding
/// on. (macOS, where `swift test` runs, doesn't suspend apps: nothing to do.)
final class ExpiringActivity: Sendable {
    private let finished = DispatchSemaphore(value: 0)

    init(reason: String) {
        #if !os(macOS)
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { [finished] expired in
            if expired {
                // Time's up: let the waiting call below return.
                finished.signal()
            } else {
                // The activity lasts as long as this block runs.
                _ = finished.wait(timeout: .now() + 30)
            }
        }
        #endif
    }

    func end() {
        finished.signal()
    }
}
