import UIKit

/// What the app calls the device it's on, wherever it names it ("On iPad",
/// "Remove from this iPhone?"): "iPad" on an iPad, else "iPhone", the Duo
/// included (Adam, 2026-11-09). One place, so no screen works it out itself.
enum ThisDevice {
    static var name: String { name(for: UIDevice.current.userInterfaceIdiom) }

    nonisolated static func name(for idiom: UIUserInterfaceIdiom) -> String {
        idiom == .pad ? "iPad" : "iPhone"
    }
}
