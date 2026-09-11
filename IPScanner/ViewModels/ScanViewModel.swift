//
//  ScanViewModel.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import SwiftUI
import SwiftData
import Observation

/// Drives a single network scan: runs the coordinator, collects results,
/// persists them, fires notifications and produces the sorted/filtered list the
/// UI renders.
@MainActor
@Observable
final class ScanViewModel {
    private let context: ModelContext
    private let appState: AppState
    private var scanTask: Task<Void, Never>?

    var devices: [ScannedDevice] = []
    var searchText: String = ""
    var phase: ScanPhase = .idle
    var isScanning = false
    var errorMessage: String?
    var lastScanSummary: ScanSummary?
    var networkName = String(localized: "Local network")

    private var knownIPsBeforeScan: Set<String> = []
    private var knownMACsBeforeScan: Set<String> = []

    init(context: ModelContext, appState: AppState) {
        self.context = context
        self.appState = appState
    }

    // MARK: - Derived list

    var filteredDevices: [ScannedDevice] {
        var result = devices
        if appState.showOnlyNew {
            result = result.filter(\.isNew)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let lowerQuery = query.lowercased()
            let cleanHexQuery = lowerQuery.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
            let allPersisted = (try? context.fetch(FetchDescriptor<Device>())) ?? []

            result = result.filter { device in
                // 1. IP match
                if device.ip.localizedCaseInsensitiveContains(query) {
                    return true
                }
                // 2. MAC match (formatted or stripped hex)
                if let mac = device.mac {
                    if mac.localizedCaseInsensitiveContains(query) {
                        return true
                    }
                    let cleanMac = mac.lowercased().replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
                    if !cleanHexQuery.isEmpty && cleanMac.contains(cleanHexQuery) {
                        return true
                    }
                }
                // 3. Hostname match
                if let hostname = device.hostname, hostname.localizedCaseInsensitiveContains(query) {
                    return true
                }
                // 4. Vendor match
                if let vendor = device.vendor, vendor.localizedCaseInsensitiveContains(query) {
                    return true
                }
                // 5. Custom name match from persisted Device
                if let matchedPersisted = allPersisted.first(where: {
                    if let mac = device.mac, let persistedMAC = $0.macAddress, ARPTableService.isValidMAC(mac) {
                        return persistedMAC.caseInsensitiveCompare(mac) == .orderedSame
                    }
                    return $0.ipAddress == device.ip
                }) {
                    if let customName = matchedPersisted.customName, customName.localizedCaseInsensitiveContains(query) {
                        return true
                    }
                }
                return false
            }
        }

        switch appState.sortKey {
        case .name:
            result.sort { (lhs, rhs) in
                let a = lhs.hostname ?? lhs.ip
                let b = rhs.hostname ?? rhs.ip
                return appState.sortAscending ? a < b : a > b
            }
        case .ip:
            result.sort { (lhs, rhs) in
                let a = IPv4Address(string: lhs.ip)?.uint32 ?? 0
                let b = IPv4Address(string: rhs.ip)?.uint32 ?? 0
                return appState.sortAscending ? a < b : a > b
            }
        case .mac:
            result.sort { (lhs, rhs) in
                let a = lhs.mac ?? ""
                let b = rhs.mac ?? ""
                return appState.sortAscending ? a < b : a > b
            }
        case .lastSeen:
            result.sort { (lhs, rhs) in
                appState.sortAscending ? lhs.lastSeen < rhs.lastSeen : lhs.lastSeen > rhs.lastSeen
            }
        }
        return result
    }

    // MARK: - Scanning

    func startScan() {
        guard !isScanning else { return }
        guard let cidr = targetCIDR() else {
            errorMessage = String(localized: "Network not available")
            return
        }

        isScanning = true
        errorMessage = nil
        devices = []
        let allPersisted = (try? context.fetch(FetchDescriptor<Device>())) ?? []
        knownIPsBeforeScan = Set(allPersisted.map(\.ipAddress))
        knownMACsBeforeScan = Set(allPersisted.compactMap { dev -> String? in
            guard let mac = dev.macAddress, ARPTableService.isValidMAC(mac) else { return nil }
            return mac.uppercased()
        })

        scanTask = Task {
            await runScan(cidr: cidr)
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        phase = .idle
    }

    private func isDeviceNew(_ device: ScannedDevice) -> Bool {
        if let mac = device.mac, ARPTableService.isValidMAC(mac) {
            if knownMACsBeforeScan.contains(mac.uppercased()) {
                return false
            }
        }
        return !knownIPsBeforeScan.contains(device.ip)
    }

    private func targetCIDR() -> String? {
        switch appState.selection {
        case .network(.localSubnet), .none:
            return SubnetService.primaryIPv4Interface()?.cidr
        case .network(.custom(let persistentID)):
            let ranges = (try? context.fetch(FetchDescriptor<CustomNetworkRange>())) ?? []
            guard let range = ranges.first(where: { $0.persistentModelID == persistentID }) else {
                return nil
            }
            return range.cidr
        default:
            return nil
        }
    }

    private func runScan(cidr: String) async {
        let coordinator = NetworkScannerCoordinator()
        let stream = await coordinator.scan(cidr: cidr, includeBonjour: true)

        var responders: [ScannedDevice] = []
        for await event in stream {
            if Task.isCancelled { break }
            switch event {
            case .phase(let newPhase):
                phase = newPhase
            case .device(let incoming):
                var device = incoming
                device.isNew = isDeviceNew(device)

                if let index = devices.firstIndex(where: { $0.ip == device.ip }) {
                    let old = devices[index]
                    let merged = ScannedDevice(
                        id: device.id,
                        ip: device.ip,
                        mac: device.mac ?? old.mac,
                        hostname: device.hostname ?? old.hostname,
                        vendor: device.vendor ?? old.vendor,
                        firstSeen: old.firstSeen,
                        lastSeen: device.lastSeen,
                        isOnline: device.isOnline,
                        isNew: old.isNew
                    )
                    devices[index] = merged
                } else {
                    devices.append(device)
                }

                if let rIndex = responders.firstIndex(where: { $0.ip == device.ip }) {
                    let old = responders[rIndex]
                    let merged = ScannedDevice(
                        id: device.id,
                        ip: device.ip,
                        mac: device.mac ?? old.mac,
                        hostname: device.hostname ?? old.hostname,
                        vendor: device.vendor ?? old.vendor,
                        firstSeen: old.firstSeen,
                        lastSeen: device.lastSeen,
                        isOnline: device.isOnline,
                        isNew: old.isNew
                    )
                    responders[rIndex] = merged
                } else {
                    responders.append(device)
                }
            case .completed(let summary):
                lastScanSummary = summary
            }
        }

        guard !Task.isCancelled else {
            isScanning = false
            return
        }

        // Persist the cumulative device list + this session's history.
        for device in responders {
            DeviceStore.upsert(device, in: context)
        }
        DeviceStore.markOffline(excluding: Set(responders.map(\.ip)), in: context)
        insertScanSession(devices: responders, cidr: cidr)
        try? context.save()

        // Notify about brand-new devices if the user opted in.
        if appState.notificationsEnabled {
            for device in responders where device.isNew {
                await NotificationService.shared.notifyNewDevice(device)
            }
        }

        isScanning = false
        phase = .idle
    }

    private func insertScanSession(devices: [ScannedDevice], cidr: String) {
        let session = ScanSession(
            startedAt: Date(),
            cidr: cidr,
            duration: lastScanSummary?.duration ?? 0,
            deviceSnapshots: devices.map {
                DeviceSnapshot(
                    ip: $0.ip,
                    mac: $0.mac,
                    hostname: $0.hostname,
                    vendor: $0.vendor,
                    isOnline: $0.isOnline,
                    lastSeen: $0.lastSeen
                )
            }
        )
        context.insert(session)
    }
}
