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

    /// Scans a CIDR range and streams progress + discovered devices.
    public func scan(cidr: String, includeBonjour: Bool = true) -> AsyncStream<ScanEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            let started = Date()
            let progress = ProgressCounter()
            let holder = TaskHolder()

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
                let pingService = PingService(timeout: 1.2)
                let pingResults = await pingService.pingSweep(addresses: addresses.map(\.description), concurrency: 32) { _ in
                    // Live progress: the sweep reports each completion.
                    let done = progress.increment()
                    continuation.yield(.phase(.pinging(completed: done, total: total)))
                }
                let responderIPs = pingResults.filter(\.succeeded).map(\.address)

                // ARP cache gives MAC addresses for hosts that answered.
                continuation.yield(.phase(.arpReading))
                let arpEntries = ARPTableService.read()
                #if DEBUG
                print("[ARP] \(arpEntries.count) entries: \(arpEntries.map { "\($0.ipAddress)=\($0.macAddress ?? "nil")" }.joined(separator: ", "))")
                #endif
                let macByIP = Dictionary(
                    arpEntries.compactMap { entry in entry.macAddress.map { (entry.ipAddress, $0) } },
                    uniquingKeysWith: { a, _ in a }
                )

                // Bonjour gives friendly hostnames (best-effort).
                var hostnameByIP: [String: String] = [:]
                if includeBonjour, !responderIPs.isEmpty {
                    continuation.yield(.phase(.bonjourDiscovery))
                    let bonjour = BonjourDiscoveryService()
                    hostnameByIP = await bonjour.resolveHostnames(for: Set(responderIPs), duration: 2)
                }

                continuation.yield(.phase(.finishing))
                let oui = OUILookupService()
                var devices: [ScannedDevice] = []
                for ip in responderIPs {
                    let mac = macByIP[ip]
                    let vendor: String?
                    if let mac {
                        vendor = await oui.vendorName(forMAC: mac)
                    } else {
                        vendor = nil
                    }
                    let device = ScannedDevice(
                        id: ip,
                        ip: ip,
                        mac: mac,
                        hostname: hostnameByIP[ip],
                        vendor: vendor,
                        firstSeen: started,
                        lastSeen: started,
                        isOnline: true,
                        isNew: false
                    )
                    devices.append(device)
                    continuation.yield(.device(device))
                    #if DEBUG
                    print("[SCAN] device \(device.ip) mac=\(device.mac ?? "nil") hostname=\(device.hostname ?? "nil")")
                    #endif
                }

                continuation.yield(.completed(
                    summary: ScanSummary(
                        totalResponded: devices.count,
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
