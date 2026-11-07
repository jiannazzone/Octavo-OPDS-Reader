#if DEBUG
import Foundation
import OctavoKit
import SwiftUI
import WebKit

/// DEBUG ONLY. Lets a script on the host drive the app's reader, so the
/// fold, position and format checks in `docs/notes/` don't depend on taps.
/// It replaced the spike's screens (`SpikeRemote`) in #17 and keeps their
/// file names and commands, so those tools run unchanged.
///
/// The script writes `Documents/spike-command.json`, e.g.
/// `{"id": 7, "cmd": "goto", "fraction": 0.5}`. The app polls for it, deletes
/// it, runs it, and writes `{"id": 7, "ok": true}` to `spike-ack.json`.
///
/// Commands:
/// - `signin`: connects the local BookOrbit (`LibraryModel.connectLocalBookOrbit`,
///   one login).
/// - `open` (`fileID`): opens that BookOrbit file in the reader through the
///   shell (download, Continue reading), with BookOrbit progress sync.
/// - `openLocal` (`name` of a book in Documents, or `fileID` like `open`).
/// - `detail` (`fileID`): the book's cover page in the Library tab, for the
///   unfold handoff.
/// - `close`, `home`: closes the reader; `home` also closes the tabs' screens.
/// - `goto` (`fraction` or `cfi`), `next`, `prev`.
/// - `turn` (`side`: left or right): a tap's page turn, as the bridge asks.
/// - `swipe` (`phase`: began, changed, ended or cancelled; `side`, `dx`,
///   `velocity`): a finger's page turn, as `ReaderSwipeRecognizer` reports
///   it, to hold a turn part way and look at it.
/// - `turnState`: what the turn under way is doing, in the ack's message.
/// - `pageTurn` (`name`): sets Page Turn, as Customize does.
/// - `tour` (`name`: `state`, in the ack's message, or `show`, as Settings'
///   Show the tour does). `signin`, `open`, `openLocal`, `detail` and `home`
///   end a tour under way, for scripts that check something else.
/// - `keyboard` (`on`: true or false): shows or hides the keyboard over the
///   reader, through a hidden text field, to check that it never moves the
///   page (the panels in #18 bring up a real one).
/// - `shape` (`point` or `range`, for the next open), `layout` (a
///   `ReaderLayout` to try until the next fold), `watch` (`cfi`: the state
///   file then says whether the visible page contains it), `js` (`script`: a
///   function body run in the reader page; its result goes to
///   `spike-js.json`).
/// - `back`: what the reader's Back button does.
/// - `closeAfter` (ms, with any command): closes the reader that long after
///   the command, without waiting for what it started.
/// - `liveReaders`: of the readers opened since launch, how many models, web
///   pages and web views are still alive, and their content processes, in
///   the ack's message (`docs/notes/reader-release.md`).
///
/// Where the reader is goes to `spike-state.json` after every move;
/// hinge, region and scene events go to `spike-events.jsonl` (`DebugEvents`).
enum ReaderRemote {
    struct Command: Decodable {
        var id: Int
        var cmd: String
        var fileID: Int?
        var fraction: Double?
        var cfi: String?
        var shape: String?
        var name: String?
        var layout: ReaderLayout?
        var script: String?
        var on: Bool?
        var phase: String?
        var side: String?
        var dx: Double?
        var velocity: Double?
        var closeAfter: Int?
    }

    struct Ack: Encodable {
        var id: Int
        var ok: Bool
        var message: String?
    }

    /// The open reader, set by `ReaderView`.
    static weak var reader: ReaderModel?
    /// A CFI the state file checks the visible page against.
    static var watchedCFI: String?
    /// Every reader opened since launch, without keeping any of them.
    private static var opened: [OpenedReader] = []
    /// The CFI shape the next reader saves and syncs.
    static var cfiShape = ReaderMessage.CFIShape.point

    private final class OpenedReader {
        weak var model: ReaderModel?
        weak var page: WebPage?
        weak var webView: WKWebView?

        init(_ model: ReaderModel) {
            self.model = model
            page = model.page
        }
    }

    static func track(_ model: ReaderModel) {
        guard !opened.contains(where: { $0.model === model }) else { return }
        opened.append(OpenedReader(model))
    }

    private static var liveReaders: String {
        for reader in opened where reader.webView == nil {
            reader.webView = reader.model?.snapshots.webView
        }
        // `_webProcessIdentifier` is WebKit's own, for its tests.
        let processes = opened.compactMap { $0.webView?.value(forKey: "_webProcessIdentifier") as? Int }
        let live = LiveReaders(
            opened: opened.count,
            models: opened.count { $0.model != nil },
            pages: opened.count { $0.page != nil },
            webViews: opened.count { $0.webView != nil },
            processes: processes,
            // For `leaks --traceTree=<address> <pid>`.
            addresses: opened.compactMap { $0.model.map { "\(Unmanaged.passUnretained($0).toOpaque())" } }
        )
        return (try? JSONEncoder().encode(live)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private struct LiveReaders: Encodable {
        var opened: Int
        var models: Int
        var pages: Int
        var webViews: Int
        var processes: [Int]
        var addresses: [String]
    }

    static let commandURL = URL.documentsDirectory.appending(path: "spike-command.json")
    static let ackURL = URL.documentsDirectory.appending(path: "spike-ack.json")
    static let scriptResultURL = URL.documentsDirectory.appending(path: "spike-js.json")
    static let keyboardNotification = Notification.Name("ReaderRemote.keyboard")
    static let backNotification = Notification.Name("ReaderRemote.back")

    /// Runs commands until the task is cancelled.
    static func run(shell: ShellModel) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            guard let data = try? Data(contentsOf: commandURL) else { continue }
            try? FileManager.default.removeItem(at: commandURL)
            guard let command = try? JSONDecoder().decode(Command.self, from: data) else { continue }
            let failure = await handle(command, shell: shell)
            if let closeAfter = command.closeAfter {
                try? await Task.sleep(for: .milliseconds(closeAfter))
                shell.closeReader()
            }
            let ack = Ack(id: command.id, ok: failure == nil, message: failure)
            try? JSONEncoder().encode(ack).write(to: ackURL, options: .atomic)
        }
    }

    /// Returns an error message, or `nil` on success.
    private static func handle(_ command: Command, shell: ShellModel) async -> String? {
        if ["signin", "open", "openLocal", "detail", "home"].contains(command.cmd) { shell.debugEndTour() }
        switch command.cmd {
        case "liveReaders":
            return liveReaders
        case "back":
            NotificationCenter.default.post(name: backNotification, object: nil)
            return nil
        case "tour":
            if command.name == "show" { shell.showTour() }
            return shell.debugTourState
        case "signin":
            await shell.library.connectLocalBookOrbit()
            if case .failed(let message) = shell.library.debugConnection { return message }
            return nil
        case "open":
            return await openBookOrbit(command.fileID, shell: shell, cover: false)
        case "openLocal":
            if command.fileID != nil { return await openBookOrbit(command.fileID, shell: shell, cover: false) }
            return openLocal(command.name, shell: shell)
        case "detail":
            return await openBookOrbit(command.fileID, shell: shell, cover: true)
        case "close":
            shell.closeReader()
            return nil
        case "home":
            shell.closeReader()
            for tab in ShellTab.allCases { shell[path: tab].replace([]) }
            return nil
        case "shape":
            guard let shape = command.shape.flatMap(ReaderMessage.CFIShape.init(rawValue:)) else { return "shape is point or range" }
            cfiShape = shape
            return nil
        case "js":
            guard let script = command.script else { return "js needs script" }
            return await runScript(script)
        case "offline":
            DebugProgressSync.offline = command.on ?? true
            return nil
        case "connectionReturned":
            shell.connection.connectionReturned()
            return nil
        case "coverMotion":
            guard let motion = shell.coverMotion else { return "no cover motion" }
            return motion.debugState
        case "spread":
            return "lastSpread \(shell.lastSpread.map { "\($0.width) pages \($0.pages.map { "\($0)" } ?? "nil")" } ?? "nil") twoPages \(shell.isTwoPages(in: shell.tab)) tabs \(shell.spreads.map { "\($0.key) \($0.value.isTwoPages)" }.sorted())"
        case "coverSpots":
            let home = shell.coverSpots.home
            return "home book \(home.book?.book.title ?? "nil") cover \(home.cover.map { "\($0)" } ?? "nil") page \(home.page.map { "\($0)" } ?? "nil") strip \(home.stripTop.map { "\($0)" } ?? "nil") spot \(home.spot != nil) books \(shell.coverSpots.bookScreens.map { "\($0.key.book.rawValue) \($0.value)" }.sorted())"
        case "turnProbe":
            guard let reader else { return "no open reader" }
            return await TurnProbe.run(reader)
        case "pageTurn":
            guard let style = command.name.flatMap(ReaderPageTurn.init(rawValue:)) else { return "pageTurn needs name: automatic, slide, flip, fade or none" }
            UserDefaults.standard.set(style.rawValue, forKey: ReaderPageTurn.key)
            return nil
        case "keyboard":
            guard reader != nil else { return "no open reader" }
            NotificationCenter.default.post(name: keyboardNotification, object: nil, userInfo: ["on": command.on ?? true])
            return nil
        default:
            return handleReaderCommand(command)
        }
    }

    /// A book in the app's Documents folder, opened straight in the reader.
    private static func openLocal(_ name: String?, shell: ShellModel) -> String? {
        guard let name, !name.contains("/") else { return "openLocal needs the name of a book in Documents" }
        let url = URL.documentsDirectory.appending(path: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return "no local book named \(name)" }
        let file = LibraryFile(id: LibraryFileID(rawValue: name), format: url.pathExtension.lowercased(), filename: name, isPrimary: true)
        let book = LibraryBook(id: LibraryBookID(rawValue: name), title: name, files: [file])
        shell.reading = nil
        shell.reading = OpenedBook(book: book, source: .files, file: file, url: url)
        return nil
    }

    /// A file on the local BookOrbit: in the reader, or its cover page. Its
    /// place syncs as any BookOrbit book's does (`ShellModel.progressSync`).
    private static func openBookOrbit(_ fileID: Int?, shell: ShellModel, cover: Bool) async -> String? {
        guard let fileID else { return "needs fileID" }
        guard let server = shell.library.server, let source = server.source as? BookOrbitSource else {
            return "not connected to BookOrbit; send signin first"
        }
        let id = LibraryFileID(rawValue: String(fileID))
        guard var book = await findBook(withFile: id, in: source), let file = book.files.first(where: { $0.id == id }) else {
            return "no book with file \(fileID)"
        }
        // The reader opens the book's readable file; keep only this one.
        book.files = [file]
        let sourced = SourcedBook(source: server.id, book: book)
        shell.reading = nil
        if cover {
            shell.select(.library)
            shell[path: .library].replace([.cover(sourced)])
        } else {
            shell.openBook(sourced)
        }
        return nil
    }

    private static func findBook(withFile id: LibraryFileID, in source: BookOrbitSource) async -> LibraryBook? {
        guard let all = try? await source.root().chips.first?.link else { return nil }
        var link: LibraryLink? = all
        while let next = link, let feed = try? await source.feed(next) {
            if let book = feed.books.first(where: { $0.files.contains { $0.id == id } }) { return book }
            link = feed.next
        }
        return nil
    }

    /// Runs `script` in the reader page and writes what it returns.
    private static func runScript(_ script: String) async -> String? {
        guard let reader else { return "no open reader" }
        let output: Any
        do {
            output = ["result": try await reader.page.callJavaScript(script) ?? NSNull()]
        } catch {
            output = ["error": String(describing: error)]
        }
        let data = (try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]))
            ?? Data(String(describing: output).utf8)
        try? data.write(to: scriptResultURL, options: .atomic)
        return nil
    }

    private static func handleReaderCommand(_ command: Command) -> String? {
        guard let reader else { return "no open reader" }
        switch command.cmd {
        case "controls":
            reader.onControlsTap?("toggle")
        case "jump":
            guard let fraction = command.fraction else { return "jump needs fraction" }
            reader.jump(toFraction: fraction)
        case "goto":
            if let fraction = command.fraction {
                reader.goTo(fraction: fraction)
            } else if let cfi = command.cfi {
                reader.goTo(cfi: cfi)
            } else {
                return "goto needs fraction or cfi"
            }
        case "layout":
            guard let layout = command.layout else { return "layout needs a layout" }
            reader.override(layout)
        case "watch":
            watchedCFI = command.cfi
        case "turn":
            guard let side = command.side.flatMap(ReaderTurnSide.init(rawValue:)) else { return "turn needs side" }
            reader.handle(.turn(side: side))
        case "swipe":
            guard let phase = command.phase.flatMap(ReaderTurnSwipe.Phase.init(rawValue:)) else { return "swipe needs phase" }
            let side = command.side.flatMap(ReaderTurnSide.init(rawValue:))
            reader.swiped(.init(phase: phase, side: side, dx: command.dx ?? 0, velocity: command.velocity ?? 0))
        case "turnState":
            let motion = reader.pageTurn.motion(spread: reader.layout.columns == 2, reduceMotion: reader.reduceMotion)
            let setting = "page turn \(reader.pageTurn.rawValue), reduce motion \(reader.reduceMotion) → \(motion.rawValue)"
            guard let run = reader.turnRun else { return "\(setting); idle, last drawn after \(reader.lastTurnDrawnAfter ?? -1) ms, queued \(reader.queuedTurns.count), overlay \(reader.turn != nil); \(reader.swipes.debugState)" }
            return "run \(run.id) \(run.side) \(run.motion) interactive \(run.interactive) moved \(String(describing: run.moved)) drawn \(run.drawn) target \(String(describing: run.target)) done \(run.animationDone) progress \(reader.turn?.progress ?? -1)"
        case "noteState":
            return reader.note.map { "open \($0.href), mark at \($0.mark.y), size \($0.font.size), line \($0.font.lineHeight ?? -1), \($0.font.family ?? "no family"), \($0.blocks.count) blocks" } ?? "no note; last error \(reader.lastError ?? "none")"
        case "next": reader.next()
        case "prev": reader.previous()
        default: return "unknown command \(command.cmd)"
        }
        return nil
    }
}

extension View {
    /// DEBUG ONLY. Hands `model` to `ReaderRemote`, writes the state file on
    /// every move, and logs the reader's hinge and region events.
    func readerRemote(_ model: ReaderModel, back: @escaping () -> Void) -> some View {
        modifier(ReaderRemoteHook(model: model, back: back))
    }
}

private struct ReaderRemoteHook: ViewModifier {
    let model: ReaderModel
    let back: () -> Void
    @State private var text = ""
    @FocusState private var keyboard: Bool

    func body(content: Content) -> some View {
        content
            // For the `keyboard` command: a field nobody sees, focused to
            // bring the keyboard up.
            .background {
                TextField("", text: $text)
                    .focused($keyboard)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: ReaderRemote.keyboardNotification)) { note in
                keyboard = note.userInfo?["on"] as? Bool ?? false
            }
            .onReceive(NotificationCenter.default.publisher(for: ReaderRemote.backNotification)) { _ in back() }
            .task {
                ReaderRemote.reader = model
                ReaderRemote.track(model)
            }
            .task(id: ReaderStateFile.Key(model)) {
                await ReaderStateFile.write(model)
            }
            .debugProbe("reader")
    }
}

/// DEBUG ONLY. Where the reader is, for scripts on the host:
/// `Documents/spike-state.json`.
enum ReaderStateFile {
    struct State: Encodable {
        var bookID: String
        var title: String?
        var cfi: String?
        var rangeCFI: String?
        var startCFI: String?
        var blankPage: Bool?
        var reason: String?
        var fraction: Double?
        var tocLabel: String?
        var location: ReaderMessage.Relocation.Location?
        var visibleText: String?
        var restoredFrom: String?
        var openedFrom: String?
        var syncStatus: String?
        var lastPushedCFI: String?
        var relocations: Int
        var posture: ReaderPosture
        var hingeAngle: Double?
        var isBookMode: Bool
        var tapColumnStart: Double?
        var margins: ReaderMargins
        var geometry: ReaderGeometry?
        var layout: ReaderLayout
        var layoutReport: DebugJSON?
        var watched: DebugJSON?
        var lastFold: ReaderModel.FoldReport?
        var updatedAt: Date
    }

    /// Rewritten on every relocation (a fold re-lays out the page without
    /// moving the position) and every layout change.
    struct Key: Equatable {
        var phase: ReaderModel.Phase
        var relocations: Int
        var layout: ReaderLayout
        var posture: ReaderPosture
        var hingeAngle: Double?
        var isBookMode: Bool
        var geometry: ReaderGeometry?

        init(_ model: ReaderModel) {
            phase = model.phase
            relocations = model.relocationCount
            layout = model.layout
            posture = model.posture
            hingeAngle = model.hingeAngle
            isBookMode = model.isBookMode
            geometry = model.geometry
        }
    }

    static let url = URL.documentsDirectory.appending(path: "spike-state.json")

    static func write(_ model: ReaderModel) async {
        guard model.phase == .open else { return }
        // Let the page settle so the text matches the final relocation.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        let state = State(
            bookID: model.book.id,
            title: model.title,
            cfi: model.position?.cfi,
            rangeCFI: model.relocation?.cfi,
            startCFI: model.relocation?.startCFI,
            blankPage: model.relocation?.blankPage,
            reason: model.relocation?.reason,
            fraction: model.position?.fraction,
            tocLabel: model.tocLabel,
            location: model.location,
            visibleText: await model.visibleText(limit: 4000),
            restoredFrom: model.restoredFrom,
            openedFrom: model.openingPosition?.label,
            syncStatus: model.syncStatus,
            lastPushedCFI: model.lastPushedCFI,
            relocations: model.relocationCount,
            posture: model.posture,
            hingeAngle: model.hingeAngle,
            isBookMode: model.isBookMode,
            margins: model.margins,
            geometry: model.geometry,
            layout: model.layout,
            layoutReport: await model.layoutReport().map(DebugJSON.init),
            watched: await watched(model),
            lastFold: model.lastFold,
            updatedAt: .now
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(state).write(to: url, options: .atomic)
    }

    private static func watched(_ model: ReaderModel) async -> DebugJSON? {
        guard let cfi = ReaderRemote.watchedCFI else { return nil }
        var result = await model.locate(cfi) ?? [:]
        result["cfi"] = cfi
        return DebugJSON(result)
    }
}

/// DEBUG ONLY. Re-encodes a dictionary that came back from JavaScript.
struct DebugJSON: Encodable {
    let object: Any

    init(_ object: Any) { self.object = object }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch object {
        case let value as NSNumber where CFGetTypeID(value) == CFBooleanGetTypeID(): try container.encode(value.boolValue)
        case let value as Int: try container.encode(value)
        case let value as Double: try container.encode(value)
        case let value as String: try container.encode(value)
        case let value as [Any]: try container.encode(value.map(DebugJSON.init))
        case let value as [String: Any]: try container.encode(value.mapValues(DebugJSON.init))
        default: try container.encodeNil()
        }
    }
}
#endif
