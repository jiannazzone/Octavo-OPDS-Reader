import Foundation
import Network
import Observation

/// Tells when the iPhone's connection comes back, so places that didn't
/// reach the server go then (Adam, 2026-11-02: retried while the app is
/// open). Only a return counts: the first report, and losing the
/// connection, change nothing.
@Observable
final class ConnectionMonitor {
    /// Counts the times the connection came back, for the reader to send a
    /// place it couldn't.
    private(set) var returns = 0
    @ObservationIgnored var onReturn: () -> Void = {}
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var wasConnected: Bool?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in self?.update(connected: connected) }
        }
        monitor.start(queue: DispatchQueue(label: "com.ianazzone.ereader.connection"))
    }

    deinit {
        monitor.cancel()
    }

    private func update(connected: Bool) {
        defer { wasConnected = connected }
        guard connected, wasConnected == false else { return }
        connectionReturned()
    }

    /// Also the debug remote's `connectionReturned`: the simulator shares
    /// the Mac's connection, which can't be dropped for one app.
    func connectionReturned() {
        returns += 1
        onReturn()
    }
}
