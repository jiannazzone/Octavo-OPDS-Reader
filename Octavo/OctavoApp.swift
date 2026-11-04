import OctavoKit
import SwiftUI

@main
struct OctavoApp: App {
    init() {
        // Keychain items outlive the app; a reinstall starts signed out. Not
        // before the first unlock, when neither the Keychain nor the marker
        // in UserDefaults can be read.
        if UIApplication.shared.isProtectedDataAvailable {
            // Before the marker this sets: an install with one isn't new.
            TourRecord().settle()
            try? ServerCredentials.removeLeftoversAfterInstall()
            // Before the shell exists, so no setup has started storing yet.
            try? KeychainSweep.run()
            try? ServerStore().moveSecretsOut()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
