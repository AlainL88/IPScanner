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

    func testScansAndEmitsDeviceEventsIncrementally() async {
        let coordinator = NetworkScannerCoordinator()
        let stream = await coordinator.scan(cidr: "127.0.0.1/32", includeBonjour: false)

        var eventTypes: [String] = []
        for await event in stream {
            switch event {
            case .phase(let phase):
                eventTypes.append("phase_\(phase)")
            case .device(let device):
                eventTypes.append("device_\(device.ip)")
            case .completed:
                eventTypes.append("completed")
            }
        }

        XCTAssertTrue(eventTypes.contains(where: { $0.hasPrefix("phase_pinging") }))
        XCTAssertTrue(eventTypes.contains("device_127.0.0.1"))
        XCTAssertEqual(eventTypes.last, "completed")
    }
}
