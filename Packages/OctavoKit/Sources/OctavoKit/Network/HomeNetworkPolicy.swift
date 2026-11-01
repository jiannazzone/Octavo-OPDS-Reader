import CFNetwork
import Foundation

/// Decides whether a URL may be loaded (D25). `ServerTransport` asks before
/// every request and every redirect, so a saved http server that now resolves
/// to the internet is refused before a password or token goes out unencrypted.
///
/// Every URL, http or https:
/// - **http or https only, no `user:password@`** (credentials belong in the
///   Keychain, not in addresses that get saved and logged).
/// - **The host written the standard way:** lowercase letters, digits and
///   hyphens without a trailing dot (an internationalized name in its `xn--`
///   form, which `URL` produces), or a standard IP address
///   (`IPAddress(literal:)`). Numbers that aren't a standard address
///   (`3232235777`, `0x7f000001`, `127.1`) are refused: iOS would connect to
///   them as addresses, and ATS takes some for names.
///
/// Plain http, additionally:
/// 1. **A home address or a local name** that ATS lets through
///    (`Config/Octavo-Info.plist`): an IP in the home ranges, a name without
///    dots (`localhost`, `nas`), or one under `.local`, `.lan`, `.internal`,
///    `.home.arpa` or `.ts.net`. Other names need https.
/// 2. **Only home addresses when resolved**, special names included (an ISP
///    that answers unknown names, or a VPN's DNS, can send `nas.lan` to the
///    internet): each address in the home ranges, or a global IPv6 address on
///    the network the device is on right now (IPv6 homes give `nas.local` one).
///    100.64.0.0/10 counts only while a VPN tunnel (Tailscale) has an address
///    in it; otherwise it's the mobile carrier's or ISP's shared space.
/// 3. **No proxy:** a proxy would resolve the name itself, wherever it is.
public struct HomeNetworkPolicy: Sendable {
    /// Names under these suffixes count as local. Keep in step with
    /// `NSExceptionDomains` in `Config/Octavo-Info.plist`.
    public static let localSuffixes = ["local", "lan", "internal", "home.arpa", "ts.net"]

    public static let system = HomeNetworkPolicy(
        resolver: SystemHostResolver(),
        localNetworks: { LocalNetworks.current() },
        usesProxy: { SystemProxies.wouldProxy($0) }
    )

    private let resolver: any HostResolver
    private let localNetworks: @Sendable () -> LocalNetworks
    private let usesProxy: @Sendable (URL) -> Bool
    /// Check where each request actually connected (`verify`). Only tests
    /// with stub `URLProtocol`s, which have no addresses, turn it off.
    let verifiesConnections: Bool

    public init(
        resolver: any HostResolver,
        localNetworks: @escaping @Sendable () -> LocalNetworks,
        usesProxy: @escaping @Sendable (URL) -> Bool = { _ in false }
    ) {
        self.init(resolver: resolver, localNetworks: localNetworks, usesProxy: usesProxy, verifiesConnections: true)
    }

    init(
        resolver: any HostResolver,
        localNetworks: @escaping @Sendable () -> LocalNetworks,
        usesProxy: @escaping @Sendable (URL) -> Bool,
        verifiesConnections: Bool
    ) {
        self.resolver = resolver
        self.localNetworks = localNetworks
        self.usesProxy = usesProxy
        self.verifiesConnections = verifiesConnections
    }

    /// Throws `NetworkTrustError` if `url` mustn't be loaded, or
    /// `URLError(.cannotFindHost)` if an http host doesn't resolve.
    public func check(_ url: URL) async throws {
        let target = try Target(url)
        guard target.scheme == "http" else { return }
        let networks = localNetworks()
        switch target.address {
        case .ip(let address):
            // Literals stick to the fixed ranges: ATS refuses any other.
            guard isHome(address, networks, onThisNetwork: false) else {
                throw NetworkTrustError.insecureAddress(host: target.host, reason: .internetAddress(address.description))
            }
        case .name(let name):
            guard Self.isLocalName(name) else { throw NetworkTrustError.insecureAddress(host: name, reason: .notALocalName) }
            let addresses = try await resolver.addresses(of: name)
            guard !addresses.isEmpty else { throw URLError(.cannotFindHost) }
            for address in addresses where !isHome(address, networks, onThisNetwork: true) {
                throw NetworkTrustError.insecureAddress(host: name, reason: .internetAddress(address.description))
            }
        }
        if usesProxy(url) { throw NetworkTrustError.insecureAddress(host: target.host, reason: .throughProxy) }
    }

    /// A home IP address or a local name, judged from the URL alone (no DNS).
    /// An internet server's pages mustn't send the app here.
    public static func isLocalAddress(_ url: URL) -> Bool {
        guard let target = try? Target(url) else { return false }
        switch target.address {
        case .ip(let address): return address.isHomeRange || address.isUnspecified
        case .name(let name): return isLocalName(name)
        }
    }

    /// After the fact: what a request to `url` was actually connected to, from
    /// the task's metrics. `nil` if that's fine. Catches DNS answers that
    /// changed after `check` and proxies it couldn't see; it can't unsend the
    /// request, but the response is refused.
    /// - Parameter fromInternetServer: the transport's server isn't local, so
    ///   home addresses are off limits too.
    func verify(_ url: URL, connectedTo remote: String?, throughProxy: Bool, fromInternetServer: Bool) -> NetworkTrustError? {
        guard verifiesConnections else { return nil }
        let host = url.host(percentEncoded: true) ?? ""
        let plainHTTP = url.scheme?.lowercased() == "http"
        if plainHTTP, throughProxy { return .insecureAddress(host: host, reason: .throughProxy) }
        guard let remote, let address = IPAddress(literal: remote) else {
            // Plain http that can't be shown to have stayed home fails closed.
            return plainHTTP ? .insecureAddress(host: host, reason: .unverifiedConnection) : nil
        }
        let networks = localNetworks()
        if plainHTTP, !isHome(address, networks, onThisNetwork: true) {
            return .insecureAddress(host: host, reason: .internetAddress(address.description))
        }
        // Through a proxy the address is the proxy's, often on the LAN.
        if fromInternetServer, !throughProxy,
           address.isHomeRange || address.isUnspecified || isHome(address, networks, onThisNetwork: true) {
            return .insecureAddress(host: host, reason: .localAddressFromInternetServer)
        }
        return nil
    }

    /// - Parameter onThisNetwork: also count a global IPv6 address on the
    ///   network the device is on right now.
    private func isHome(_ address: IPAddress, _ networks: LocalNetworks, onThisNetwork: Bool) -> Bool {
        if address.isSharedAddressSpace { return networks.hasSharedAddressTunnel }
        if address.isHomeRange { return true }
        return onThisNetwork && address.isGlobalUnicastIPv6 && networks.ipv6Prefixes.contains { $0.contains(address) }
    }

    static func isLocalName(_ host: String) -> Bool {
        !host.contains(".") || localSuffixes.contains { host.hasSuffix("." + $0) }
    }
}

/// A URL's scheme and host as the connection will see them.
private struct Target {
    enum Address {
        case ip(IPAddress)
        case name(String)
    }

    var scheme: String
    /// Lowercased, without IPv6 brackets.
    var host: String
    var address: Address

    init(_ url: URL) throws {
        let refuse = NetworkTrustError.unsupportedAddress(url.trustDescription)
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.user(percentEncoded: true) == nil, url.password(percentEncoded: true) == nil,
              let host = url.connectionHost, !host.isEmpty else { throw refuse }
        if host.contains(":") {
            guard let address = IPAddress(literal: host), !address.isIPv4 else { throw refuse }
            self.address = .ip(address)
        } else if Self.looksNumeric(host) {
            guard let address = IPAddress(literal: host) else { throw refuse }
            self.address = .ip(address)
        } else {
            guard Self.isStandardName(host) else { throw refuse }
            self.address = .name(host)
        }
        self.scheme = scheme
        self.host = host
    }

    /// The last label is a number (decimal or `0x` hex): the host is meant as
    /// an IP address, however it's written.
    static func looksNumeric(_ host: String) -> Bool {
        let last = host.split(separator: ".", omittingEmptySubsequences: false).last ?? ""
        if !last.isEmpty, last.allSatisfy({ $0.isASCII && $0.isNumber }) { return true }
        return last.hasPrefix("0x") && last.dropFirst(2).allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// Lowercase ASCII letters, digits and hyphens in 1–63 character labels,
    /// no trailing dot.
    static func isStandardName(_ host: String) -> Bool {
        guard host.count <= 253 else { return false }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.count) && label.first != "-" && label.last != "-"
                && label.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        }
    }
}

/// Looks up a host's addresses.
public protocol HostResolver: Sendable {
    func addresses(of host: String) async throws -> [IPAddress]
}

/// The system resolver (`getaddrinfo`), asking for IPv4 and IPv6 whether or
/// not this device has a route for both, since the connection may use either.
public struct SystemHostResolver: HostResolver {
    public init() {}

    public func addresses(of host: String) async throws -> [IPAddress] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var list: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else {
                    continuation.resume(throwing: URLError(.cannotFindHost))
                    return
                }
                defer { freeaddrinfo(first) }
                var addresses: [IPAddress] = []
                for entry in sequence(first: first, next: { $0.pointee.ai_next }) {
                    if let address = entry.pointee.ai_addr.flatMap({ IPAddress(socketAddress: $0) }), !addresses.contains(address) {
                        addresses.append(address)
                    }
                }
                continuation.resume(returning: addresses)
            }
        }
    }
}

/// The networks this device is on right now, from its interfaces.
public struct LocalNetworks: Sendable {
    /// Global IPv6 prefixes of interfaces that are up and on a real link (not
    /// loopback, not a point-to-point tunnel), /48 or narrower, so a
    /// misconfigured or hostile router can't make the whole internet "local".
    public var ipv6Prefixes: [NetworkPrefix]
    /// A VPN tunnel (`utun`, as Tailscale's is) has an address in
    /// 100.64.0.0/10.
    public var hasSharedAddressTunnel: Bool

    public init(ipv6Prefixes: [NetworkPrefix] = [], hasSharedAddressTunnel: Bool = false) {
        self.ipv6Prefixes = ipv6Prefixes
        self.hasSharedAddressTunnel = hasSharedAddressTunnel
    }

    public static func current() -> LocalNetworks {
        var result = LocalNetworks()
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return result }
        defer { freeifaddrs(first) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, let addr = entry.pointee.ifa_addr, let address = IPAddress(socketAddress: addr) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            if name.hasPrefix("utun"), address.isSharedAddressSpace {
                result.hasSharedAddressTunnel = true
            }
            guard flags & (IFF_LOOPBACK | IFF_POINTOPOINT) == 0, address.isGlobalUnicastIPv6,
                  let mask = entry.pointee.ifa_netmask.flatMap({ IPAddress(socketAddress: $0) }) else { continue }
            let length = mask.bytes.reduce(0) { $0 + $1.nonzeroBitCount }
            guard (48...128).contains(length) else { continue }
            result.ipv6Prefixes.append(NetworkPrefix(address: address, length: length))
        }
        return result
    }
}

/// The system's proxy settings (Wi-Fi proxy, PAC, a configuration profile).
enum SystemProxies {
    /// Whether a request to `url` would go through a proxy. A PAC file counts
    /// as one: which proxy it picks isn't known without running it.
    static func wouldProxy(_ url: URL) -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else { return false }
        let proxies = CFNetworkCopyProxiesForURL(url as CFURL, settings).takeRetainedValue() as? [[CFString: Any]] ?? []
        return proxies.contains { ($0[kCFProxyTypeKey] as? String) != (kCFProxyTypeNone as String) }
    }
}

extension IPAddress {
    init?(socketAddress: UnsafePointer<sockaddr>) {
        switch Int32(socketAddress.pointee.sa_family) {
        case AF_INET:
            let bytes = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin_addr) { Array($0) }
            }
            self.init(bytes: bytes)
        case AF_INET6:
            let bytes = socketAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin6_addr) { Array($0) }
            }
            self.init(bytes: bytes)
        default:
            return nil
        }
    }
}

extension URL {
    /// The host as the connection uses it, lowercased and without IPv6
    /// brackets: from `absoluteString`, so internationalized names are in
    /// their `xn--` form (`host(percentEncoded:)` would percent-encode them)
    /// and other escapes stay as they are.
    var connectionHost: String? {
        guard var host = URLComponents(string: absoluteString)?.encodedHost?.lowercased() else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return host
    }

    /// Scheme, host and port only, for errors: no `user:password@`, and no
    /// path or query (Kavita puts its API key in the path).
    var trustDescription: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return scheme ?? "" }
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string ?? scheme ?? ""
    }
}
