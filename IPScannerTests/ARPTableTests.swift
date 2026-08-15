//
//  ARPTableTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class ARPTableTests: XCTestCase {
    #if os(macOS)
    func testReadIsWellFormed() {
        let entries = ARPTableService.read()
        // Validate every entry's shape; the table may legitimately be empty on a
        // host with no LAN traffic yet.
        for entry in entries {
            XCTAssertNotNil(IPv4Address(string: entry.ipAddress), "ARP IP invalid: \(entry.ipAddress)")
            if let mac = entry.macAddress {
                XCTAssertEqual(mac.split(separator: ":").count, 6, "ARP MAC malformed: \(mac)")
            }
        }
    }

    func testReadDoesNotCrashOnMacOS() {
        // Smoke test: exercising the real sysctl path must not crash or hang.
        XCTAssertNoThrow(ARPTableService.read())
    }

    func testMacLookupUnknown() {
        XCTAssertNil(ARPTableService.macAddress(for: "203.0.113.250"))
    }
    #endif
}
