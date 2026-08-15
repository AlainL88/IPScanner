//
//  SubnetServiceTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class SubnetServiceTests: XCTestCase {
    func testPrivateIPDetection() {
        XCTAssertTrue(SubnetService.isPrivateIP("10.0.0.1"))
        XCTAssertTrue(SubnetService.isPrivateIP("172.16.0.1"))
        XCTAssertTrue(SubnetService.isPrivateIP("172.31.255.255"))
        XCTAssertTrue(SubnetService.isPrivateIP("192.168.1.23"))
        XCTAssertFalse(SubnetService.isPrivateIP("172.32.0.1"))   // outside 172.16/12
        XCTAssertFalse(SubnetService.isPrivateIP("8.8.8.8"))
        XCTAssertFalse(SubnetService.isPrivateIP("not-an-ip"))
    }

    func testPrefixLengthFromNetmask() {
        XCTAssertEqual(SubnetService.prefixLength(fromNetmask: "255.255.255.0"), 24)
        XCTAssertEqual(SubnetService.prefixLength(fromNetmask: "255.255.0.0"), 16)
        XCTAssertEqual(SubnetService.prefixLength(fromNetmask: "255.0.0.0"), 8)
        XCTAssertEqual(SubnetService.prefixLength(fromNetmask: "0.0.0.0"), 0)
        XCTAssertEqual(SubnetService.prefixLength(fromNetmask: "255.255.255.255"), 32)
        XCTAssertEqual(SubnetService.prefixLength(fromNetmask: "junk"), 0)
    }

    #if os(macOS)
    func testPrimaryInterfaceIsValid() throws {
        guard let iface = SubnetService.primaryIPv4Interface() else {
            throw XCTSkip("No active IPv4 interface on this host")
        }
        XCTAssertNotNil(IPv4Address(string: iface.ipAddress))
        XCTAssertLessThanOrEqual(iface.prefixLength, 32)
        XCTAssertTrue(iface.cidr.contains("/"))
    }
    #endif
}
