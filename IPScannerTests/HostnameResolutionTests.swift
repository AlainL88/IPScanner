//
//  HostnameResolutionTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 11/09/2026.
//

import XCTest
@testable import IPScanner

final class HostnameResolutionTests: XCTestCase {
    func testReverseDNSLookupLoopback() {
        let result = DNSResolver.reverseLookup(ip: "127.0.0.1")
        XCTAssertNotNil(result, "127.0.0.1 should reverse resolve to localhost")
        XCTAssertEqual(result?.lowercased(), "localhost")
    }

    func testReverseDNSLookupInvalidIPReturnsNil() {
        let result = DNSResolver.reverseLookup(ip: "999.999.999.999")
        XCTAssertNil(result)
    }

    func testCleanHostnameHelper() {
        XCTAssertEqual(DNSResolver.cleanHostname("macbook-pro.local."), "macbook-pro")
        XCTAssertEqual(DNSResolver.cleanHostname("macbook-pro.local"), "macbook-pro")
        XCTAssertEqual(DNSResolver.cleanHostname("router.home.arpa."), "router.home.arpa")
        XCTAssertEqual(DNSResolver.cleanHostname("192.168.1.1"), nil)
    }
}
