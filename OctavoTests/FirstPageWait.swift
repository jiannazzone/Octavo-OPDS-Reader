import Foundation
import Testing
@testable import Octavo

/// Waits for WebKit to answer once before its suite runs. On a new runner the
/// first pages of a run can stall for minutes, whichever test opens them
/// (`docs/notes/ci.md`), and that says nothing about what the test checks.
/// The tests keep the limits they'd have anyway. Only the suite that runs
/// first takes it: `@Suite(.firstPageWait)`.
nonisolated struct FirstPageWait: SuiteTrait, TestScoping {
    /// Gives up after 5 minutes, and the tests then report for themselves.
    private static let answered = Task { @MainActor in
        let folder = URL.temporaryDirectory.appending(path: "\(TemporaryFiles.prefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = folder.appending(path: "first.epub")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try BookInspectorTests.epub(opf: "<dc:title>First</dc:title>").write(to: book)
        } catch { return }
        let end = ContinuousClock.now + .seconds(300)
        while ContinuousClock.now < end {
            do {
                _ = try await BookInspector().inspect(book)
                return
            } catch BookInspectionError.timedOut {
                continue
            } catch {
                return
            }
        }
    }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        await Self.answered.value
        try await function()
    }
}

extension Trait where Self == FirstPageWait {
    static var firstPageWait: Self { FirstPageWait() }
}
