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
/// Filter mode for the scanned devices list.
public enum DeviceListFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case onlineOnly
    case whitelistedOnly
    case notWhitelistedOnly
    case availableOnly

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .onlineOnly:
            return String(localized: "Online")
        case .whitelistedOnly:
            return String(localized: "Whitelisted")
        case .notWhitelistedOnly:
            return String(localized: "Not in Whitelist")
        case .availableOnly:
            return String(localized: "Free IPs")
        }
    }
}

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
    var filterMode: DeviceListFilter = .all
    var phase: ScanPhase = .idle
    var isScanning = false
    var isRefreshingStatus = false
    var errorMessage: String?
    var lastScanSummary: ScanSummary?
    var networkName = String(localized: "Local network")

    private var knownIPsBeforeScan: Set<String> = []
    private var knownMACsBeforeScan: Set<String> = []
    private var statusRefreshTask: Task<Void, Never>?

    init(context: ModelContext, appState: AppState) {
        self.context = context
        self.appState = appState
    }

    // MARK: - Subnet & Free IPs

    var currentCIDR: String? {
        targetCIDR()
    }

    var allSubnetHostIPs: [IPv4Address] {
        guard let cidr = targetCIDR() else { return [] }
        return IPv4CIDR.hostAddresses(cidr)
    }

    var totalSubnetHostsCount: Int {
        allSubnetHostIPs.count
    }

    var availableIPs: [String] {
        guard let cidr = targetCIDR() else { return [] }
        let allHosts = IPv4CIDR.hostAddresses(cidr)
        let occupied = Set(devices.map(\.ip))
        var freeList = allHosts.map(\.description).filter { !occupied.contains($0) }
        if !appState.sortAscending && appState.sortKey == .ip {
            freeList.reverse()
        }
        return freeList
    }

    var filteredAvailableIPs: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return availableIPs
        }
        return availableIPs.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Derived list

    var filteredDevices: [ScannedDevice] {
        var result = devices
        let allPersisted = (try? context.fetch(FetchDescriptor<Device>())) ?? []

        switch filterMode {
        case .all:
            break
        case .onlineOnly:
            result = result.filter(\.isOnline)
        case .whitelistedOnly:
            let whitelistedMACs = Set(allPersisted.filter(\.isWhitelisted).compactMap { dev -> String? in
                guard let mac = dev.macAddress, ARPTableService.isValidMAC(mac) else { return nil }
                return mac.uppercased()
            })
            let whitelistedIPs = Set(allPersisted.filter(\.isWhitelisted).map(\.ipAddress))
            result = result.filter { dev in
                if let mac = dev.mac?.uppercased(), whitelistedMACs.contains(mac) {
                    return true
                }
                return whitelistedIPs.contains(dev.ip)
            }
        case .notWhitelistedOnly:
            let whitelistedMACs = Set(allPersisted.filter(\.isWhitelisted).compactMap { dev -> String? in
                guard let mac = dev.macAddress, ARPTableService.isValidMAC(mac) else { return nil }
                return mac.uppercased()
            })
            let whitelistedIPs = Set(allPersisted.filter(\.isWhitelisted).map(\.ipAddress))
            result = result.filter { dev in
                if let mac = dev.mac?.uppercased(), whitelistedMACs.contains(mac) {
                    return false
                }
                return !whitelistedIPs.contains(dev.ip)
            }
        case .availableOnly:
            break
        }

        if appState.showOnlyNew {
            result = result.filter(\.isNew)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let lowerQuery = query.lowercased()
            let cleanHexQuery = lowerQuery.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")

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

    // MARK: - Periodic Status Check & Quick Ping

    /// Starts periodic quick status checks (pinging existing devices to update online/offline status and discovering new devices).
    func startPeriodicStatusCheck(interval: TimeInterval = 15) {
        stopPeriodicStatusCheck()
        statusRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                if !self.isScanning {
                    await self.refreshDeviceStatuses()
                }
            }
        }
    }

    /// Stops the periodic status check task.
    func stopPeriodicStatusCheck() {
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
    }

    /// Quickly checks reachable status (ICMP ping with retry + TCP probe) for all currently known devices,
    /// and auto-discovers newly connected or migrated devices appearing on the network in real-time.
    func refreshDeviceStatuses() async {
        guard !isScanning, !isRefreshingStatus else { return }
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        let now = Date()
        let currentDevices = devices

        // 1. Update statuses of existing devices if any
        if !currentDevices.isEmpty {
            let pingService = PingService(timeout: 1.2)

            await withTaskGroup(of: (String, Bool).self) { group in
                for device in currentDevices {
                    let ip = device.ip
                    group.addTask {
                        // 1. Fast ICMP ping check with 1 retry (2 attempts to absorb transient WiFi drops)
                        let pingResult = await pingService.ping(host: ip, retries: 1, timeout: 1.0)
                        if pingResult.succeeded {
                            return (ip, true)
                        }
                        // 2. Multi-port TCP probe fallback (checks common IoT, smart home, media, and printer ports)
                        if await PortScanService.isHostReachable(host: ip, timeout: 0.4) {
                            return (ip, true)
                        }
                        #if os(macOS)
                        // 3. Active ARP table entry (crucial for macOS hosts with firewall/stealth mode active)
                        if let currentMAC = ARPTableService.macAddress(for: ip), ARPTableService.isValidMAC(currentMAC) {
                            return (ip, true)
                        }
                        #endif
                        return (ip, false)
                    }
                }

                var updatedStatuses: [String: Bool] = [:]
                for await (ip, isOnline) in group {
                    updatedStatuses[ip] = isOnline
                }

                for index in devices.indices {
                    let ip = devices[index].ip
                    if let isOnline = updatedStatuses[ip] {
                        if devices[index].isOnline != isOnline {
                            devices[index] = ScannedDevice(
                                id: devices[index].id,
                                ip: devices[index].ip,
                                mac: devices[index].mac,
                                hostname: devices[index].hostname,
                                vendor: devices[index].vendor,
                                firstSeen: devices[index].firstSeen,
                                lastSeen: isOnline ? now : devices[index].lastSeen,
                                isOnline: isOnline,
                                isNew: devices[index].isNew
                            )
                        } else if isOnline {
                            devices[index] = ScannedDevice(
                                id: devices[index].id,
                                ip: devices[index].ip,
                                mac: devices[index].mac,
                                hostname: devices[index].hostname,
                                vendor: devices[index].vendor,
                                firstSeen: devices[index].firstSeen,
                                lastSeen: now,
                                isOnline: true,
                                isNew: devices[index].isNew
                            )
                        }
                    }
                }

                // Persist status updates in SwiftData
                let allPersisted = (try? context.fetch(FetchDescriptor<Device>())) ?? []
                for (ip, isOnline) in updatedStatuses {
                    if let match = allPersisted.first(where: { $0.ipAddress == ip }) {
                        if match.isOnline != isOnline {
                            match.isOnline = isOnline
                        }
                        if isOnline {
                            match.lastSeen = now
                        }
                    }
                }
                try? context.save()
            }
        }

        // 2. Auto-discover new or migrated devices appearing on the network in real-time
        if let cidr = targetCIDR() {
            let targetIPSet = Set(IPv4CIDR.hostAddresses(cidr).map(\.description))
            let currentActiveIPSet = Set(devices.filter(\.isOnline).map(\.ip))
            let arpEntries = ARPTableService.read().filter { entry in
                guard let mac = entry.macAddress, ARPTableService.isValidMAC(mac) else { return false }
                return targetIPSet.contains(entry.ipAddress) && !currentActiveIPSet.contains(entry.ipAddress)
            }

            if !arpEntries.isEmpty {
                let pingService = PingService(timeout: 1.2)
                let oui = OUILookupService()
                let allPersisted = (try? context.fetch(FetchDescriptor<Device>())) ?? []
                let knownPersistedIPs = Set(allPersisted.map(\.ipAddress))
                let knownPersistedMACs = Set(allPersisted.compactMap { dev -> String? in
                    guard let mac = dev.macAddress, ARPTableService.isValidMAC(mac) else { return nil }
                    return mac.uppercased()
                })

                for entry in arpEntries {
                    guard let mac = entry.macAddress else { continue }
                    let ip = entry.ipAddress

                    // Liveness verification: verify that the IP responds to ICMP or TCP, or has valid ARP
                    let pingResult = await pingService.ping(host: ip, retries: 1, timeout: 1.0)
                    let isReachable: Bool
                    if pingResult.succeeded {
                        isReachable = true
                    } else if await PortScanService.isHostReachable(host: ip, timeout: 0.4) {
                        isReachable = true
                    } else {
                        #if os(macOS)
                        isReachable = ARPTableService.isValidMAC(mac)
                        #else
                        isReachable = false
                        #endif
                    }
                    guard isReachable else { continue }

                    let vendor = await oui.vendorName(forMAC: mac)
                    let hostname = DNSResolver.reverseLookup(ip: ip)
                    let isBrandNew = !knownPersistedIPs.contains(ip) && !knownPersistedMACs.contains(mac.uppercased())
                    let newDevice = ScannedDevice(
                        id: ip,
                        ip: ip,
                        mac: mac,
                        hostname: hostname,
                        vendor: vendor,
                        firstSeen: now,
                        lastSeen: now,
                        isOnline: true,
                        isNew: isBrandNew
                    )
                    upsertScannedDevice(newDevice, into: &devices)
                    DeviceStore.upsert(newDevice, in: context)
                    if isBrandNew && appState.notificationsEnabled {
                        Task { await NotificationService.shared.notifyNewDevice(newDevice) }
                    }
                }
                try? context.save()
            }
        }
    }

    private func upsertScannedDevice(_ incoming: ScannedDevice, into list: inout [ScannedDevice]) {
        let mac = incoming.mac?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidMAC = ARPTableService.isValidMAC(mac)
        let hostname = incoming.hostname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDistinctHost = isDistinctHostname(hostname)

        var matchIndex: Int?
        // 1. Match by valid MAC address (authoritative, survives IP changes)
        if hasValidMAC, let mac {
            matchIndex = list.firstIndex(where: {
                guard let existingMAC = $0.mac else { return false }
                return existingMAC.caseInsensitiveCompare(mac) == .orderedSame
            })
        }
        // 2. Fallback match by distinct hostname (for iOS where MAC is restricted)
        if matchIndex == nil, hasDistinctHost, let hostname {
            matchIndex = list.firstIndex(where: {
                guard let existingHost = $0.hostname, isDistinctHostname(existingHost) else { return false }
                return existingHost.caseInsensitiveCompare(hostname) == .orderedSame
            })
        }
        // 3. Fallback match by IP address
        if matchIndex == nil {
            matchIndex = list.firstIndex(where: { $0.ip == incoming.ip })
        }

        if let index = matchIndex {
            let old = list[index]
            // If device changed its IP address, purge any other stale entry in list at incoming.ip
            if old.ip != incoming.ip {
                list.removeAll(where: { $0.ip == incoming.ip && $0.id != old.id })
            }
            let merged = ScannedDevice(
                id: incoming.id,
                ip: incoming.ip,
                mac: (hasValidMAC ? mac : nil) ?? incoming.mac ?? old.mac,
                hostname: (incoming.hostname?.isEmpty == false ? incoming.hostname : nil) ?? old.hostname,
                vendor: (incoming.vendor?.isEmpty == false ? incoming.vendor : nil) ?? old.vendor,
                firstSeen: old.firstSeen,
                lastSeen: incoming.lastSeen,
                isOnline: incoming.isOnline,
                isNew: old.isNew
            )
            if let targetIndex = list.firstIndex(where: { $0.id == old.id || (hasValidMAC && $0.mac?.caseInsensitiveCompare(mac!) == .orderedSame) }) {
                list[targetIndex] = merged
            } else {
                list.append(merged)
            }
        } else {
            list.removeAll(where: { $0.ip == incoming.ip })
            list.append(incoming)
        }
    }

    private func isDistinctHostname(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let lower = host.lowercased()
        let generic = ["localhost", "unknown", "broadcasthost", "local"]
        if generic.contains(lower) { return false }
        return true
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
                upsertScannedDevice(device, into: &devices)
                upsertScannedDevice(device, into: &responders)
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
