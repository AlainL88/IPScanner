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

    @MainActor
    func testDeviceFollowsHostnameWhenIPChangesWithoutMAC() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        // Initial scan: Apple TV at 192.168.1.30 with hostname "appletv-salotto.local", no MAC
        let initial = ScannedDevice(
            id: "192.168.1.30",
            ip: "192.168.1.30",
            mac: nil,
            hostname: "appletv-salotto.local",
            vendor: "Apple",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: true
        )
        DeviceStore.upsert(initial, in: context)
        try context.save()

        let saved = try XCTUnwrap((try context.fetch(FetchDescriptor<Device>())).first)
        saved.customName = "Apple TV Salotto"
        try context.save()

        // iOS scan after DHCP change: Apple TV moved to 192.168.1.99, still no MAC available
        let moved = ScannedDevice(
            id: "192.168.1.99",
            ip: "192.168.1.99",
            mac: nil,
            hostname: "appletv-salotto.local",
            vendor: "Apple",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: false
        )
        DeviceStore.upsert(moved, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Device>())
        XCTAssertEqual(all.count, 1)
        let resolved = try XCTUnwrap(all.first)
        XCTAssertEqual(resolved.ipAddress, "192.168.1.99")
        XCTAssertEqual(resolved.customName, "Apple TV Salotto")
    }

    @MainActor
    func testConflictingDeviceDoesNotOverwriteKnownDeviceOnSameIP() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        // 1. Device A originally at 192.168.1.50 with custom name "Clima Salotto"
        let deviceA = Device(
            ipAddress: "192.168.1.50",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "clima-salotto.local",
            customName: "Clima Salotto"
        )
        context.insert(deviceA)
        try context.save()

        // 2. Scan from iOS at 192.168.1.50 finds a different device (Device B, iPad) without MAC
        let deviceBScanned = ScannedDevice(
            id: "192.168.1.50",
            ip: "192.168.1.50",
            mac: nil,
            hostname: "ipad-alain.local",
            vendor: "Apple",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: true
        )
        DeviceStore.upsert(deviceBScanned, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Device>())
        XCTAssertEqual(all.count, 2)

        // Device A retains its custom name and MAC
        let original = try XCTUnwrap(all.first(where: { $0.customName == "Clima Salotto" }))
        XCTAssertEqual(original.macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertFalse(original.isOnline)

        // Device B is created separately with its own hostname
        let newDevice = try XCTUnwrap(all.first(where: { $0.hostname == "ipad-alain.local" }))
        XCTAssertEqual(newDevice.ipAddress, "192.168.1.50")
        XCTAssertNil(newDevice.customName)
    }

    @MainActor
    func testDuplicateDeviceWithSameMACMergesAndPreservesCustomization() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        // Record A: Synced from Mac with custom name
        let deviceA = Device(
            ipAddress: "192.168.1.77",
            macAddress: "AA:11:22:33:44:55",
            hostname: "synology.local",
            customName: "NAS Principale",
            customIcon: "server.rack",
            isWhitelisted: true
        )
        context.insert(deviceA)
        try context.save()

        // Scan from iPhone sees the device at 192.168.1.77 with same MAC
        let scanned = ScannedDevice(
            id: "192.168.1.77",
            ip: "192.168.1.77",
            mac: "aa:11:22:33:44:55",
            hostname: "synology.local",
            vendor: "Synology",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: false
        )
        DeviceStore.upsert(scanned, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Device>())
        XCTAssertEqual(all.count, 1)
        let resolved = try XCTUnwrap(all.first)
        XCTAssertEqual(resolved.customName, "NAS Principale")
        XCTAssertEqual(resolved.customIcon, "server.rack")
        XCTAssertTrue(resolved.isWhitelisted)
        XCTAssertEqual(resolved.vendor, "Synology")
    }

    @MainActor
    func testDuplicateDeviceWithSameMACPrefersMoreRecentCustomName() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let olderDate = Date().addingTimeInterval(-3600)
        let newerDate = Date().addingTimeInterval(-60)

        // Record A: Older record created on Mac
        let deviceA = Device(
            ipAddress: "192.168.1.77",
            macAddress: "AA:11:22:33:44:55",
            hostname: "synology.local",
            customName: "Vecchio Nome",
            lastSeen: olderDate
        )
        // Record B: Newer record created/edited on iPhone with custom icon and whitelist
        let deviceB = Device(
            ipAddress: "192.168.1.77",
            macAddress: "AA:11:22:33:44:55",
            hostname: "synology.local",
            customName: "Nuovo Nome iPhone",
            customIcon: "server.rack",
            isWhitelisted: true,
            lastSeen: newerDate
        )
        context.insert(deviceA)
        context.insert(deviceB)
        try context.save()

        let scanned = ScannedDevice(
            id: "192.168.1.77",
            ip: "192.168.1.77",
            mac: "AA:11:22:33:44:55",
            hostname: "synology.local",
            vendor: "Synology",
            firstSeen: olderDate,
            lastSeen: Date(),
            isOnline: true,
            isNew: false
        )
        DeviceStore.upsert(scanned, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Device>())
        XCTAssertEqual(all.count, 1)
        let resolved = try XCTUnwrap(all.first)
        XCTAssertEqual(resolved.customName, "Nuovo Nome iPhone")
        XCTAssertEqual(resolved.customIcon, "server.rack")
        XCTAssertTrue(resolved.isWhitelisted)
    }

    @MainActor
    func testUpsertMergesAndDeletesUnMACDuplicateAtSameIP() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        // Record A: Created on iOS previously with no MAC address
        let deviceA = Device(
            ipAddress: "192.168.1.50",
            macAddress: nil,
            hostname: "camera.local",
            customName: "Vecchia Camera",
            isWhitelisted: true
        )
        context.insert(deviceA)
        try context.save()

        // Incoming scan has resolved MAC address
        let scanned = ScannedDevice(
            id: "192.168.1.50",
            ip: "192.168.1.50",
            mac: "AA:BB:CC:DD:EE:11",
            hostname: "camera.local",
            vendor: "D-Link",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: false
        )
        DeviceStore.upsert(scanned, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Device>())
        XCTAssertEqual(all.count, 1)
        let resolved = try XCTUnwrap(all.first)
        XCTAssertEqual(resolved.ipAddress, "192.168.1.50")
        XCTAssertEqual(resolved.macAddress, "AA:BB:CC:DD:EE:11")
        XCTAssertEqual(resolved.customName, "Vecchia Camera")
        XCTAssertTrue(resolved.isWhitelisted)
    }

    func testInferredIcon() {
        XCTAssertEqual(Device.inferredIcon(for: "Alain-iPad.local", ip: "192.168.1.5"), "ipad")
        XCTAssertEqual(Device.inferredIcon(for: "iPhone-15-Pro.local", ip: "192.168.1.6"), "iphone")
        XCTAssertEqual(Device.inferredIcon(for: "MacBook-Pro.local", ip: "192.168.1.7"), "laptopcomputer")
        XCTAssertEqual(Device.inferredIcon(for: "HomePod-Salotto.local", ip: "192.168.1.8"), "homepod.fill")
        XCTAssertEqual(Device.inferredIcon(for: "Apple-Watch.local", ip: "192.168.1.9"), "applewatch")
        XCTAssertEqual(Device.inferredIcon(for: "fritz.box", ip: "192.168.1.1"), "wifi.router")
        XCTAssertEqual(Device.inferredIcon(for: "synology-ds920.local", ip: "192.168.1.10"), "server.rack")
        XCTAssertEqual(Device.inferredIcon(for: "camera-ingresso.local", ip: "192.168.1.11"), "camera.fill")
        XCTAssertEqual(Device.inferredIcon(for: "philips-hue-bridge.local", ip: "192.168.1.12"), "lightbulb.fill")
        XCTAssertEqual(Device.inferredIcon(for: "ps5-console.local", ip: "192.168.1.13"), "gamecontroller.fill")
        XCTAssertEqual(Device.inferredIcon(for: "sonos-arc.local", ip: "192.168.1.14"), "speaker.wave.2.fill")
        XCTAssertEqual(Device.inferredIcon(for: "raspberrypi.local", ip: "192.168.1.15"), "terminal.fill")
        XCTAssertEqual(Device.inferredIcon(for: "epson-printer.local", ip: "192.168.1.16"), "printer")
        XCTAssertEqual(Device.inferredIcon(for: "samsung-smart-tv.local", ip: "192.168.1.17"), "tv")
    }
}
