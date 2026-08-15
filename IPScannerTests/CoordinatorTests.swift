//
//  CoordinatorTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class CoordinatorTests: XCTestCase {
    /// End-to-end: a /32 scan of loopback exercises the full pipeline
    /// (ping sweep -> ARP -> OUI) and must report the local host as a device.
    func testScansLoopbackEndToEnd() async {
        let coordinator = NetworkScannerCoordinator()
        let stream = await coordinator.scan(cidr: "127.0.0.1/32", includeBonjour: false)

        var foundIPs: [String] = []
        var completed = false
        for await event in stream {
            switch event {
            case .device(let device):
                foundIPs.append(device.ip)
            case .completed:
                completed = true
            default:
                break
            }
        }

        XCTAssertTrue(foundIPs.contains("127.0.0.1"))
        XCTAssertTrue(completed, "The scan must emit a completion event")
    }
}
