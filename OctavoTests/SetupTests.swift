import Foundation
import OctavoKit
import Testing
@testable import Octavo

struct ServerAddressTests {
    private func url(_ text: String) throws -> String {
        try ServerAddress.parse(text).url.absoluteString
    }

    @Test func aMissingSchemeIsHTTPAtHomeAndHTTPSElsewhere() throws {
        #expect(try url("books.example.com") == "https://books.example.com")
        #expect(try url("192.168.1.5:3300") == "http://192.168.1.5:3300")
        #expect(try url("localhost:3300") == "http://localhost:3300")
        #expect(try url("nas.local/opds") == "http://nas.local/opds")
        #expect(try url("100.101.102.103") == "http://100.101.102.103")
        #expect(try url("adam:pw@NAS.lan.") == "http://nas.lan")
    }

    @Test func theHostIsWrittenOneWay() throws {
        #expect(try url("  HTTPS://Books.Example.COM./opds/  ") == "https://books.example.com/opds")
        #expect(try url("https://bücher.example") == "https://xn--bcher-kva.example")
        #expect(try url("http://localhost:3340/api/opds/0123456789abcdef") == "http://localhost:3340/api/opds/0123456789abcdef")
        #expect(try url("https://books.example.com/opds#top") == "https://books.example.com/opds")
    }

    @Test func anAccountInTheAddressMovesToTheFields() throws {
        let parsed = try ServerAddress.parse("http://adam:pa%20ss@nas.lan:8080/opds")
        #expect(parsed.url.absoluteString == "http://nas.lan:8080/opds")
        #expect(parsed.username == "adam")
        #expect(parsed.password == "pa ss")
        #expect(parsed.isPlainHTTP)
    }

    @Test func whatIsntAnAddressSaysWhy() {
        #expect(throws: ServerAddress.Problem.empty) { try ServerAddress.parse("   ") }
        #expect(throws: ServerAddress.Problem.unsupportedScheme) { try ServerAddress.parse("ftp://books.example.com") }
        #expect(throws: ServerAddress.Problem.notAnAddress) { try ServerAddress.parse("https://") }
    }
}

@MainActor
struct SavedServerTests {
    private static func temporaryStore() -> ServerStore {
        ServerStore(fileURL: URL.temporaryDirectory.appending(path: "Server-\(UUID().uuidString).json"))
    }

    @Test func keepsTheServerBetweenLaunches() throws {
        let store = Self.temporaryStore()
        #expect(store.load() == nil)
        let server = SavedServer(
            id: SavedServer.newID(), kind: .opds, address: "http://nas.lan:8080/opds", name: "Calibre-Web",
            username: "adam", authScheme: .digest
        )
        try store.save(server)
        #expect(store.load() == server)
        try store.remove()
        #expect(store.load() == nil)
    }

    @Test func describesItselfByHostAndAccount() {
        let id = SavedServer.newID()
        #expect(SavedServer(id: id, kind: .bookOrbit, address: "https://books.example.com", name: "BookOrbit", username: "adam").detail
            == "books.example.com · adam")
        #expect(SavedServer(id: id, kind: .opds, address: "http://nas.lan:8080/opds", name: "COPS").detail == "nas.lan:8080")
        #expect(SavedServer(id: id, kind: .opds, address: "http://localhost:3340/api/opds/{key}", name: "Kavita").detail == "localhost:3340")
    }

    @Test func aCatalogWhoseKeyIsGoneStartsSetupAgain() throws {
        let id = SavedServer.newID()
        let kavita = SavedServer(id: id, kind: .opds, address: "http://localhost:3340/api/opds/{key}", name: "Kavita")
        #expect(kavita.libraryServer() == nil)

        let secrets = KeychainCatalogSecretStore(serverID: id.rawValue)
        try secrets.save(OPDSURLSecret("0123456789abcdef"))
        defer { try? ServerCredentials.removeAll(serverID: id.rawValue) }
        #expect(kavita.libraryServer()?.name == "Kavita")
    }
}

@MainActor
struct SetupFlowTests {
    @Test func withoutAServerSetupShowsAndOpensItsSteps() {
        let shell = makeShell()
        #expect(shell.needsSetup)
        shell.push(.setup(.opds))
        #expect(shell[path: .setup].routes == [.setup(.opds)])
        #expect(shell[path: .home].routes.isEmpty)
    }

    @Test func aFinishedSetupKeepsTheServerAndOpensHome() throws {
        let shell = makeShell()
        shell.select(.search)
        shell.push(.setup(.opds))
        let saved = SavedServer(id: SavedServer.newID(), kind: .opds, address: "http://localhost:3320/feed.php", name: "COPS")
        shell.setup.catalogAddress = "localhost:3320/feed.php"
        shell.setup.finished(saved)

        #expect(!shell.needsSetup)
        #expect(shell.library.server?.id == saved.id)
        #expect(shell.servers.load() == saved)
        #expect(shell.tab == .home)
        #expect(shell[path: .setup].routes.isEmpty)
        #expect(shell.setup.catalogAddress.isEmpty, "setup starts clean")
    }

    @Test func messagesSayWhatToDo() {
        let message = { (error: any Error) in SetupModel.message(for: error, server: "BookOrbit", host: "nas.lan") }
        #expect(message(BookOrbitError.http(status: 401, message: nil)) == "That username or password didn’t work.")
        #expect(message(NetworkTrustError.insecureAddress(host: "books.example.com", reason: .notALocalName)).hasPrefix("Use https://"))
        #expect(message(URLError(.cannotFindHost)) == "Can’t find nas.lan. Check the address.")
        #expect(message(URLError(.timedOut)).hasPrefix("Can’t reach nas.lan."))
        #expect(message(BookOrbitError.http(status: 404, message: nil)).hasPrefix("That doesn’t look like a BookOrbit server"))
    }

    @Test func emptyFieldsAskBeforeTryingTheServer() {
        let setup = SetupModel()
        setup.signInToBookOrbit()
        #expect(setup.error == "Enter your server’s address.")
        setup.bookOrbitAddress = "localhost:3300"
        setup.signInToBookOrbit()
        #expect(setup.error == "Enter your username and password.")
        setup.bookOrbitAddress = "ftp://localhost"
        setup.signInToBookOrbit()
        #expect(setup.error == "Use an address that starts with https:// or http://.")
        #expect(!setup.working)
    }

    /// `nas.lan@evil.com` is evil.com: the account moves to the fields and
    /// nothing goes out until the address is tried again.
    @Test func anAccountInTheAddressIsntSentOnTheSameTap() {
        let setup = SetupModel()
        setup.bookOrbitPassword = "typed"
        setup.bookOrbitAddress = "nas.lan@evil.example"
        setup.signInToBookOrbit()
        #expect(!setup.working)
        #expect(setup.bookOrbitAddress == "https://evil.example")
        #expect(setup.bookOrbitUsername == "nas.lan")
        #expect(setup.bookOrbitPassword == "typed")
        #expect(setup.error == SetupModel.accountMoved)
    }
}

@MainActor
struct AttemptTests {
    /// A server that never answers: the try gives up at the time limit, and
    /// its answer, if it ever comes, changes nothing.
    @Test func aServerThatDoesntAnswerTimesOut() async {
        let attempt = Attempt(timeLimit: .milliseconds(50))
        var outcome = "waiting"
        attempt.start { isCurrent in
            try? await Task.sleep(for: .milliseconds(300))
            if isCurrent() { outcome = "answered" }
        } timedOut: {
            outcome = "timed out"
        }
        #expect(attempt.running)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(outcome == "timed out")
        #expect(!attempt.running)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(outcome == "timed out", "the late answer goes nowhere")
    }

    @Test func aNewTryReplacesTheOneRunning() async {
        let attempt = Attempt(timeLimit: .seconds(5))
        var answers: [String] = []
        attempt.start { isCurrent in
            try? await Task.sleep(for: .milliseconds(100))
            if isCurrent() { answers.append("first") }
        } timedOut: {}
        attempt.start { isCurrent in
            if isCurrent() { answers.append("second") }
        } timedOut: {}
        await attempt.wait()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(answers == ["second"])
        #expect(!attempt.running)
    }

    @Test func typingStopsTheTry() {
        let setup = SetupModel()
        setup.bookOrbitAddress = "nas.local"
        setup.bookOrbitUsername = "adam"
        setup.bookOrbitPassword = "secret"
        setup.signInToBookOrbit()
        #expect(setup.working)
        setup.bookOrbitAddress = "nas.local:3300"
        #expect(!setup.working)
        #expect(setup.error == nil)
    }
}

struct AuthorAvatarTests {
    @Test func initialsAreTheFirstAndLastNames() {
        #expect(AuthorAvatar.initials("Jane Austen") == "JA")
        #expect(AuthorAvatar.initials("H. G. Wells") == "HW")
        #expect(AuthorAvatar.initials("Arthur Conan Doyle") == "AD")
        #expect(AuthorAvatar.initials("Plato") == "P")
        #expect(AuthorAvatar.initials("  ") == "")
    }

    @Test func aNameKeepsItsTint() {
        #expect(AuthorAvatar.tint(for: "Jane Austen") == AuthorAvatar.tint(for: "Jane Austen"))
    }
}
