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
        let container = PersistenceController.makeInMemoryContainer()
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
        let container = PersistenceController.makeInMemoryContainer()
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

    @MainActor
    func testDevicePreservesCustomNameWhenIPChanges() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        // 1. Initial scan: device found at 192.168.1.50 with MAC AA:BB:CC:11:22:33
        let initialScanned = ScannedDevice(
            id: "192.168.1.50",
            ip: "192.168.1.50",
            mac: "AA:BB:CC:11:22:33",
            hostname: "macbook.local",
            vendor: "Apple",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: true
        )
        DeviceStore.upsert(initialScanned, in: context)
        try context.save()

        // 2. User renames device and picks a custom icon
        let devices = try context.fetch(FetchDescriptor<Device>())
        let savedDevice = try XCTUnwrap(devices.first(where: { $0.macAddress == "AA:BB:CC:11:22:33" }))
        savedDevice.customName = "Alain's MacBook Pro"
        savedDevice.customIcon = "laptopcomputer"
        savedDevice.isWhitelisted = true
        try context.save()

        // 3. Next scan: device changed IP to 192.168.1.88, but keeps same MAC
        let updatedScanned = ScannedDevice(
            id: "192.168.1.88",
            ip: "192.168.1.88",
            mac: "aa:bb:cc:11:22:33", // case-insensitive check
            hostname: "macbook.local",
            vendor: "Apple",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: false
        )
        DeviceStore.upsert(updatedScanned, in: context)
        try context.save()

        // Verify there is still only 1 device record, its IP updated to .88, and custom name/icon preserved
        let allDevices = try context.fetch(FetchDescriptor<Device>())
        XCTAssertEqual(allDevices.count, 1)
        let resolved = try XCTUnwrap(allDevices.first)
        XCTAssertEqual(resolved.ipAddress, "192.168.1.88")
        XCTAssertEqual(resolved.customName, "Alain's MacBook Pro")
        XCTAssertEqual(resolved.customIcon, "laptopcomputer")
        XCTAssertTrue(resolved.isWhitelisted)
    }

    @MainActor
    func testUpsertFallbackToIPWhenMACUnavailable() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let device1 = ScannedDevice(
            id: "192.168.1.20",
            ip: "192.168.1.20",
            mac: nil,
            hostname: "iphone.local",
            vendor: nil,
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: true
        )
        DeviceStore.upsert(device1, in: context)
        try context.save()

        let saved = try XCTUnwrap((try context.fetch(FetchDescriptor<Device>())).first)
        saved.customName = "My iPhone"
        try context.save()

        let device1Rescan = ScannedDevice(
            id: "192.168.1.20",
            ip: "192.168.1.20",
            mac: nil,
            hostname: "iphone.local",
            vendor: nil,
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: false
        )
        DeviceStore.upsert(device1Rescan, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Device>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.customName, "My iPhone")
    }
}
