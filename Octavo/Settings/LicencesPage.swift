import Foundation
import SwiftUI

/// About's Licences (Adam, 2026-11-02): Octavo's own, then each component
/// with its full text, from the `THIRD-PARTY-NOTICES.md` the app bundles.
struct LicencesPage: View {
    private let notices = ThirdPartyNotice.bundled()

    var body: some View {
        SettingsPageList(title: "Licences") {
            Section {
                Text("Octavo: Mozilla Public License 2.0, with the components below under their own licences.")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
            ForEach(notices) { notice in
                Section {
                    Text(notice.paragraphs.joined(separator: "\n\n"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.name)
                            .font(.headline)
                            .foregroundStyle(Color(.label))
                        Text(notice.license)
                    }
                    .textCase(nil)
                }
            }
        }
    }
}

/// One entry in `THIRD-PARTY-NOTICES.md`: its `## ` heading, its
/// `- License:` line, and the licence text in its code block, as paragraphs
/// that wrap on the page. An entry without a text (a credit) has the
/// lines under its heading instead.
nonisolated struct ThirdPartyNotice: Identifiable, Equatable, Sendable {
    var name: String
    var license: String
    var paragraphs: [String]

    var id: String { name }

    static func bundled(_ bundle: Bundle = .main) -> [ThirdPartyNotice] {
        guard let url = bundle.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return parse(text)
    }

    static func parse(_ markdown: String) -> [ThirdPartyNotice] {
        var notices: [ThirdPartyNotice] = []
        var name: String?
        var license = ""
        var notes: [String] = []
        var text: [String]?
        var inCode = false

        func finish() {
            guard let name else { return }
            let body = text.map(paragraphs(of:)) ?? notes
            notices.append(ThirdPartyNotice(name: name, license: license, paragraphs: body))
        }

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                inCode.toggle()
                if inCode, name != nil { text = text ?? [] }
                continue
            }
            if inCode {
                text?.append(line)
            } else if line.hasPrefix("## ") {
                finish()
                name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                license = ""
                notes = []
                text = nil
            } else if name != nil, line.hasPrefix("- License: ") {
                license = String(line.dropFirst("- License: ".count))
            } else if name != nil, line.hasPrefix("- "), !line.hasPrefix("- Source:"), !line.hasPrefix("- Location:") {
                notes.append(String(line.dropFirst(2)))
            }
        }
        finish()
        return notices
    }

    /// Lines broken at 80 columns, joined back into paragraphs.
    private static func paragraphs(of lines: [String]) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
                current = []
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        return paragraphs
    }
}
