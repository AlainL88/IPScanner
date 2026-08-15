//
//  IPv4Tests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class IPv4Tests: XCTestCase {
    func testParseValid() {
        let ip = IPv4Address(string: "192.168.1.5")
        XCTAssertEqual(ip, IPv4Address(192, 168, 1, 5))
        XCTAssertEqual(ip?.description, "192.168.1.5")
    }

    func testParseRejectsMalformed() {
        XCTAssertNil(IPv4Address(string: "256.1.1.1"))
        XCTAssertNil(IPv4Address(string: "abc"))
        XCTAssertNil(IPv4Address(string: "1.2.3"))
        XCTAssertNil(IPv4Address(string: "1.2.3.4.5"))
        XCTAssertNil(IPv4Address(string: "192.168.1.05")) // leading zero
        XCTAssertNil(IPv4Address(string: ""))
    }

    func testNext() {
        XCTAssertEqual(IPv4Address(192, 168, 1, 1).next(), IPv4Address(192, 168, 1, 2))
        XCTAssertEqual(IPv4Address(192, 168, 1, 255).next(), IPv4Address(192, 168, 2, 0))
        XCTAssertNil(IPv4Address(255, 255, 255, 255).next())
    }

    func testHostAddressHeuristic() {
        XCTAssertFalse(IPv4Address(192, 168, 1, 0).isHostAddress)
        XCTAssertFalse(IPv4Address(192, 168, 1, 255).isHostAddress)
        XCTAssertTrue(IPv4Address(192, 168, 1, 5).isHostAddress)
    }

    func testUInt32RoundTrip() {
        let ip = IPv4Address(10, 20, 30, 40)
        XCTAssertEqual(IPv4Address(uint32: ip.uint32), ip)
        XCTAssertEqual(IPv4Address(uint32: 0).description, "0.0.0.0")
        XCTAssertEqual(IPv4Address(uint32: UInt32.max).description, "255.255.255.255")
    }

    func testCIDRParse() {
        let parsed = IPv4CIDR.parse("192.168.1.0/24")
        XCTAssertEqual(parsed?.network, IPv4Address(192, 168, 1, 0))
        XCTAssertEqual(parsed?.prefix, 24)
        XCTAssertNil(IPv4CIDR.parse("192.168.1.0"))      // missing prefix
        XCTAssertNil(IPv4CIDR.parse("1.2.3.0/33"))       // prefix > 32
        XCTAssertNil(IPv4CIDR.parse("nope/24"))          // bad network
    }

    func testCIDR30Expansion() {
        let hosts = IPv4CIDR.hostAddresses("10.0.0.0/30")
        XCTAssertEqual(hosts.map(\.description), ["10.0.0.1", "10.0.0.2"])
    }

    func testCIDR24ExpansionCapped() {
        let hosts = IPv4CIDR.hostAddresses("192.168.1.0/24", maxHosts: 10)
        XCTAssertEqual(hosts.count, 10)
        XCTAssertEqual(hosts.first?.description, "192.168.1.1")
        XCTAssertEqual(hosts.last?.description, "192.168.1.10")
    }

    func testCIDRBroadcast() {
        XCTAssertEqual(IPv4CIDR.broadcast(of: IPv4Address(192, 168, 1, 0), prefix: 24).description, "192.168.1.255")
        XCTAssertEqual(IPv4CIDR.broadcast(of: IPv4Address(10, 0, 0, 0), prefix: 8).description, "10.255.255.255")
    }

    func testCIDR31And32() {
        XCTAssertEqual(IPv4CIDR.hostAddresses("10.0.0.0/31").map(\.description), ["10.0.0.0", "10.0.0.1"])
        XCTAssertEqual(IPv4CIDR.hostAddresses("10.0.0.1/32").map(\.description), ["10.0.0.1"])
    }
}
