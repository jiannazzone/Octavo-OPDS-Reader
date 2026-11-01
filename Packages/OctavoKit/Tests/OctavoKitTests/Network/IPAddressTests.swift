import Foundation
@testable import OctavoKit
import Testing

struct IPAddressTests {
    @Test(arguments: [
        ("192.168.1.122", [192, 168, 1, 122]),
        ("0.0.0.0", [0, 0, 0, 0]),
        ("10.0.0.255", [10, 0, 0, 255]),
    ])
    func readsStandardIPv4(_ literal: String, _ bytes: [UInt8]) {
        #expect(IPAddress(literal: literal)?.bytes == bytes)
    }

    /// Spellings iOS reads differently from each other, or that ATS takes
    /// for names (measured on iOS 27.1, docs/notes/network-trust.md).
    @Test(arguments: [
        "3232235898",           // 192.168.1.122 as one decimal number
        "16843009",             // 1.1.1.1: passed ATS and reached Cloudflare
        "0x7f000001",           // hex
        "0177.0.0.1",           // octal 127.0.0.1, or decimal 177.0.0.1?
        "0300.0250.1.0172",     // octal 192.168.1.122
        "010.8.8.8",            // 10.8.8.8 to a naive check, 8.8.8.8 octal
        "192.168.001.122",      // leading zeros
        "0xc0.0xa8.0x1.0x7a",   // hex parts
        "127.1",                // short form
        "192.168.378",          // short form
        "192.168.1.122.",       // trailing dot
        "256.1.1.1",
        "1.2.3",
        "1.2.3.4.5",
        "١٩٢.١٦٨.١.١",          // Arabic-Indic digits
        "",
    ])
    func refusesOtherIPv4Spellings(_ literal: String) {
        #expect(IPAddress(literal: literal) == nil)
    }

    @Test func readsIPv6() throws {
        #expect(IPAddress(literal: "::1")?.bytes == Array(repeating: 0, count: 15) + [1])
        #expect(IPAddress(literal: "fe80::1%25en0") != nil)
        #expect(IPAddress(literal: "fe80::1%en0") != nil)
        #expect(IPAddress(literal: "::ffff:192.168.1.122")?.mappedIPv4 == IPAddress(literal: "192.168.1.122"))
        #expect(IPAddress(literal: "::ffff:c0a8:17a")?.mappedIPv4 == IPAddress(literal: "192.168.1.122"))
    }

    @Test(arguments: [
        "2001:db8::1%25en0",        // a zone only makes sense on link-local
        "fe80::1%25",               // empty zone
        "fe80::1%25en0/64",
        "::ffff:010.8.8.8",         // leading zero in the embedded IPv4
        "::ffff:127.1",
        "1:2:3:4:5:6:7:8:9",
        ":::1",
        "fe80::g",
    ])
    func refusesOtherIPv6Spellings(_ literal: String) {
        #expect(IPAddress(literal: literal) == nil)
    }

    @Test(arguments: [
        "10.0.0.1", "10.255.255.255",
        "172.16.0.0", "172.31.255.255",
        "192.168.0.1", "192.168.255.255",
        "100.64.0.0", "100.100.100.100", "100.127.255.255",   // RFC 6598, Tailscale
        "127.0.0.1", "127.255.255.254",
        "169.254.1.1",
        "::1",
        "fc00::1", "fd7a:115c:a1e0::1",                       // ULA, Tailscale
        "fe80::1", "febf::1",
        "::ffff:192.168.1.122", "::ffff:127.0.0.1", "::ffff:100.64.0.1",
    ])
    func homeRanges(_ literal: String) throws {
        #expect(try #require(IPAddress(literal: literal)).isHomeRange)
    }

    @Test(arguments: [
        "9.255.255.255", "11.0.0.0",
        "172.15.255.255", "172.32.0.0",
        "192.167.255.255", "192.169.0.0",
        "100.63.255.255", "100.128.0.0",
        "128.0.0.1", "169.253.255.255", "169.255.0.0",
        "0.0.0.0", "255.255.255.255", "224.0.0.251", "1.1.1.1", "8.8.8.8",
        "::", "::2", "fec0::1", "ff02::1",
        "2603:7001:f100:669::1",
        "::ffff:8.8.8.8", "::ffff:1.1.1.1",
        "64:ff9b::c0a8:17a",       // NAT64 of 192.168.1.122: goes out through the carrier
        "::192.168.1.122",         // IPv4-compatible (deprecated)
        "2002:c0a8:17a::1",        // 6to4 of 192.168.1.122
        "2001:0:4136:e378::1",     // Teredo
    ])
    func notHomeRanges(_ literal: String) throws {
        #expect(try !#require(IPAddress(literal: literal)).isHomeRange)
    }

    @Test func prefixes() throws {
        let home = NetworkPrefix(address: try #require(IPAddress(literal: "2603:7001:f100:669:c5d:569:60af:96b3")), length: 64)
        #expect(home.contains(try #require(IPAddress(literal: "2603:7001:f100:669::1"))))
        #expect(!home.contains(try #require(IPAddress(literal: "2603:7001:f100:66a::1"))))
        #expect(!home.contains(try #require(IPAddress(literal: "192.168.1.1"))))
        let odd = NetworkPrefix(address: try #require(IPAddress(literal: "2001:db8:abcd:12::")), length: 61)
        #expect(odd.contains(try #require(IPAddress(literal: "2001:db8:abcd:17::1"))))
        #expect(!odd.contains(try #require(IPAddress(literal: "2001:db8:abcd:18::1"))))
    }

    @Test func describes() throws {
        #expect(try #require(IPAddress(literal: "::ffff:c0a8:17a")).description == "::ffff:192.168.1.122")
        #expect(try #require(IPAddress(literal: "10.0.0.1")).description == "10.0.0.1")
    }
}
