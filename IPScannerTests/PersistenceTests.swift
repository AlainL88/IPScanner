//
//  PersistenceTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
import SwiftData
@testable import IPScanner

final class PersistenceTests: XCTestCase {
    @MainActor
    func testInMemoryContainerRoundTrip() throws {
        let container = PersistenceController.previewContainer
        let context = container.mainContext

        let device = Device(ipAddress: "192.168.1.5", macAddress: "AA:BB:CC:DD:EE:FF", hostname: "test-host")
        context.insert(device)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Device>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.ipAddress, "192.168.1.5")
        XCTAssertEqual(fetched.first?.macAddress, "AA:BB:CC:DD:EE:FF")
    }

    @MainActor
    func testScanSessionSnapshotRoundTrip() throws {
        let container = PersistenceController.previewContainer
        let context = container.mainContext
        let session = ScanSession(
            cidr: "192.168.1.0/24",
            duration: 1.5,
            deviceSnapshots: [DeviceSnapshot(ip: "192.168.1.7", hostname: "camera")]
        )
        context.insert(session)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ScanSession>())
        XCTAssertEqual(fetched.first?.deviceSnapshots.first?.hostname, "camera")
    }

    func testDeviceDisplayName() {
        let named = Device(ipAddress: "192.168.1.5", hostname: "router.local", customName: "Router")
        XCTAssertEqual(named.displayName, "Router")

        let unnamed = Device(ipAddress: "192.168.1.9")
        XCTAssertEqual(unnamed.displayName, "192.168.1.9")
    }
}
