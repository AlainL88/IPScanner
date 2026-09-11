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
    /// falling back to IP address. Preserves any custom metadata (name/icon/whitelist).
    static func upsert(_ device: ScannedDevice, in context: ModelContext) {
        let mac = device.mac?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidMAC = ARPTableService.isValidMAC(mac)

        var targetDevice: Device?

        if hasValidMAC, let mac {
            let allDevices = (try? context.fetch(FetchDescriptor<Device>())) ?? []
            targetDevice = allDevices.first(where: {
                guard let existingMAC = $0.macAddress else { return false }
                return existingMAC.caseInsensitiveCompare(mac) == .orderedSame
            })
        }

        if targetDevice == nil {
            let ip = device.ip
            let request = FetchDescriptor<Device>(
                predicate: #Predicate { $0.ipAddress == ip }
            )
            targetDevice = (try? context.fetch(request))?.first
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
