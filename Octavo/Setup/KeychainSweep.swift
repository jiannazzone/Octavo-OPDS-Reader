import Foundation
import OctavoKit

/// The launch sweep (step 16, `docs/notes/network-trust.md`): the Keychain
/// keeps only the saved servers' secrets. It deletes what a failed Keychain
/// delete left at Remove server, what a setup left before it finished, and
/// the sign-in of a server signed out of (`SavedServer.signedOut`) if Sign
/// out couldn't delete it.
///
/// Runs once, at launch, before the shell and its setup exist: a setup
/// stores its secrets under a new ID each launch (`SetupModel`), so no
/// setup in progress can lose them. If the saved servers can't be read, or
/// the Keychain can't list its items, nothing is deleted.
nonisolated enum KeychainSweep {
    /// - Parameter scope: the servers it may delete from; tests narrow it
    ///   to their own.
    static func run(servers: ServerStore = ServerStore(), scope: (String) -> Bool = { _ in true }) throws {
        let saved = try servers.read().servers
        let keeping = Set(saved.map(\.id.rawValue))
        // All of it runs; the first failure is thrown after (an item that
        // won't delete mustn't keep a signed-out sign-in).
        var failure: (any Error)?
        do {
            try ServerCredentials.removeAll { account in
                !scope(account) || keeping.contains(account) || keepsForDebugging(account)
            }
        } catch {
            failure = error
        }
        for server in saved where server.signedOut == true {
            do {
                try ServerCredentials.removeSignIn(serverID: server.id.rawValue)
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
    }

    /// The debug servers' fixed IDs (`LibraryModel.localBookOrbitID`, the
    /// debug trust section), which keep their sign-ins without a saved
    /// server so launch arguments don't sign in on every launch.
    private static func keepsForDebugging(_ account: String) -> Bool {
        #if DEBUG
        account.hasPrefix("debug-")
        #else
        false
        #endif
    }
}
