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
    var phase: ScanPhase = .idle
    var isScanning = false
    var errorMessage: String?
    var lastScanSummary: ScanSummary?
    var networkName = String(localized: "Local network")

    private var knownIPsBeforeScan: Set<String> = []

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
        knownIPsBeforeScan = Set((try? context.fetch(FetchDescriptor<Device>()))?.map(\.ipAddress) ?? [])

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
            case .device(let device):
                var device = device
                device.isNew = !knownIPsBeforeScan.contains(device.ip)
                devices.append(device)
                responders.append(device)
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
