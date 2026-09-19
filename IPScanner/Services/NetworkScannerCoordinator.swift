//
//  NetworkScannerCoordinator.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//
//  Orchestrates a full scan: ICMP ping sweep -> ARP MAC enrichment -> Bonjour
//  hostname enrichment -> OUI vendor lookup. Streams progress and results to the
//  UI via an AsyncStream.

import Foundation

/// A snapshot of a device found on the network.
public struct ScannedDevice: Sendable, Hashable, Identifiable {
    public let id: String // the IP address
    public let ip: String
    public let mac: String?
    public let hostname: String?
    public let vendor: String?
    public let firstSeen: Date
    public let lastSeen: Date
    public let isOnline: Bool
    /// Set by the view model based on persisted metadata / whitelist.
    public var isNew: Bool

    public init(
        id: String,
        ip: String,
        mac: String?,
        hostname: String?,
        vendor: String?,
        firstSeen: Date,
        lastSeen: Date,
        isOnline: Bool,
        isNew: Bool
    ) {
        self.id = id
        self.ip = ip
        self.mac = mac
        self.hostname = hostname
        self.vendor = vendor
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.isOnline = isOnline
        self.isNew = isNew
    }
}

public enum ScanPhase: Sendable, Equatable {
    case idle
    case subnetDetection
    case pinging(completed: Int, total: Int)
    case arpReading
    case bonjourDiscovery
    case finishing
}

public enum ScanEvent: Sendable {
    case phase(ScanPhase)
    case device(ScannedDevice)
    case completed(summary: ScanSummary)
}

public struct ScanSummary: Sendable, Hashable {
    public let totalResponded: Int
    public let duration: TimeInterval
    public let started: Date

    public init(totalResponded: Int, duration: TimeInterval, started: Date) {
        self.totalResponded = totalResponded
        self.duration = duration
        self.started = started
    }
}

public actor NetworkScannerCoordinator {
    public init() {}

    /// Scans a CIDR range and streams progress + discovered devices in real time.
    public func scan(cidr: String, includeBonjour: Bool = true) -> AsyncStream<ScanEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let started = Date()
            let progress = ProgressCounter()
            let holder = TaskHolder()
            let store = DiscoveredDevicesStore(started: started)

            continuation.yield(.phase(.subnetDetection))

            let addresses = IPv4CIDR.hostAddresses(cidr, maxHosts: 2048)
            let total = addresses.count

            guard total > 0 else {
                continuation.yield(.completed(summary: ScanSummary(totalResponded: 0, duration: 0, started: started)))
                continuation.finish()
                return
            }

            continuation.yield(.phase(.pinging(completed: 0, total: total)))

            holder.task = Task {
                let targetAddressStrings = addresses.map(\.description)
                let targetIPSet = Set(targetAddressStrings)
                let oui = OUILookupService()
                let pingService = PingService(timeout: 1.2)
                let bonjour = BonjourDiscoveryService()
                let bonjourTask = Task { () -> [String: String] in
                    guard includeBonjour else { return [:] }
                    return await bonjour.resolveHostnames(for: targetIPSet, duration: 5.0)
                }

                // 1. Concurrent ICMP ping sweep with immediate streaming as IPs respond.
                _ = await pingService.pingSweep(addresses: targetAddressStrings, concurrency: 32) { result in
                    let done = progress.increment()
                    continuation.yield(.phase(.pinging(completed: done, total: total)))

                    if result.succeeded {
                        let ip = result.address
                        let primaryIface = SubnetService.primaryIPv4Interface()
                        var mac = ARPTableService.macAddress(for: ip)
                        if ip == primaryIface?.ipAddress && !ARPTableService.isValidMAC(mac) {
                            mac = primaryIface?.hardwareAddress
                        }
                        let initialDevice = store.update(ip: ip, mac: mac)
                        continuation.yield(.device(initialDevice))

                        if let mac, ARPTableService.isValidMAC(mac) {
                            Task {
                                if let vendor = await oui.vendorName(forMAC: mac) {
                                    let enriched = store.update(ip: ip, mac: mac, vendor: vendor)
                                    continuation.yield(.device(enriched))
                                }
                            }
                        }
                    }
                }

                guard !Task.isCancelled else {
                    bonjourTask.cancel()
                    continuation.finish()
                    return
                }

                // 2. ARP Table discovery & enrichment:
                // Captures active hosts that replied to Layer 2 ARP during the ping sweep
                // (crucial for macOS hosts with stealth mode/firewall and IoT devices that drop ICMP ping).
                continuation.yield(.phase(.arpReading))
                let arpEntries = ARPTableService.read()
                let targetARPEntries = arpEntries.filter { entry in
                    guard let mac = entry.macAddress, ARPTableService.isValidMAC(mac) else { return false }
                    return targetIPSet.contains(entry.ipAddress)
                }

                for entry in targetARPEntries {
                    guard let mac = entry.macAddress else { continue }
                    let ip = entry.ipAddress
                    let vendor = await oui.vendorName(forMAC: mac)
                    let device = store.update(ip: ip, mac: mac, vendor: vendor)
                    continuation.yield(.device(device))
                }

                guard !Task.isCancelled else {
                    bonjourTask.cancel()
                    continuation.finish()
                    return
                }

                // 3. Fast TCP probe fallback for hosts that did not respond to ICMP ping or ARP
                let discoveredIPs = Set(store.all().map(\.ip))
                let remainingIPs = targetAddressStrings.filter { !discoveredIPs.contains($0) }
                if !remainingIPs.isEmpty {
                    await withTaskGroup(of: String?.self) { group in
                        for ip in remainingIPs {
                            group.addTask {
                                if await PortScanService.isHostReachable(host: ip, timeout: 0.3) {
                                    return ip
                                }
                                return nil
                            }
                        }
                        for await activeIP in group {
                            if let activeIP {
                                let mac = ARPTableService.macAddress(for: activeIP)
                                let vendor = (mac != nil && ARPTableService.isValidMAC(mac)) ? await oui.vendorName(forMAC: mac!) : nil
                                let device = store.update(ip: activeIP, mac: mac, vendor: vendor)
                                continuation.yield(.device(device))
                            }
                        }
                    }
                }

                guard !Task.isCancelled else {
                    bonjourTask.cancel()
                    continuation.finish()
                    return
                }

                // 4. Bonjour / mDNS discovery:
                // Active mDNS hosts are verified alive on the network (e.g. Apple Macs, iOS devices, AirPlay receivers).
                if includeBonjour {
                    continuation.yield(.phase(.bonjourDiscovery))
                    let bonjourHostnames = await bonjourTask.value
                    let primaryIface = SubnetService.primaryIPv4Interface()
                    for (ip, rawHostname) in bonjourHostnames {
                        if targetIPSet.contains(ip) {
                            let hostname = DNSResolver.cleanHostname(rawHostname)
                            if let existing = store.get(ip) {
                                let device = store.update(ip: ip, hostname: hostname)
                                continuation.yield(.device(device))
                            } else {
                                // For a new IP found ONLY via Bonjour:
                                // Verify it actually exists on the network (not a stale mDNS cache entry).
                                let isLocalHost = (ip == primaryIface?.ipAddress)
                                var mac = ARPTableService.macAddress(for: ip)
                                if isLocalHost && !ARPTableService.isValidMAC(mac) {
                                    mac = primaryIface?.hardwareAddress
                                }
                                let hasValidMAC = (mac != nil && ARPTableService.isValidMAC(mac))

                                if hasValidMAC || isLocalHost {
                                    let vendor = hasValidMAC ? await oui.vendorName(forMAC: mac!) : nil
                                    let device = store.update(ip: ip, mac: mac, hostname: hostname, vendor: vendor)
                                    continuation.yield(.device(device))
                                } else {
                                    // Device has no MAC in ARP. Check if it actually responds to ICMP ping or TCP probe
                                    var isReachable = await pingService.ping(host: ip, retries: 0, timeout: 0.25).succeeded
                                    if !isReachable {
                                        isReachable = await PortScanService.isHostReachable(host: ip, timeout: 0.25)
                                    }
                                    if isReachable {
                                        let updatedMAC = ARPTableService.macAddress(for: ip)
                                        let vendor = (updatedMAC != nil && ARPTableService.isValidMAC(updatedMAC)) ? await oui.vendorName(forMAC: updatedMAC!) : nil
                                        let device = store.update(ip: ip, mac: updatedMAC, hostname: hostname, vendor: vendor)
                                        continuation.yield(.device(device))
                                    }
                                }
                            }
                        }
                    }
                }

                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                // 5. Reverse DNS fallback for devices missing a hostname (concurrent):
                let discovered = store.all()
                let missingHostnameIPs = discovered.filter { $0.hostname == nil || $0.hostname?.isEmpty == true }.map(\.ip)
                if !missingHostnameIPs.isEmpty {
                    await withTaskGroup(of: (ip: String, hostname: String)?.self) { group in
                        for ip in missingHostnameIPs {
                            group.addTask {
                                if let reverseName = DNSResolver.reverseLookup(ip: ip) {
                                    return (ip, reverseName)
                                }
                                return nil
                            }
                        }
                        for await result in group {
                            if let (ip, reverseName) = result {
                                let updated = store.update(ip: ip, hostname: reverseName)
                                continuation.yield(.device(updated))
                            }
                        }
                    }
                }

                // 6. Local host identification fallback:
                if let primaryIface = SubnetService.primaryIPv4Interface() {
                    let localIP = primaryIface.ipAddress
                    var localMAC = ARPTableService.macAddress(for: localIP)
                    if !ARPTableService.isValidMAC(localMAC) {
                        localMAC = primaryIface.hardwareAddress
                    }
                    let localVendor = (localMAC != nil && ARPTableService.isValidMAC(localMAC)) ? await oui.vendorName(forMAC: localMAC!) : nil
                    #if os(macOS)
                    let localName = Host.current().localizedName ?? DNSResolver.cleanHostname(ProcessInfo.processInfo.hostName)
                    #else
                    let localName = DNSResolver.cleanHostname(ProcessInfo.processInfo.hostName)
                    #endif
                    let updated = store.update(ip: localIP, mac: localMAC, hostname: localName, vendor: localVendor)
                    continuation.yield(.device(updated))
                }

                continuation.yield(.phase(.finishing))

                continuation.yield(.completed(
                    summary: ScanSummary(
                        totalResponded: store.count,
                        duration: Date().timeIntervalSince(started),
                        started: started
                    )
                ))
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                holder.task?.cancel()
            }
        }
    }
}

/// Thread-safe accumulator for discovered scanned devices during a sweep.
private final class DiscoveredDevicesStore: @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [String: ScannedDevice] = [:]
    private let started: Date

    init(started: Date) {
        self.started = started
    }

    func update(
        ip: String,
        mac: String? = nil,
        hostname: String? = nil,
        vendor: String? = nil
    ) -> ScannedDevice {
        lock.lock()
        defer { lock.unlock() }

        let existing = devices[ip]
        let finalMAC = (mac != nil && ARPTableService.isValidMAC(mac)) ? mac : (existing?.mac)
        let finalHostname = (hostname != nil && !hostname!.isEmpty) ? hostname : (existing?.hostname)
        let finalVendor = (vendor != nil && !vendor!.isEmpty) ? vendor : (existing?.vendor)

        // Deduplicate: if another IP in store had the same valid MAC, remove the older entry
        if let finalMAC, ARPTableService.isValidMAC(finalMAC) {
            let staleIPs = devices.compactMap { (key, value) -> String? in
                guard key != ip, let existingMAC = value.mac, ARPTableService.isValidMAC(existingMAC) else { return nil }
                return existingMAC.caseInsensitiveCompare(finalMAC) == .orderedSame ? key : nil
            }
            for staleIP in staleIPs {
                devices.removeValue(forKey: staleIP)
            }
        }

        let device = ScannedDevice(
            id: ip,
            ip: ip,
            mac: finalMAC,
            hostname: finalHostname,
            vendor: finalVendor,
            firstSeen: existing?.firstSeen ?? started,
            lastSeen: started,
            isOnline: true,
            isNew: false
        )
        devices[ip] = device
        return device
    }

    func get(_ ip: String) -> ScannedDevice? {
        lock.lock()
        defer { lock.unlock() }
        return devices[ip]
    }

    func all() -> [ScannedDevice] {
        lock.lock()
        defer { lock.unlock() }
        return Array(devices.values)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return devices.count
    }
}

/// Holds a reference to the scan task so the AsyncStream can cancel it without
/// capturing a mutable local in a @Sendable closure.
private final class TaskHolder: @unchecked Sendable {
    var task: Task<Void, Never>?
}

/// Lock-protected counter used for cross-thread progress reporting.
private final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        value += 1
        let current = value
        lock.unlock()
        return current
    }
}
