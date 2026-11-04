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
@Suite(.temporaryFiles)
struct SavedServerTests {
    private static func temporaryStore() -> ServerStore {
        ServerStore(fileURL: URL.testDirectory.appending(path: "Server-\(UUID().uuidString).json"))
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

    // Setup doesn't offer "Don't sync" for now (Adam, 2026-11-02), so a
    // server an earlier setup saved without sync syncs anyway.
    @Test func everyBookOrbitServerSyncsWhileTheChoiceIsntOffered() {
        #expect(!SavedServer.offersSyncChoice)
        let server = SavedServer(id: SavedServer.newID(), kind: .bookOrbit, address: "https://books.example.com", name: "BookOrbit")
        #expect(!server.syncsProgress)
        #expect(server.progressSyncs)
    }

    /// Step 16: no file is "no server"; a file that can't be read throws,
    /// so the launch sweep never takes it for none. A file saved before
    /// `signedOut` existed still reads.
    @Test func tellsNoServerFromOneThatCantBeRead() throws {
        let store = Self.temporaryStore()
        #expect(try store.read() == nil)
        try Data("{ not json".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.read() }
        #expect(store.load() == nil)

        let older = #"{"id":"server-1","kind":"opds","address":"http://nas.lan/opds","name":"COPS","syncsProgress":false}"#
        try Data(older.utf8).write(to: store.fileURL)
        #expect(try store.read()?.signedOut == nil)
        #expect(try store.read()?.name == "COPS")
    }

    /// Other secrets in a catalog's address are saved as placeholders, and
    /// the address still shows its host.
    @Test func otherSecretsInTheAddressAreSavedAsPlaceholders() throws {
        let id = SavedServer.newID()
        let address = "https://nas.lan/opds/{key}/v1.2/catalog?token={key2}"
        let stump = SavedServer(id: id, kind: .opds, address: address, name: "Stump")
        #expect(stump.detail == "nas.lan")
        #expect(stump.libraryServer() == nil, "no secrets in the Keychain")

        let typed = try #require(URL(string: "https://nas.lan/opds/stump_0123456789/v1.2/catalog?token=abcdefgh1234"))
        let secret = try #require(OPDSURLSecret.detect(in: typed))
        #expect(secret.redact(typed.absoluteString) == address)
        try KeychainCatalogSecretStore(serverID: id.rawValue).save(secret)
        defer { try? ServerCredentials.removeAll(serverID: id.rawValue) }
        #expect(stump.libraryServer()?.name == "Stump")
    }

    /// A server saved before step 16 has its address's other secrets moved
    /// to the Keychain at launch, next to a key already there; once done,
    /// it's left alone.
    @Test func movesOlderSavedSecretsOut() throws {
        let store = Self.temporaryStore()
        let id = SavedServer.newID()
        defer { try? ServerCredentials.removeAll(serverID: id.rawValue) }
        let secrets = KeychainCatalogSecretStore(serverID: id.rawValue)
        try secrets.save(OPDSURLSecret("kavita0123456789"))
        try store.save(SavedServer(id: id, kind: .opds, address: "http://nas.lan/api/opds/{key}?token=abcdefgh1234", name: "Kavita"))

        try store.moveSecretsOut()
        #expect(store.load()?.address == "http://nas.lan/api/opds/{key}?token={key2}")
        #expect(try secrets.load()?.values == ["kavita0123456789", "abcdefgh1234"])
        try store.moveSecretsOut()
        #expect(store.load()?.address == "http://nas.lan/api/opds/{key}?token={key2}")

        let bookOrbit = SavedServer(id: SavedServer.newID(), kind: .bookOrbit, address: "https://books.example.com?token=abcdefgh", name: "BookOrbit")
        try store.save(bookOrbit)
        try store.moveSecretsOut()
        #expect(store.load()?.address == "https://books.example.com")
    }

    /// A crash or a failed save after the Keychain: the next launch still
    /// takes the key out of the saved address.
    @Test func finishesMovingAKeyAlreadyInTheKeychain() throws {
        let store = Self.temporaryStore()
        let id = SavedServer.newID()
        defer { try? ServerCredentials.removeAll(serverID: id.rawValue) }
        let secrets = KeychainCatalogSecretStore(serverID: id.rawValue)
        try secrets.save(OPDSURLSecret("abcdefgh12345678"))
        try store.save(SavedServer(id: id, kind: .opds, address: "http://nas.lan/feed?apikey=abcdefgh12345678", name: "COPS"))

        try store.moveSecretsOut()
        #expect(store.load()?.address == "http://nas.lan/feed?apikey={key}")
        #expect(try secrets.load()?.values == ["abcdefgh12345678"])
    }

    /// BookOrbit's address is its root: a query typed with it goes.
    @Test func aBookOrbitAddressDropsItsQuery() throws {
        #expect(URL(string: "https://books.example.com/?token=abcdefgh")!.withoutQuery.absoluteString == "https://books.example.com/")
        #expect(URL(string: "http://nas.lan:3300")!.withoutQuery.absoluteString == "http://nas.lan:3300")
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
@Suite(.temporaryFiles)
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
