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

    @Test func emptyFieldsAskBeforeTryingTheServer() async {
        let setup = SetupModel()
        await setup.signInToBookOrbit()
        #expect(setup.error == "Enter your server’s address.")
        setup.bookOrbitAddress = "localhost:3300"
        await setup.signInToBookOrbit()
        #expect(setup.error == "Enter your username and password.")
        setup.bookOrbitAddress = "ftp://localhost"
        await setup.signInToBookOrbit()
        #expect(setup.error == "Use an address that starts with https:// or http://.")
    }
}
