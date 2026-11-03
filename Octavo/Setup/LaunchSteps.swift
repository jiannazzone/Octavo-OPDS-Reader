import Foundation
import OctavoKit
import UIKit

/// What runs once at launch, before the shell and its setup exist
/// (`docs/notes/network-trust.md`).
///
/// From `application(_:didFinishLaunchingWithOptions:)`, not `App.init`: that
/// runs before `UIApplicationMain`, when `UIApplication.shared` is nil and
/// `isProtectedDataAvailable` reads false, so nothing ever ran from there.
enum LaunchSteps {
    /// Whether they ran as this process launched, for the launch path's test.
    fileprivate(set) static var ranAtLaunch = false

    /// Not before the first unlock, when neither the Keychain nor the marker
    /// in UserDefaults can be read: the next launch does them.
    ///
    /// - Parameter scope: the servers the sweep may delete from; tests narrow
    ///   it to their own.
    /// - Returns: whether they ran.
    @discardableResult
    static func run(
        protectedDataAvailable: Bool, defaults: UserDefaults = .standard, servers: ServerStore = ServerStore(),
        scope: (String) -> Bool = { _ in true }
    ) -> Bool {
        guard protectedDataAvailable else { return false }
        // Before the marker this sets: an install with one isn't new.
        TourRecord(defaults: defaults).settle()
        // Keychain items outlive the app; a reinstall starts signed out.
        try? ServerCredentials.removeLeftoversAfterInstall(
            hasSavedServer: FileManager.default.fileExists(atPath: servers.fileURL.path), defaults: defaults
        )
        // No setup has started storing: nothing can be tapped until this
        // callback returns.
        try? KeychainSweep.run(servers: servers, scope: scope)
        try? servers.moveSecretsOut()
        return true
    }
}

final class OctavoAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LaunchSteps.ranAtLaunch = LaunchSteps.run(protectedDataAvailable: application.isProtectedDataAvailable)
        return true
    }
}
