import SwiftUI

@main
struct OctavoApp: App {
    /// Runs `LaunchSteps` as the app launches.
    @UIApplicationDelegateAdaptor private var appDelegate: OctavoAppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
