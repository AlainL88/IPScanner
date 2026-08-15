//
//  PingTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class PingTests: XCTestCase {
    /// Verifies the ICMP checksum against an independently computed vector.
    func testChecksumVector() throws {
        let packet = SimplePing.makeEchoRequest(identifier: 0x1234, sequence: 0x0001)
        let bytes = [UInt8](packet)
        XCTAssertEqual(bytes.count, 16)
        let checksum = (UInt16(bytes[2]) << 8) | UInt16(bytes[3])
        XCTAssertEqual(checksum, 0xe5ca, "ICMP checksum did not match the reference vector")
    }

    func testParseEchoReply() {
        let bytes: [UInt8] = [0, 0, 0xFF, 0xFE, 0x12, 0x34, 0x00, 0x02, 1, 2, 3, 4]
        let reply = SimplePing.parseEchoReply(Data(bytes))
        XCTAssertEqual(reply?.type, 0)
        XCTAssertEqual(reply?.identifier, 0x1234)
        XCTAssertEqual(reply?.sequence, 0x0002)

        XCTAssertNil(SimplePing.parseEchoReply(Data([0])))
        XCTAssertNil(SimplePing.parseEchoReply(Data([0x01, 0, 0, 0, 0, 0, 0, 0]))) // type 1: not echo
    }

    /// A non-routable TEST-NET address must yield a structured failure (send error
    /// or timeout), never a hang.
    func testFailureOnDeadHost() {
        let result = SimplePing.ping(host: "192.0.2.1", identifier: 7, sequence: 1, timeout: 0.5)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.address, "192.0.2.1")
        XCTAssertNotNil(result.errorDescription)
    }

    /// Loopback always answers ICMP on macOS: exercises the actor + GCD path.
    func testLoopbackPing() async {
        let service = PingService(timeout: 2)
        let result = await service.ping(host: "127.0.0.1")
        XCTAssertTrue(result.succeeded, result.errorDescription ?? "no error")
        XCTAssertNotNil(result.roundTripTime)
    }
}
