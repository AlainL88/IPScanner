//
//  ExportTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class ExportTests: XCTestCase {
    private func sampleDevice() -> ScannedDevice {
        ScannedDevice(
            id: "192.168.1.5",
            ip: "192.168.1.5",
            mac: "AA:BB:CC:DD:EE:FF",
            hostname: "router",
            vendor: "Apple, Inc.",
            firstSeen: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0),
            isOnline: true,
            isNew: false
        )
    }

    func testCSVHeaderAndQuoting() {
        let csv = ExportService.csvString(for: [sampleDevice()])
        XCTAssertTrue(csv.hasPrefix("IP,MAC,Hostname,Vendor,Status,Last Seen\n"))
        XCTAssertTrue(csv.contains("192.168.1.5"))
        XCTAssertTrue(csv.contains("\"Apple, Inc.\""), "Comma-containing vendor must be RFC-4180 quoted")
        XCTAssertTrue(csv.contains("AA:BB:CC:DD:EE:FF"))
        XCTAssertTrue(csv.contains(",online,"))
    }

    func testJSONRoundTrip() throws {
        let json = ExportService.jsonString(for: [sampleDevice()])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]]
        )
        XCTAssertEqual(object.first?["ip"], "192.168.1.5")
        XCTAssertEqual(object.first?["mac"], "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(object.first?["vendor"], "Apple, Inc.")
        XCTAssertEqual(object.first?["status"], "online")
    }

    func testEmptyExport() {
        XCTAssertEqual(ExportService.csvString(for: []), "IP,MAC,Hostname,Vendor,Status,Last Seen\n")
        let json = ExportService.jsonString(for: [])
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any]
        XCTAssertEqual(object?.isEmpty, true)
    }
}
