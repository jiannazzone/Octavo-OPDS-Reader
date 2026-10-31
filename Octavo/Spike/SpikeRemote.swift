#if DEBUG
import Foundation

/// SPIKE ONLY, DEBUG ONLY (deleted after the spike). Lets a script on the host
/// drive the spike screens, so position checks don't depend on taps.
///
/// The script writes `Documents/spike-command.json`, e.g.
/// `{"id": 7, "cmd": "goto", "fraction": 0.5}`. The app polls for it, deletes
/// it, runs it, and writes `{"id": 7, "ok": true}` to `spike-ack.json`.
/// Commands: `signin`, `open` (`fileID`), `close`, `goto` (`fraction` or
/// `cfi`), `next`, `prev`, `shape` (`point` or `range`, applies to the next
/// open). Where the reader is goes to `spike-state.json` (`SpikeStateFile`).
enum SpikeRemote {
    struct Command: Decodable {
        var id: Int
        var cmd: String
        var fileID: Int?
        var fraction: Double?
        var cfi: String?
        var shape: String?
    }

    struct Ack: Encodable {
        var id: Int
        var ok: Bool
        var message: String?
    }

    /// The open reader, set by `SpikeReaderView`.
    static weak var reader: ReaderModel?

    static let commandURL = URL.documentsDirectory.appending(path: "spike-command.json")
    static let ackURL = URL.documentsDirectory.appending(path: "spike-ack.json")

    /// Calls `handle` for each command until the task is cancelled.
    static func poll(_ handle: (Command) async -> String?) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            guard let data = try? Data(contentsOf: commandURL) else { continue }
            try? FileManager.default.removeItem(at: commandURL)
            guard let command = try? JSONDecoder().decode(Command.self, from: data) else { continue }
            let failure = await handle(command)
            let ack = Ack(id: command.id, ok: failure == nil, message: failure)
            try? JSONEncoder().encode(ack).write(to: ackURL, options: .atomic)
        }
    }

    /// Reader commands. Returns an error message, or `nil` on success.
    static func handleReaderCommand(_ command: Command) -> String? {
        guard let reader else { return "no open reader" }
        switch command.cmd {
        case "goto":
            if let fraction = command.fraction {
                reader.goTo(fraction: fraction)
            } else if let cfi = command.cfi {
                reader.goTo(cfi: cfi)
            } else {
                return "goto needs fraction or cfi"
            }
        case "next": reader.next()
        case "prev": reader.previous()
        default: return "unknown command \(command.cmd)"
        }
        return nil
    }
}
#endif
