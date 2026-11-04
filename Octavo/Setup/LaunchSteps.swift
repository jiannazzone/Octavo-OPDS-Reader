import Foundation
import OctavoKit
import OSLog
import UIKit

/// What runs once at launch, before the shell and its setup exist
/// (`docs/notes/network-trust.md`).
///
/// From `application(_:didFinishLaunchingWithOptions:)`, not `App.init`: that
/// runs before `UIApplicationMain`, when `UIApplication.shared` is nil and
/// `isProtectedDataAvailable` reads false, so nothing ever ran from there.
enum LaunchSteps {
    enum Step: String {
        case removeLeftovers, sweep, moveSecretsOut
    }

    /// The steps that failed as this process launched, `nil` if they didn't
    /// run, for the launch path's test.
    fileprivate(set) static var failedAtLaunch: [Step]?

    private static let log = Logger(subsystem: "com.ianazzone.ereader", category: "Launch")

    /// Not before the first unlock, when neither the Keychain nor the marker
    /// in UserDefaults can be read: the next launch does them.
    ///
    /// - Parameter scope: the servers they may delete from; tests narrow it
    ///   to their own.
    /// - Returns: the steps that failed, `nil` if they didn't run.
    @discardableResult
    static func run(
        protectedDataAvailable: Bool, defaults: UserDefaults = .standard, servers: ServerStore = ServerStore(),
        scope: (String) -> Bool = { _ in true }
    ) -> [Step]? {
        guard protectedDataAvailable else { return nil }
        var failed: [Step] = []
        func attempt(_ step: Step, _ body: () throws -> Void) {
            do {
                try body()
            } catch {
                log.error("\(step.rawValue, privacy: .public) failed: \(error)")
                failed.append(step)
            }
        }
        // Before the marker this sets: an install with one isn't new.
        TourRecord(defaults: defaults).settle()
        // Keychain items outlive the app; a reinstall starts signed out.
        attempt(.removeLeftovers) {
            try ServerCredentials.removeLeftoversAfterInstall(
                hasSavedServer: FileManager.default.fileExists(atPath: servers.fileURL.path), defaults: defaults, scope: scope
            )
        }
        // No setup has started storing: nothing can be tapped until this
        // callback returns.
        attempt(.sweep) { try KeychainSweep.run(servers: servers, scope: scope) }
        attempt(.moveSecretsOut) { try servers.moveSecretsOut() }
        return failed
    }
}

final class OctavoAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LaunchSteps.failedAtLaunch = LaunchSteps.run(protectedDataAvailable: application.isProtectedDataAvailable)
        return true
    }
}
