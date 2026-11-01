import Foundation
@testable import OctavoKit
import Synchronization
import Testing

/// DNS answers set by the test; unknown names don't resolve.
final class FakeResolver: HostResolver {
    private let answers: Mutex<[String: [String]]>
    private let log = Mutex<[String]>([])

    init(_ answers: [String: [String]] = [:]) {
        self.answers = Mutex(answers)
    }

    func set(_ host: String, _ addresses: [String]) {
        answers.withLock { $0[host] = addresses }
    }

    var lookups: [String] { log.withLock { $0 } }

    func addresses(of host: String) async throws -> [IPAddress] {
        log.withLock { $0.append(host) }
        guard let literals = answers.withLock({ $0[host] }) else { throw URLError(.cannotFindHost) }
        return literals.map { IPAddress(literal: $0)! }
    }
}

extension HomeNetworkPolicy {
    /// The developer's home Wi-Fi (a global IPv6 /64), with Tailscale up
    /// unless `tunnel` is false.
    /// `verifiesConnections` is off by default: stub `URLProtocol`s have no
    /// addresses, so plain http to them would fail closed.
    static func testing(_ resolver: FakeResolver, networks: [String] = ["2603:7001:f100:669::1/64"],
                        tunnel: Bool = true, proxy: Bool = false, verifiesConnections: Bool = false) -> HomeNetworkPolicy {
        let prefixes = networks.map { entry in
            let parts = entry.split(separator: "/")
            return NetworkPrefix(address: IPAddress(literal: String(parts[0]))!, length: Int(parts[1])!)
        }
        return HomeNetworkPolicy(
            resolver: resolver,
            localNetworks: { LocalNetworks(ipv6Prefixes: prefixes, hasSharedAddressTunnel: tunnel) },
            usesProxy: { _ in proxy },
            verifiesConnections: verifiesConnections
        )
    }
}

struct HomeNetworkPolicyTests {
    let resolver = FakeResolver([
        "nas.lan": ["192.168.1.5"],
        "nas": ["192.168.1.5"],
        "diskstation.local": ["192.168.1.5", "fe80::211:32ff:fe12:3456", "2603:7001:f100:669:211:32ff:fe12:3456"],
        "nas.tail1234.ts.net": ["100.101.102.103", "fd7a:115c:a1e0::1"],
        "funnel.tail1234.ts.net": ["203.0.113.9"],
        "mixed.lan": ["192.168.1.5", "203.0.113.9"],
        "hijacked.home.arpa": ["198.51.100.7"],
        "away.local": ["192.168.1.5", "2001:db8:1::5"],
        "nat64.lan": ["64:ff9b::c0a8:105"],
        "xn--bcher-kva.local": ["192.168.1.6"],
        "books.example.com": ["192.168.1.5"],
        "localhost": ["127.0.0.1", "::1"],
    ])

    var policy: HomeNetworkPolicy { .testing(resolver) }

    private func check(_ string: String) async throws {
        try await policy.check(try #require(URL(string: string)))
    }

    private func refusal(_ string: String) async -> NetworkTrustError? {
        do {
            try await check(string)
            return nil
        } catch let error as NetworkTrustError {
            return error
        } catch {
            Issue.record("Expected NetworkTrustError, got \(error)")
            return nil
        }
    }

    @Test(arguments: [
        "https://books.example.com/opds",
        "https://203.0.113.9/",
        "https://[2606:4700:4700::1111]/",
        "https://bücher.example/",    // sent as xn--bcher-kva.example
    ])
    func httpsPassesWithoutDNS(_ url: String) async throws {
        try await check(url)
        #expect(resolver.lookups.isEmpty)
    }

    @Test(arguments: [
        "http://192.168.1.122:3300/api/v1/health",
        "http://10.0.0.2/",
        "http://100.101.102.103:8080/",
        "http://[::1]:3300/",
        "http://[fe80::1%25en0]:3300/",
        "http://[::ffff:192.168.1.122]:3300/",
        "http://[fd7a:115c:a1e0::1]/",
    ])
    func homeAddressesPassWithoutDNS(_ url: String) async throws {
        try await check(url)
        #expect(resolver.lookups.isEmpty)
    }

    @Test(arguments: [
        "http://nas.lan/opds",
        "http://NAS.LAN/opds",
        "http://nas/opds",
        "http://localhost:3300/",
        "http://diskstation.local:5000/",     // its global IPv6 is on this network
        "http://nas.tail1234.ts.net/",
        "http://xn--bcher-kva.local/",
        "http://bücher.local/",               // URL sends it as xn--bcher-kva.local
        "http://nas.ｌａｎ/",                  // URL maps fullwidth letters to nas.lan
        "http://nas。lan/",                   // and the ideographic full stop
    ])
    func localNamesThatResolveHomePass(_ url: String) async throws {
        try await check(url)
        #expect(resolver.lookups.count == 1)
    }

    @Test func publicAddressesAreRefused() async {
        #expect(await refusal("http://1.1.1.1/") == .insecureAddress(host: "1.1.1.1", reason: .internetAddress("1.1.1.1")))
        #expect(await refusal("http://[2606:4700:4700::1111]/") == .insecureAddress(host: "2606:4700:4700::1111", reason: .internetAddress("2606:4700:4700::1111")))
        #expect(await refusal("http://[::ffff:1.1.1.1]/") == .insecureAddress(host: "::ffff:1.1.1.1", reason: .internetAddress("::ffff:1.1.1.1")))
        // A global IPv6 literal on this network still needs https: ATS
        // only lets the fixed ranges through.
        #expect(await refusal("http://[2603:7001:f100:669::5]/") != nil)
    }

    /// Spellings that hide an address: refused before any lookup, whichever
    /// address they mean.
    @Test(arguments: [
        "http://16843009/",
        "http://3232235898:3300/",
        "http://0x7f000001:3300/",
        "http://0177.0.0.1:3300/",
        "http://0300.0250.1.0172:3300/",
        "http://192.168.001.122/",
        "http://127.1:3300/",
        "http://192.168.378/",
        "http://nas.0x1f/",
        "http://192.168.1.122./",
        "http://localhost.:3300/",
        "http://nas.lan./",
        "https://16843009/",              // odd spellings are refused for https too
        "https://0x7f000001/",
        "https://example.com./",
        "http://nas%2elan/",
        "http://octavo:secret@192.168.1.5/opds",   // credentials belong in the Keychain
        "https://octavo@books.example.com/",
        "http://-nas.lan/",
        "http://nas_1.lan/",
        "http://[2001:db8::1%25en0]/",
        "ftp://192.168.1.5/",
        "file:///etc/hosts",
    ])
    func hiddenOrOddAddressesAreRefused(_ url: String) async {
        let error = await refusal(url)
        guard case .unsupportedAddress = error else {
            Issue.record("\(url): \(String(describing: error))")
            return
        }
        #expect(resolver.lookups.isEmpty)
    }

    /// ATS blocks plain http to other names anyway; say why first.
    @Test func otherNamesNeedHTTPS() async {
        #expect(await refusal("http://books.example.com/") == .insecureAddress(host: "books.example.com", reason: .notALocalName))
        #expect(await refusal("http://nas.local.example.com/") == .insecureAddress(host: "nas.local.example.com", reason: .notALocalName))
        #expect(resolver.lookups.isEmpty)
    }

    /// Every address must be home: a name that resolves to home and public
    /// addresses could connect to either.
    @Test func mixedAnswersAreRefused() async {
        #expect(await refusal("http://mixed.lan/") == .insecureAddress(host: "mixed.lan", reason: .internetAddress("203.0.113.9")))
        #expect(await refusal("http://away.local/") == .insecureAddress(host: "away.local", reason: .internetAddress("2001:db8:1::5")))
    }

    /// An ISP that answers unknown names, or a VPN's DNS, can send a
    /// special-use name to the internet; the name alone isn't enough.
    @Test func specialNamesStillHaveToResolveHome() async {
        #expect(await refusal("http://hijacked.home.arpa/") == .insecureAddress(host: "hijacked.home.arpa", reason: .internetAddress("198.51.100.7")))
        #expect(await refusal("http://funnel.tail1234.ts.net/") == .insecureAddress(host: "funnel.tail1234.ts.net", reason: .internetAddress("203.0.113.9")))
        #expect(await refusal("http://nat64.lan/") == .insecureAddress(host: "nat64.lan", reason: .internetAddress("64:ff9b::c0a8:105")))
    }

    /// Away from home the same name's IPv6 address is no longer local.
    @Test func globalIPv6CountsOnlyOnItsOwnNetwork() async throws {
        let away = HomeNetworkPolicy.testing(resolver, networks: ["2001:db8:aaaa:1::1/64"])
        await #expect(throws: NetworkTrustError.insecureAddress(host: "diskstation.local", reason: .internetAddress("2603:7001:f100:669:211:32ff:fe12:3456"))) {
            try await away.check(URL(string: "http://diskstation.local/")!)
        }
        // A network wider than /48 doesn't count (LocalNetworks drops it; the
        // policy relies on that).
        #expect(LocalNetworks.current().ipv6Prefixes.allSatisfy { $0.length >= 48 && $0.address.isGlobalUnicastIPv6 })
    }

    /// Without Tailscale, 100.64.0.0/10 is the carrier's or ISP's space.
    @Test func sharedAddressSpaceNeedsTheTunnel() async {
        let noTunnel = HomeNetworkPolicy.testing(resolver, tunnel: false)
        await #expect(throws: NetworkTrustError.insecureAddress(host: "100.101.102.103", reason: .internetAddress("100.101.102.103"))) {
            try await noTunnel.check(URL(string: "http://100.101.102.103:8080/")!)
        }
        await #expect(throws: NetworkTrustError.insecureAddress(host: "nas.tail1234.ts.net", reason: .internetAddress("100.101.102.103"))) {
            try await noTunnel.check(URL(string: "http://nas.tail1234.ts.net/")!)
        }
        try? await noTunnel.check(URL(string: "http://[fd7a:115c:a1e0::1]/")!)   // ULA isn't routed by carriers
    }

    /// A proxy would resolve the name itself, wherever it runs.
    @Test func proxiesAreRefused() async {
        let proxied = HomeNetworkPolicy.testing(resolver, proxy: true)
        await #expect(throws: NetworkTrustError.insecureAddress(host: "192.168.1.5", reason: .throughProxy)) {
            try await proxied.check(URL(string: "http://192.168.1.5/")!)
        }
        await #expect(throws: NetworkTrustError.insecureAddress(host: "nas.lan", reason: .throughProxy)) {
            try await proxied.check(URL(string: "http://nas.lan/")!)
        }
        try? await proxied.check(URL(string: "https://books.example.com/")!)
    }

    @Test func localAddresses() {
        #expect(HomeNetworkPolicy.isLocalAddress(URL(string: "http://192.168.1.1/cgi-bin")!))
        #expect(HomeNetworkPolicy.isLocalAddress(URL(string: "https://router/")!))
        #expect(HomeNetworkPolicy.isLocalAddress(URL(string: "https://nas.local:5001/")!))
        #expect(HomeNetworkPolicy.isLocalAddress(URL(string: "http://[::1]/")!))
        #expect(HomeNetworkPolicy.isLocalAddress(URL(string: "https://0.0.0.0:8443/")!))   // the device itself
        #expect(HomeNetworkPolicy.isLocalAddress(URL(string: "https://[::]/")!))
        #expect(!HomeNetworkPolicy.isLocalAddress(URL(string: "https://books.example.com/")!))
        #expect(!HomeNetworkPolicy.isLocalAddress(URL(string: "https://8.8.8.8/")!))
    }

    /// After the fact, from the task's metrics: where the request really went.
    @Test func verifiesWhereItActuallyConnected() {
        let policy = HomeNetworkPolicy.testing(resolver, tunnel: false, verifiesConnections: true)
        let http = URL(string: "http://nas.lan/opds")!
        func verify(_ url: URL, _ remote: String?, proxy: Bool = false, internet: Bool = false) -> NetworkTrustError? {
            policy.verify(url, connectedTo: remote, throughProxy: proxy, fromInternetServer: internet)
        }
        #expect(verify(http, "192.168.1.5") == nil)
        #expect(verify(http, "fe80::1%en0") == nil)
        #expect(verify(http, "2603:7001:f100:669::5") == nil)   // on this network
        #expect(verify(http, nil) == .insecureAddress(host: "nas.lan", reason: .unverifiedConnection))   // fails closed
        #expect(verify(http, "not an address") == .insecureAddress(host: "nas.lan", reason: .unverifiedConnection))
        // DNS changed after the check: refuse the response.
        #expect(verify(http, "203.0.113.9") == .insecureAddress(host: "nas.lan", reason: .internetAddress("203.0.113.9")))
        #expect(verify(http, "100.101.102.103") == .insecureAddress(host: "nas.lan", reason: .internetAddress("100.101.102.103")))
        #expect(verify(http, "64:ff9b::c0a8:105") != nil)       // out through the carrier's NAT64
        #expect(verify(http, "192.168.1.5", proxy: true) == .insecureAddress(host: "nas.lan", reason: .throughProxy))

        let cover = URL(string: "https://rebind.example.com/cover.jpg")!
        #expect(verify(cover, "203.0.113.9", internet: true) == nil)
        #expect(verify(cover, "192.168.1.1", internet: true) == .insecureAddress(host: "rebind.example.com", reason: .localAddressFromInternetServer))
        #expect(verify(cover, "0.0.0.0", internet: true) != nil)
        #expect(verify(cover, "2603:7001:f100:669::7", internet: true) != nil)   // home IPv6 on this network
        #expect(verify(cover, nil, internet: true) == nil)                     // https: TLS decided
        #expect(verify(cover, "192.168.1.1", internet: false) == nil)
        #expect(verify(cover, "203.0.113.9", proxy: true) == nil)   // https through a proxy is still TLS to the server
    }

    @Test func unknownNamesCantBeReached() async {
        await #expect(throws: URLError(.cannotFindHost)) {
            try await check("http://missing.lan/")
        }
    }

    @Test func systemResolverReadsLocalhost() async throws {
        let addresses = try await SystemHostResolver().addresses(of: "localhost")
        #expect(addresses.contains(IPAddress(literal: "127.0.0.1")!))
        #expect(addresses.allSatisfy { $0.isHomeRange })
        try await HomeNetworkPolicy.system.check(URL(string: "http://localhost:3300/")!)
    }
}
