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
    /// Inserts or updates a Device for the given snapshot. Preserves any custom
    /// metadata (name/icon/whitelist) on existing records.
    static func upsert(_ device: ScannedDevice, in context: ModelContext) {
        let ip = device.ip
        let request = FetchDescriptor<Device>(
            predicate: #Predicate { $0.ipAddress == ip }
        )
        if let existing = (try? context.fetch(request))?.first {
            existing.macAddress = device.mac ?? existing.macAddress
            existing.hostname = device.hostname ?? existing.hostname
            existing.vendor = device.vendor ?? existing.vendor
            existing.lastSeen = device.lastSeen
            existing.isOnline = device.isOnline
        } else {
            context.insert(
                Device(
                    ipAddress: device.ip,
                    macAddress: device.mac,
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
