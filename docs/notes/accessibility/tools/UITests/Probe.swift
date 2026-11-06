import XCTest

/// Takes commands from `$PROBE_IO/cmd.txt` and answers in `$PROBE_IO/out-*.txt`, so
/// `probe.sh` can read the running app's accessibility tree and run Apple's audit
/// on whatever screen it's on (`docs/notes/accessibility.md`).
final class Probe: XCTestCase {
    func testLoop() throws {
        let io = try XCTUnwrap(ProcessInfo.processInfo.environment["PROBE_IO"])
        continueAfterFailure = true
        let app = XCUIApplication(bundleIdentifier: "com.ianazzone.ereader")
        app.activate()
        let cmdPath = io + "/cmd.txt"
        while true {
            guard let raw = try? String(contentsOfFile: cmdPath, encoding: .utf8), !raw.isEmpty else {
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            try? FileManager.default.removeItem(atPath: cmdPath)
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1).map(String.init)
            let verb = parts.first ?? "", arg = parts.count > 1 ? parts[1] : ""
            var out = ""
            switch verb {
            case "exit":
                return
            case "dump":
                out = app.debugDescription
            case "audit":
                var issues: [String] = []
                do {
                    try app.performAccessibilityAudit(for: .all) { issue in
                        let element = issue.element
                        issues.append("[\(issue.auditType)] \(issue.compactDescription) :: \(issue.detailedDescription) :: el='\(element?.label ?? "-")' type=\(element?.elementType.rawValue ?? 0) frame=\(element?.frame ?? .zero)")
                        return true
                    }
                } catch {
                    issues.append("ERROR \(error)")
                }
                out = issues.joined(separator: "\n") + "\n(\(issues.count) issues)"
            case "tap":
                // Not one hidden or covered: the tree lists those too.
                let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", arg))
                if matches.firstMatch.waitForExistence(timeout: 3),
                   let element = matches.allElementsBoundByIndex.first(where: \.isHittable) {
                    element.tap()
                    out = "tapped \(arg)"
                } else {
                    out = "not found \(arg)"
                }
            default:
                out = "unknown \(raw)"
            }
            try? out.write(toFile: io + "/out.tmp", atomically: true, encoding: .utf8)
            try? FileManager.default.moveItem(atPath: io + "/out.tmp", toPath: io + "/out-\(UUID().uuidString.prefix(4)).txt")
        }
    }
}
