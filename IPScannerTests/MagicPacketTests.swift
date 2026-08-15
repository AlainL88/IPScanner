//
//  MagicPacketTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class MagicPacketTests: XCTestCase {
    func testMagicPacketStructure() throws {
        let packet = try XCTUnwrap(MagicPacket.build(forMAC: "AA:BB:CC:DD:EE:FF"))
        XCTAssertEqual(packet.count, 102)

        // First 6 bytes: 0xFF sync.
        for i in 0..<6 {
            XCTAssertEqual(packet[packet.startIndex + i], 0xFF)
        }

        // Bytes 6...102: the MAC repeated 16 times.
        let mac = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        for i in 0..<16 {
            let base = 6 + i * 6
            for j in 0..<6 {
                XCTAssertEqual(packet[packet.startIndex + base + j], mac[j])
            }
        }
    }

    func testMACParsingFormats() {
        XCTAssertEqual(MagicPacket.parseMAC("AA-BB-CC-DD-EE-FF"), Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
        XCTAssertEqual(MagicPacket.parseMAC("aa:bb:cc:dd:ee:ff"), Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
        XCTAssertEqual(MagicPacket.parseMAC("aabb.ccdd.eeff"), Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
    }

    func testInvalidMAC() {
        XCTAssertNil(MagicPacket.build(forMAC: ""))
        XCTAssertNil(MagicPacket.build(forMAC: "ZZ:BB:CC:DD:EE:FF"))
        XCTAssertNil(MagicPacket.build(forMAC: "AA:BB:CC"))          // too short
        XCTAssertNil(MagicPacket.build(forMAC: "AA:BB:CC:DD:EE:FF:00")) // too long
    }
}
