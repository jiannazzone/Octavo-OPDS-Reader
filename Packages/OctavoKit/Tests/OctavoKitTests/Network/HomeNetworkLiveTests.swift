import Foundation
@testable import OctavoKit
import Testing

/// #9's question, measured with this Mac's real resolver (step 16): is a
/// server home by its name alone? Skipped unless `OCTAVO_LIVE_DNS=1`:
///
///     OCTAVO_LIVE_DNS=1 swift test --filter HomeNetworkLiveTests
///
/// Needs the internet's DNS (for `uz`, `tk` and `cm`, top-level domains
/// with addresses of their own) and Bonjour: the suite registers `.local`
/// names with `dns-sd -P`, as a hostile device on the Wi-Fi could. With
/// `OCTAVO_LIVE_DNS_PORT=3300` it also loads the local BookOrbit by this
/// Mac's `.local` name, through the transport and its connection check.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["OCTAVO_LIVE_DNS"] == "1", "Set OCTAVO_LIVE_DNS=1"))
struct HomeNetworkLiveTests {
    static let probes = [
        ("octavo-probe-public.local", "203.0.113.7"),
        ("octavo-probe-v6.local", "2001:db8::7"),
        ("octavo-probe-home.local", "192.168.1.250"),
    ]

    let policy = HomeNetworkPolicy.system

    /// `URLError(.cannotFindHost)` if the name doesn't resolve, else the
    /// refusal or `nil`.
    private func outcome(_ string: String) async -> (any Error)? {
        do {
            try await policy.check(URL(string: string)!)
            return nil
        } catch {
            return error
        }
    }

    /// Single labels pass ATS's local-networking rule, and the policy's name
    /// rule, whatever they resolve to. These three resolve to the internet.
    @Test func topLevelDomainsWithAddressesAreRefused() async throws {
        var resolved = 0
        for name in ["uz", "tk", "cm"] {
            guard let addresses = try? await SystemHostResolver().addresses(of: name) else { continue }
            resolved += 1
            let error = await outcome("http://\(name)/")
            guard case NetworkTrustError.insecureAddress(host: name, reason: .internetAddress(let address))? = error else {
                Issue.record("\(name) → \(addresses): \(String(describing: error))")
                continue
            }
            #expect(addresses.map(\.description).contains(address))
        }
        try #require(resolved > 0, "None of uz, tk, cm resolved: no internet DNS?")
    }

    /// A `.local` name answered over mDNS with an internet address is
    /// refused; with a home address it passes.
    @Test func mDNSAnswersAreChecked() async throws {
        let registrations = try Self.probes.map { name, address in
            try Self.register(name, address)
        }
        defer { registrations.forEach { $0.terminate() } }
        for (name, _) in Self.probes {
            try await Self.waitUntilResolves(name)
        }

        #expect(await outcome("http://octavo-probe-public.local:3300/") as? NetworkTrustError
            == .insecureAddress(host: "octavo-probe-public.local", reason: .internetAddress("203.0.113.7")))
        #expect(await outcome("http://octavo-probe-v6.local:3300/") as? NetworkTrustError
            == .insecureAddress(host: "octavo-probe-v6.local", reason: .internetAddress("2001:db8::7")))
        #expect(await outcome("http://octavo-probe-home.local:3300/") == nil)
    }

    /// This Mac's own `.local` name: on an IPv6 home it also has a global
    /// address, which counts as home only because it's on this network.
    @Test func thisMacsLocalNamePasses() async throws {
        let name = try Self.localHostName() + ".local"
        let addresses = try await SystemHostResolver().addresses(of: name)
        let networks = LocalNetworks.current()
        for address in addresses where address.isGlobalUnicastIPv6 {
            #expect(networks.ipv6Prefixes.contains { $0.contains(address) }, "\(address) isn't on this network")
        }
        #expect(await outcome("http://\(name):3300/") == nil)

        guard let port = ProcessInfo.processInfo.environment["OCTAVO_LIVE_DNS_PORT"] else { return }
        let url = try #require(URL(string: "http://\(name):\(port)/"))
        let (_, response) = try await ServerTransport(server: url).data(for: URLRequest(url: url))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    // MARK: Helpers

    /// `dns-sd -P` registers `host` → `address` over Bonjour while it runs.
    private static func register(_ host: String, _ address: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/dns-sd")
        process.arguments = ["-P", "Octavo probe \(host)", "_octavoprobe._tcp", "local", "3300", host, address]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private static func waitUntilResolves(_ host: String) async throws {
        for _ in 0..<50 {
            if let addresses = try? await SystemHostResolver().addresses(of: host), !addresses.isEmpty { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("\(host) never resolved")
    }

    private static func localHostName() throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/sbin/scutil")
        process.arguments = ["--get", "LocalHostName"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
