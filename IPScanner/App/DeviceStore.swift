//
//  DeviceStore.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import SwiftData

/// Shared SwiftData upsert helpers for `Device`, used by both the foreground
/// scan flow and the background refresh task.
@MainActor
enum DeviceStore {
    /// Inserts or updates a Device for the given snapshot.
    /// Prefers matching by MAC address when available (stable across IP changes),
    /// then by distinct hostname/mDNS (for iOS where MAC is restricted),
    /// falling back to IP address with collision safeguards. Preserves any custom metadata.
    static func upsert(_ device: ScannedDevice, in context: ModelContext) {
        let mac = device.mac?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidMAC = ARPTableService.isValidMAC(mac)
        let hostname = device.hostname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDistinctHostname = isDistinctHostname(hostname)

        let allDevices = (try? context.fetch(FetchDescriptor<Device>())) ?? []
        var targetDevice: Device?

        // 1. Match by authoritative MAC address (primary, stable across DHCP changes)
        if hasValidMAC, let mac {
            targetDevice = allDevices.first(where: {
                guard let existingMAC = $0.macAddress else { return false }
                return existingMAC.caseInsensitiveCompare(mac) == .orderedSame
            })
        }

        // 2. Match by distinct Hostname / mDNS / Bonjour (useful on iOS when MAC is restricted)
        if targetDevice == nil, hasDistinctHostname, let hostname {
            targetDevice = allDevices.first(where: {
                guard let existingHost = $0.hostname?.trimmingCharacters(in: .whitespacesAndNewlines),
                      isDistinctHostname(existingHost) else { return false }
                return existingHost.caseInsensitiveCompare(hostname) == .orderedSame
            })
        }

        // 3. Fallback: match by IP address, with identity conflict safeguards
        if targetDevice == nil {
            let ip = device.ip
            if let candidate = allDevices.first(where: { $0.ipAddress == ip }) {
                let macConflict: Bool = {
                    guard hasValidMAC, let mac, let candMAC = candidate.macAddress, ARPTableService.isValidMAC(candMAC) else {
                        return false
                    }
                    return candMAC.caseInsensitiveCompare(mac) != .orderedSame
                }()

                let hostConflict: Bool = {
                    guard hasDistinctHostname, let hostname,
                          let candHost = candidate.hostname, isDistinctHostname(candHost) else {
                        return false
                    }
                    return candHost.caseInsensitiveCompare(hostname) != .orderedSame
                }()

                if macConflict || hostConflict {
                    candidate.isOnline = false
                } else {
                    targetDevice = candidate
                }
            }
        }

        if let existing = targetDevice {
            existing.ipAddress = device.ip
            if hasValidMAC, let mac {
                existing.macAddress = mac
            }
            if let hostname = device.hostname, !hostname.isEmpty {
                existing.hostname = hostname
            }
            if let vendor = device.vendor, !vendor.isEmpty {
                existing.vendor = vendor
            }
            existing.lastSeen = device.lastSeen
            existing.isOnline = device.isOnline
        } else {
            context.insert(
                Device(
                    ipAddress: device.ip,
                    macAddress: hasValidMAC ? mac : device.mac,
                    hostname: device.hostname,
                    vendor: device.vendor,
                    firstSeen: device.firstSeen,
                    lastSeen: device.lastSeen,
                    isOnline: device.isOnline
                )
            )
        }
    }

    /// Helper to identify non-generic hostnames
    private static func isDistinctHostname(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let lower = host.lowercased()
        let generic = ["localhost", "unknown", "broadcasthost", "local"]
        if generic.contains(lower) { return false }
        return true
    }

    /// Marks every device that wasn't seen in the latest sweep as offline
    /// (used to end the cumulative-mode "online" state).
    static func markOffline(excluding seenIPs: Set<String>, in context: ModelContext) {
        let request = FetchDescriptor<Device>()
        guard let devices = try? context.fetch(request) else { return }
        for device in devices where device.isOnline && !seenIPs.contains(device.ipAddress) {
            device.isOnline = false
        }
        try? context.save()
    }
}
