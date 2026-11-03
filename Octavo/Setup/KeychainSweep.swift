import Foundation
import OctavoKit

/// The launch sweep (step 16, `docs/notes/network-trust.md`): the Keychain
/// keeps only the saved server's secrets. It deletes what a failed Keychain
/// delete left at Remove server, what a setup left before it finished, and
/// the sign-in of a server signed out of (`SavedServer.signedOut`) if Sign
/// out couldn't delete it.
///
/// Runs once, at launch, before the shell and its setup exist: a setup
/// stores its secrets under a new ID each launch (`SetupModel`), so no
/// setup in progress can lose them. If the saved server can't be read, or
/// the Keychain can't list its items, nothing is deleted.
nonisolated enum KeychainSweep {
    /// - Parameter scope: the servers it may delete from; tests narrow it
    ///   to their own.
    static func run(servers: ServerStore = ServerStore(), scope: (String) -> Bool = { _ in true }) throws {
        let saved = try servers.read()
        try ServerCredentials.removeAll { account in
            !scope(account) || account == saved?.id.rawValue || keepsForDebugging(account)
        }
        if let saved, saved.signedOut == true {
            try ServerCredentials.removeSignIn(serverID: saved.id.rawValue)
        }
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
