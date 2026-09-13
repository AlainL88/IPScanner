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

    func testAppStateDefaultVisibleColumns() {
        let defaults = UserDefaults(suiteName: "test_visible_columns_\(UUID().uuidString)")!
        let state = AppState(defaults: defaults)
        XCTAssertTrue(state.visibleColumns.contains(.ip))
        XCTAssertTrue(state.visibleColumns.contains(.mac))
        XCTAssertTrue(state.visibleColumns.contains(.hostname))
        XCTAssertTrue(state.visibleColumns.contains(.vendor))
        XCTAssertTrue(state.visibleColumns.contains(.status))
    }

    func testAppStateVisibleColumnsPersistence() {
        let suite = "test_visible_columns_persist_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let state1 = AppState(defaults: defaults)
        state1.visibleColumns = [.ip, .hostname, .lastSeen]
        state1.persist()

        let state2 = AppState(defaults: defaults)
        XCTAssertEqual(state2.visibleColumns, [.ip, .hostname, .lastSeen])
    }

    func testFilterModeOnlineOnly() {
        viewModel.devices[1] = ScannedDevice(
            id: "192.168.1.20",
            ip: "192.168.1.20",
            mac: "11:22:33:44:55:66",
            hostname: "brother-printer.local",
            vendor: "Brother Industries",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: false,
            isNew: false
        )

        viewModel.filterMode = .onlineOnly
        XCTAssertEqual(viewModel.filteredDevices.count, 2)
        XCTAssertTrue(viewModel.filteredDevices.allSatisfy(\.isOnline))

        viewModel.filterMode = .all
        XCTAssertEqual(viewModel.filteredDevices.count, 3)
    }

    func testAvailableIPsForCustomRange() {
        let range = CustomNetworkRange(name: "Test Subnet", cidr: "192.168.1.0/24")
        context.insert(range)
        try? context.save()
        appState.selection = .network(.custom(range.persistentModelID))

        XCTAssertEqual(viewModel.totalSubnetHostsCount, 254)
        // 254 total host IPs minus 3 occupied devices (.10, .20, .30) = 251 available IPs
        XCTAssertEqual(viewModel.availableIPs.count, 251)
        XCTAssertFalse(viewModel.availableIPs.contains("192.168.1.10"))
        XCTAssertFalse(viewModel.availableIPs.contains("192.168.1.20"))
        XCTAssertFalse(viewModel.availableIPs.contains("192.168.1.30"))
        XCTAssertTrue(viewModel.availableIPs.contains("192.168.1.1"))
        XCTAssertTrue(viewModel.availableIPs.contains("192.168.1.15"))
    }

    func testFilteredAvailableIPsWithSearch() {
        let range = CustomNetworkRange(name: "Test Subnet", cidr: "192.168.1.0/24")
        context.insert(range)
        try? context.save()
        appState.selection = .network(.custom(range.persistentModelID))

        viewModel.searchText = ".15"
        XCTAssertTrue(viewModel.filteredAvailableIPs.contains("192.168.1.15"))
        XCTAssertFalse(viewModel.filteredAvailableIPs.contains("192.168.1.10")) // occupied

        viewModel.searchText = "192.168.1.10"
        XCTAssertFalse(viewModel.filteredAvailableIPs.contains("192.168.1.10")) // .10 is occupied
        XCTAssertTrue(viewModel.filteredAvailableIPs.contains("192.168.1.100")) // .100 is available and matches query

        viewModel.searchText = "10.99.99"
        XCTAssertTrue(viewModel.filteredAvailableIPs.isEmpty) // outside subnet range
    }

    func testFilterModeWhitelistedOnly() {
        // Persist one whitelisted device (macbook at 192.168.1.10)
        let whitelistedDevice = Device(
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:11:22:33",
            isWhitelisted: true
        )
        context.insert(whitelistedDevice)
        try? context.save()

        viewModel.filterMode = .whitelistedOnly
        XCTAssertEqual(viewModel.filteredDevices.count, 1)
        XCTAssertEqual(viewModel.filteredDevices.first?.ip, "192.168.1.10")

        viewModel.filterMode = .notWhitelistedOnly
        XCTAssertEqual(viewModel.filteredDevices.count, 2)
        XCTAssertFalse(viewModel.filteredDevices.contains(where: { $0.ip == "192.168.1.10" }))
    }

    func testPeriodicStatusCheckStartAndStop() {
        viewModel.startPeriodicStatusCheck(interval: 60)
        XCTAssertFalse(viewModel.isScanning)

        viewModel.stopPeriodicStatusCheck()
    }

    func testRefreshDeviceStatusesWithLoopback() async {
        // Configure a device with 127.0.0.1 (which should respond to ping on local machine)
        let loopbackDevice = ScannedDevice(
            id: "127.0.0.1",
            ip: "127.0.0.1",
            mac: nil,
            hostname: "localhost",
            vendor: nil,
            firstSeen: Date().addingTimeInterval(-3600),
            lastSeen: Date().addingTimeInterval(-3600),
            isOnline: false,
            isNew: false
        )
        let deadDevice = ScannedDevice(
            id: "192.0.2.1", // TEST-NET-1 (non-routable/dead)
            ip: "192.0.2.1",
            mac: nil,
            hostname: nil,
            vendor: nil,
            firstSeen: Date().addingTimeInterval(-3600),
            lastSeen: Date().addingTimeInterval(-3600),
            isOnline: true,
            isNew: false
        )
        viewModel.devices = [loopbackDevice, deadDevice]

        // Persist records in SwiftData
        let persistedLoopback = Device(ipAddress: "127.0.0.1", isOnline: false)
        let persistedDead = Device(ipAddress: "192.0.2.1", isOnline: true)
        context.insert(persistedLoopback)
        context.insert(persistedDead)
        try? context.save()

        await viewModel.refreshDeviceStatuses()

        // Loopback should be marked online
        let updatedLoopback = viewModel.devices.first(where: { $0.ip == "127.0.0.1" })
        XCTAssertEqual(updatedLoopback?.isOnline, true)

        // Dead device should be marked offline
        let updatedDead = viewModel.devices.first(where: { $0.ip == "192.0.2.1" })
        XCTAssertEqual(updatedDead?.isOnline, false)

        // SwiftData persisted models should match
        XCTAssertEqual(persistedLoopback.isOnline, true)
        XCTAssertEqual(persistedDead.isOnline, false)
    }

    func testDeviceIPChangeDeduplicationInDevices() {
        // Initial state: device at .54 with MAC DE:AD:BE:EF:00:01
        let original = ScannedDevice(
            id: "192.168.1.54",
            ip: "192.168.1.54",
            mac: "DE:AD:BE:EF:00:01",
            hostname: "sensor-bedroom.local",
            vendor: "Espressif",
            firstSeen: Date().addingTimeInterval(-3600),
            lastSeen: Date().addingTimeInterval(-3600),
            isOnline: true,
            isNew: false
        )
        viewModel.devices = [original]

        // Device changes IP to .52 and appears with the same MAC
        let moved = ScannedDevice(
            id: "192.168.1.52",
            ip: "192.168.1.52",
            mac: "de:ad:be:ef:00:01", // case-insensitive check
            hostname: "sensor-bedroom.local",
            vendor: "Espressif",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            isNew: false
        )

        // Simulate incoming scanned device update
        // We can test filteredDevices or direct scan upsert behavior
        DeviceStore.upsert(original, in: context)
        DeviceStore.upsert(moved, in: context)
        try? context.save()

        let persisted = (try? context.fetch(FetchDescriptor<Device>())) ?? []
        // There should be only 1 persisted record, at .52
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.ipAddress, "192.168.1.52")
        XCTAssertEqual(persisted.first?.macAddress, "de:ad:be:ef:00:01")
    }
}
