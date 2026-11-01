import Foundation

/// An IPv4 or IPv6 address, as raw bytes (4 or 16).
///
/// `init?(literal:)` accepts only the one standard spelling. iOS reads other
/// spellings inconsistently and ATS mistakes some for names: on iOS 27.1,
/// `http://16843009/` (1.1.1.1 as one decimal number) passes ATS and connects,
/// `0300.0250.1.0172` connects to 192.168.1.122, and `0177.0.0.1` doesn't
/// reach 127.0.0.1. A check that read them differently from the connection
/// would let plain http out to the internet (`docs/notes/network-trust.md`).
public struct IPAddress: Hashable, Sendable, CustomStringConvertible {
    /// 4 bytes for IPv4, 16 for IPv6.
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == 4 || bytes.count == 16 else { return nil }
        self.bytes = bytes
    }

    public var isIPv4: Bool { bytes.count == 4 }

    /// A URL host in its standard form: dotted decimal IPv4 with exactly four
    /// parts and no leading zeros, or IPv6 (without brackets). An IPv6 zone
    /// (`fe80::1%25en0`, as `URL.host` returns it) is only allowed on a
    /// link-local address, and is dropped.
    public init?(literal: String) {
        if literal.contains(":") {
            var address = Substring(literal)
            if let percent = literal.firstIndex(of: "%") {
                var zone = literal[literal.index(after: percent)...]
                if zone.hasPrefix("25") { zone = zone.dropFirst(2) }
                guard !zone.isEmpty, zone.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
                address = literal[..<percent]
            }
            // inet_pton reads an embedded IPv4 part itself; hold it to the
            // same standard spelling.
            if let lastColon = address.lastIndex(of: ":"), address[lastColon...].contains(".") {
                guard Self.parseIPv4(String(address[address.index(after: lastColon)...])) != nil else { return nil }
            }
            var raw = in6_addr()
            guard address.allSatisfy({ $0.isASCII }), inet_pton(AF_INET6, String(address), &raw) == 1 else { return nil }
            let parsed = withUnsafeBytes(of: &raw) { Array($0) }
            if address.endIndex != literal.endIndex, !(parsed[0] == 0xfe && parsed[1] & 0xc0 == 0x80) { return nil }
            bytes = parsed
        } else {
            guard let parsed = Self.parseIPv4(literal) else { return nil }
            bytes = parsed
        }
    }

    private static func parseIPv4(_ string: String) -> [UInt8]? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: [UInt8] = []
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part == "0" || part.first != "0", let value = UInt8(part) else { return nil }
            result.append(value)
        }
        return result
    }

    /// The IPv4 address inside an IPv4-mapped IPv6 address (`::ffff:a.b.c.d`).
    public var mappedIPv4: IPAddress? {
        guard bytes.count == 16, bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff else { return nil }
        return IPAddress(bytes: Array(bytes[12...]))
    }

    /// In one of the fixed home and VPN ranges (D25): RFC 1918, RFC 6598,
    /// loopback, link-local, IPv6 ULA and link-local. An IPv4-mapped IPv6
    /// address counts as its IPv4 address. Everything else, including NAT64
    /// (`64:ff9b::/96`), 6to4 and IPv4-compatible addresses, doesn't.
    public var isHomeRange: Bool {
        if let mapped = mappedIPv4 { return mapped.isHomeRange }
        let b = bytes
        if b.count == 4 {
            return b[0] == 10                                    // 10.0.0.0/8
                || (b[0] == 172 && b[1] & 0xf0 == 16)            // 172.16.0.0/12
                || (b[0] == 192 && b[1] == 168)                  // 192.168.0.0/16
                || (b[0] == 100 && b[1] & 0xc0 == 64)            // 100.64.0.0/10
                || b[0] == 127                                   // 127.0.0.0/8
                || (b[0] == 169 && b[1] == 254)                  // 169.254.0.0/16
        }
        return b == Self.ipv6Loopback                            // ::1
            || b[0] & 0xfe == 0xfc                               // fc00::/7
            || (b[0] == 0xfe && b[1] & 0xc0 == 0x80)             // fe80::/10
    }

    /// 0.0.0.0/8 or `::`: "this host" to the connection layer (macOS and iOS
    /// connect 0.0.0.0 to the device itself), so treated as local.
    public var isUnspecified: Bool {
        if let mapped = mappedIPv4 { return mapped.isUnspecified }
        return bytes.count == 4 ? bytes[0] == 0 : bytes.allSatisfy { $0 == 0 }
    }

    /// In 100.64.0.0/10 (RFC 6598): Tailscale's addresses, but also the
    /// shared space mobile carriers and some ISPs number their customers in.
    public var isSharedAddressSpace: Bool {
        if let mapped = mappedIPv4 { return mapped.isSharedAddressSpace }
        return bytes.count == 4 && bytes[0] == 100 && bytes[1] & 0xc0 == 64
    }

    /// A global unicast IPv6 address (`2000::/3`): the kind a home network
    /// with IPv6 hands out, and only home when it's on the network the device
    /// is on right now (`NetworkPrefix`).
    var isGlobalUnicastIPv6: Bool {
        bytes.count == 16 && bytes[0] & 0xe0 == 0x20
    }

    private static let ipv6Loopback: [UInt8] = Array(repeating: 0, count: 15) + [1]

    public var description: String {
        if bytes.count == 4 { return bytes.map(String.init).joined(separator: ".") }
        var raw = in6_addr()
        withUnsafeMutableBytes(of: &raw) { $0.copyBytes(from: bytes) }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &raw, &buffer, socklen_t(buffer.count)) != nil else { return "?" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// A network a device interface is on: an address and its prefix length.
public struct NetworkPrefix: Hashable, Sendable {
    public var address: IPAddress
    public var length: Int

    public init(address: IPAddress, length: Int) {
        self.address = address
        self.length = length
    }

    public func contains(_ other: IPAddress) -> Bool {
        guard other.bytes.count == address.bytes.count, (0...address.bytes.count * 8).contains(length) else { return false }
        var remaining = length
        for (a, b) in zip(address.bytes, other.bytes) where remaining > 0 {
            let bits = min(8, remaining)
            let mask = UInt8(truncatingIfNeeded: 0xff << (8 - bits))
            if a & mask != b & mask { return false }
            remaining -= bits
        }
        return true
    }
}
