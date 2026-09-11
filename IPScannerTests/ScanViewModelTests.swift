//
//  ScanViewModelTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 11/09/2026.
//

import XCTest
import SwiftData
@testable import IPScanner

@MainActor
final class ScanViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var appState: AppState!
    var viewModel: ScanViewModel!

    override func setUp() {
        super.setUp()
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        appState = AppState(defaults: UserDefaults(suiteName: #file)!)
        viewModel = ScanViewModel(context: context, appState: appState)

        viewModel.devices = [
            ScannedDevice(
                id: "192.168.1.10",
                ip: "192.168.1.10",
                mac: "AA:BB:CC:11:22:33",
                hostname: "macbook-pro.local",
                vendor: "Apple, Inc.",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                isNew: false
            ),
            ScannedDevice(
                id: "192.168.1.20",
                ip: "192.168.1.20",
                mac: "11:22:33:44:55:66",
                hostname: "brother-printer.local",
                vendor: "Brother Industries",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                isNew: false
            ),
            ScannedDevice(
                id: "192.168.1.30",
                ip: "192.168.1.30",
                mac: "DE:AD:BE:EF:00:01",
                hostname: nil,
                vendor: "Espressif Inc",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                isNew: true
            )
        ]
    }

    override func tearDown() {
        viewModel = nil
        appState = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testFilteredDevicesEmptySearchReturnsAll() {
        viewModel.searchText = ""
        XCTAssertEqual(viewModel.filteredDevices.count, 3)
    }

    func testFilteredDevicesByIP() {
        viewModel.searchText = "192.168.1.10"
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.10")

        viewModel.searchText = ".20"
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.20")
    }

    func testFilteredDevicesByMAC() {
        // Formatted with colons
        viewModel.searchText = "AA:BB:CC"
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.10")

        // Unformatted without colons (clean hex match)
        viewModel.searchText = "aabbcc11"
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.10")

        // Formatted with dashes
        viewModel.searchText = "11-22-33-44"
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.20")
    }

    func testFilteredDevicesByHostname() {
        viewModel.searchText = "macbook"
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.10")

        viewModel.searchText = "PRINTER"
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.20")
    }

    func testFilteredDevicesByVendor() {
        viewModel.searchText = "espressif"
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.30")
    }

    func testFilteredDevicesByCustomName() {
        // Persist a custom name for the Espressif device
        let customDevice = Device(
            ipAddress: "192.168.1.30",
            macAddress: "DE:AD:BE:EF:00:01",
            customName: "Sensore Temperatura Salotto"
        )
        context.insert(customDevice)
        try? context.save()

        viewModel.searchText = "Temperatura"
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.30")
    }

    func testFilteredDevicesNoMatchReturnsEmpty() {
        viewModel.searchText = "non-existent-device-query"
        XCTAssertTrue(viewModel.filteredDevices.isEmpty)
    }
}
