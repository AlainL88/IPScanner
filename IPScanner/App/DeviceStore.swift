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
        var device = device
        if device.mac == nil || !ARPTableService.isValidMAC(device.mac) {
            if let liveMAC = ARPTableService.macAddress(for: device.ip), ARPTableService.isValidMAC(liveMAC) {
                let liveVendor = device.vendor ?? OUILookupService.shared.vendorNameSync(forMAC: liveMAC)
                device = ScannedDevice(
                    id: device.id,
                    ip: device.ip,
                    mac: liveMAC,
                    hostname: device.hostname,
                    vendor: liveVendor,
                    firstSeen: device.firstSeen,
                    lastSeen: device.lastSeen,
                    isOnline: device.isOnline,
                    isNew: device.isNew
                )
            }
        }
        let mac = device.mac?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidMAC = ARPTableService.isValidMAC(mac)
        let hostname = device.hostname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDistinctHostname = isDistinctHostname(hostname)

        let allDevices = (try? context.fetch(FetchDescriptor<Device>())) ?? []
        var targetDevice: Device?

        // 1. Match by authoritative MAC address (primary, stable across DHCP changes)
        if hasValidMAC, let mac {
            let matching = allDevices.filter {
                guard let existingMAC = $0.macAddress else { return false }
                return existingMAC.caseInsensitiveCompare(mac) == .orderedSame
            }
            if !matching.isEmpty {
                // If any matching record carries user customization, prefer it as targetDevice
                let customMatch = matching.first(where: {
                    ($0.customName != nil && !$0.customName!.isEmpty) ||
                    ($0.customIcon != nil && !$0.customIcon!.isEmpty) ||
                    $0.isWhitelisted
                })
                let chosen = customMatch ?? matching.first!
                targetDevice = chosen

                // Preserve any custom metadata across duplicates before cleaning them up
                let preservedName = matching.compactMap(\.customName).first(where: { !$0.isEmpty })
                let preservedIcon = matching.compactMap(\.customIcon).first(where: { !$0.isEmpty })
                let preservedWhitelisted = matching.contains(where: \.isWhitelisted)

                if chosen.customName == nil || chosen.customName?.isEmpty == true {
                    chosen.customName = preservedName
                }
                if chosen.customIcon == nil || chosen.customIcon?.isEmpty == true {
                    chosen.customIcon = preservedIcon
                }
                if !chosen.isWhitelisted && preservedWhitelisted {
                    chosen.isWhitelisted = true
                }

                // Clean up any extraneous duplicates with the same MAC
                for duplicate in matching where duplicate.persistentModelID != chosen.persistentModelID {
                    context.delete(duplicate)
                }
            }
        }

        // 2. Match by distinct Hostname / mDNS / Bonjour (useful on iOS when MAC is restricted)
        if targetDevice == nil, hasDistinctHostname, let hostname {
            let matching = allDevices.filter {
                guard let existingHost = $0.hostname?.trimmingCharacters(in: .whitespacesAndNewlines),
                      isDistinctHostname(existingHost) else { return false }
                guard existingHost.caseInsensitiveCompare(hostname) == .orderedSame else { return false }
                // Safeguard: if the persisted device already has an authoritative MAC and incoming does not,
                // do not migrate it to a different IP based solely on hostname.
                if $0.macAddress != nil && !hasValidMAC && $0.ipAddress != device.ip {
                    return false
                }
                return true
            }
            if let customMatch = matching.first(where: {
                ($0.customName != nil && !$0.customName!.isEmpty) ||
                ($0.customIcon != nil && !$0.customIcon!.isEmpty) ||
                $0.isWhitelisted
            }) {
                targetDevice = customMatch
            } else {
                targetDevice = matching.first
            }
        }

        // 3. Fallback: match by IP address, with identity conflict safeguards
        if targetDevice == nil {
            let ip = device.ip
            let candidates = allDevices.filter { $0.ipAddress == ip }
            let customCandidate = candidates.first(where: {
                ($0.customName != nil && !$0.customName!.isEmpty) ||
                ($0.customIcon != nil && !$0.customIcon!.isEmpty) ||
                $0.isWhitelisted
            })
            let chosenCandidate = customCandidate ?? candidates.first

            if let candidate = chosenCandidate {
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
            // If any duplicate record with the same MAC carries customizations, merge them
            if hasValidMAC, let mac {
                let sameMACDuplicates = allDevices.filter {
                    $0.persistentModelID != existing.persistentModelID &&
                    $0.macAddress?.caseInsensitiveCompare(mac) == .orderedSame
                }
                if existing.customName == nil || existing.customName?.isEmpty == true {
                    existing.customName = sameMACDuplicates.compactMap(\.customName).first(where: { !$0.isEmpty })
                }
                if existing.customIcon == nil || existing.customIcon?.isEmpty == true {
                    existing.customIcon = sameMACDuplicates.compactMap(\.customIcon).first(where: { !$0.isEmpty })
                }
                if !existing.isWhitelisted && sameMACDuplicates.contains(where: \.isWhitelisted) {
                    existing.isWhitelisted = true
                }
                for duplicate in sameMACDuplicates {
                    context.delete(duplicate)
                }
            }

            // If the device migrated to a new IP address, resolve any conflicting record at the new IP
            if existing.ipAddress != device.ip {
                let ipCollisions = allDevices.filter { $0.persistentModelID != existing.persistentModelID && $0.ipAddress == device.ip }
                for collision in ipCollisions {
                    if (collision.macAddress == nil || collision.macAddress?.isEmpty == true) &&
                       (collision.customName == nil || collision.customName?.isEmpty == true) &&
                       (collision.customIcon == nil || collision.customIcon?.isEmpty == true) &&
                       !collision.isWhitelisted {
                        context.delete(collision)
                    } else {
                        collision.isOnline = false
                    }
                }
            }

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
            // Clean up any stale uncustomized records without MAC at device.ip before inserting
            let ipCollisions = allDevices.filter { $0.ipAddress == device.ip }
            for collision in ipCollisions {
                if (collision.macAddress == nil || collision.macAddress?.isEmpty == true) &&
                   (collision.customName == nil || collision.customName?.isEmpty == true) &&
                   (collision.customIcon == nil || collision.customIcon?.isEmpty == true) &&
                   !collision.isWhitelisted {
                    context.delete(collision)
                } else {
                    collision.isOnline = false
                }
            }

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
            // If an offline device has no MAC address and no user customizations,
            // purge it so stale mDNS ghost records don't persist in the database.
            if (device.macAddress == nil || device.macAddress?.isEmpty == true) &&
               (device.customName == nil || device.customName?.isEmpty == true) &&
               (device.customIcon == nil || device.customIcon?.isEmpty == true) &&
               !device.isWhitelisted {
                context.delete(device)
            }
        }
        try? context.save()
    }
}
