import Foundation
import Testing

/// Gives each test case a temporary folder of its own, `URL.testDirectory`,
/// and removes it when the case ends, so test files don't pile up in the
/// app's container. Every suite that writes files takes it:
/// `@Suite(.temporaryFiles)`.
nonisolated struct TemporaryFiles: SuiteTrait, TestTrait, TestScoping {
    @TaskLocal static var directory: URL?

    static let prefix = "OctavoTests-"

    /// What an earlier run couldn't remove, cleared before this run's first
    /// case: folders a write that finished late brought back, and defaults
    /// suites, whose plists cfprefsd writes after the process ends.
    private static let sweep: Void = {
        let preferences = URL.libraryDirectory.appending(path: "Preferences", directoryHint: .isDirectory)
        for folder in [URL.temporaryDirectory, preferences] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            for name in names where name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: folder.appending(path: name))
            }
        }
    }()

    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        _ = Self.sweep
        let directory = URL.temporaryDirectory.appending(path: "\(Self.prefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.$directory.withValue(directory) { try await function() }
    }
}

extension Trait where Self == TemporaryFiles {
    static var temporaryFiles: Self { TemporaryFiles() }
}

extension URL {
    /// The running test case's temporary folder, removed when it ends.
    nonisolated static var testDirectory: URL {
        if let directory = TemporaryFiles.directory { return directory }
        Issue.record("This suite writes files: give it @Suite(.temporaryFiles), or they stay in tmp.")
        return .temporaryDirectory
    }
}

extension UserDefaults {
    /// Defaults for one test. Their plist outlives the process, so the next
    /// run of a `.temporaryFiles` suite removes it.
    nonisolated static func testSuite(_ name: String) -> UserDefaults {
        UserDefaults(suiteName: "\(TemporaryFiles.prefix)\(name)-\(UUID().uuidString)")!
    }
}
