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
                // Sort matching so that records with custom metadata and more recent edits come first
                let sortedMatching = matching.sorted { a, b in
                    let aHasCustom = (a.customName?.isEmpty == false) || (a.customIcon?.isEmpty == false) || a.isWhitelisted
                    let bHasCustom = (b.customName?.isEmpty == false) || (b.customIcon?.isEmpty == false) || b.isWhitelisted
                    if aHasCustom != bHasCustom {
                        return aHasCustom && !bHasCustom
                    }
                    return a.lastSeen > b.lastSeen
                }
                let chosen = sortedMatching.first!
                targetDevice = chosen

                // Preserve any custom metadata across duplicates before cleaning them up
                let preservedName = sortedMatching.compactMap(\.customName).first(where: { !$0.isEmpty })
                let preservedIcon = sortedMatching.compactMap(\.customIcon).first(where: { !$0.isEmpty })
                let preservedWhitelisted = matching.contains(where: \.isWhitelisted)

                chosen.customName = preservedName
                chosen.customIcon = preservedIcon
                if preservedWhitelisted {
                    chosen.isWhitelisted = true
                }
                chosen.firstSeen = matching.map(\.firstSeen).min() ?? chosen.firstSeen
                chosen.lastSeen = max(chosen.lastSeen, matching.map(\.lastSeen).max() ?? chosen.lastSeen)

                // Clean up any extraneous duplicates with the same MAC
                for duplicate in matching where duplicate.persistentModelID != chosen.persistentModelID {
                    context.delete(duplicate)
                }
            }
        }

        // 2. Match by distinct Hostname / mDNS / Bonjour (when MAC is not yet available)
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
                    // Only consider host conflict when the candidate already has an authoritative MAC
                    // and incoming has a distinctly different hostname without a matching MAC.
                    guard candidate.macAddress != nil && !hasValidMAC,
                          hasDistinctHostname, let hostname,
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
                if !sameMACDuplicates.isEmpty {
                    let allSameMAC = [existing] + sameMACDuplicates
                    let sortedSameMAC = allSameMAC.sorted { a, b in
                        let aHasCustom = (a.customName?.isEmpty == false) || (a.customIcon?.isEmpty == false) || a.isWhitelisted
                        let bHasCustom = (b.customName?.isEmpty == false) || (b.customIcon?.isEmpty == false) || b.isWhitelisted
                        if aHasCustom != bHasCustom {
                            return aHasCustom && !bHasCustom
                        }
                        return a.lastSeen > b.lastSeen
                    }
                    if existing.customName == nil || existing.customName?.isEmpty == true {
                        existing.customName = sortedSameMAC.compactMap(\.customName).first(where: { !$0.isEmpty })
                    }
                    if existing.customIcon == nil || existing.customIcon?.isEmpty == true {
                        existing.customIcon = sortedSameMAC.compactMap(\.customIcon).first(where: { !$0.isEmpty })
                    }
                    if allSameMAC.contains(where: \.isWhitelisted) {
                        existing.isWhitelisted = true
                    }
                    for duplicate in sameMACDuplicates {
                        context.delete(duplicate)
                    }
                }
            }

            // Also clean up any un-MAC'd duplicate records at the same IP
            let sameIPDuplicates = allDevices.filter {
                $0.persistentModelID != existing.persistentModelID &&
                $0.ipAddress == device.ip &&
                ($0.macAddress == nil || $0.macAddress?.isEmpty == true)
            }
            for dup in sameIPDuplicates {
                if existing.customName == nil || existing.customName?.isEmpty == true {
                    existing.customName = dup.customName
                }
                if existing.customIcon == nil || existing.customIcon?.isEmpty == true {
                    existing.customIcon = dup.customIcon
                }
                if dup.isWhitelisted {
                    existing.isWhitelisted = true
                }
                context.delete(dup)
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

    /// Consolidates and optimizes the persistent database:
    /// 1. Merges all duplicate records sharing the same MAC address, preserving the newest customName,
    ///    customIcon, whitelist status, and earliest/latest dates, deleting extra copies.
    /// 2. Merges records sharing the same IP address where one has an authoritative MAC and the other has no MAC.
    /// 3. Purges stale "ghost" devices that have no user customizations (no customName, no customIcon,
    ///    not whitelisted) and are currently offline.
    /// Returns the number of redundant / stale records removed.
    @discardableResult
    static func consolidateDatabase(in context: ModelContext, purgeOfflineUncustomized: Bool = true) -> Int {
        let allDevices = (try? context.fetch(FetchDescriptor<Device>())) ?? []
        var deletedCount = 0
        var deletedIDs = Set<PersistentIdentifier>()

        // 1. Group by valid MAC address
        var macGroups: [String: [Device]] = [:]
        for device in allDevices {
            if let rawMAC = device.macAddress?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
               ARPTableService.isValidMAC(rawMAC) {
                macGroups[rawMAC, default: []].append(device)
            }
        }

        for (_, group) in macGroups where group.count > 1 {
            let sorted = group.sorted { a, b in
                let aHasCustom = (a.customName?.isEmpty == false) || (a.customIcon?.isEmpty == false) || a.isWhitelisted
                let bHasCustom = (b.customName?.isEmpty == false) || (b.customIcon?.isEmpty == false) || b.isWhitelisted
                if aHasCustom != bHasCustom {
                    return aHasCustom && !bHasCustom
                }
                return a.lastSeen > b.lastSeen
            }
            let chosen = sorted.first!
            let preservedName = sorted.compactMap(\.customName).first(where: { !$0.isEmpty })
            let preservedIcon = sorted.compactMap(\.customIcon).first(where: { !$0.isEmpty })
            let preservedWhitelisted = group.contains(where: \.isWhitelisted)

            chosen.customName = preservedName
            chosen.customIcon = preservedIcon
            if preservedWhitelisted {
                chosen.isWhitelisted = true
            }
            chosen.firstSeen = group.map(\.firstSeen).min() ?? chosen.firstSeen
            chosen.lastSeen = max(chosen.lastSeen, group.map(\.lastSeen).max() ?? chosen.lastSeen)

            for dup in group where dup.persistentModelID != chosen.persistentModelID {
                context.delete(dup)
                deletedIDs.insert(dup.persistentModelID)
                deletedCount += 1
            }
        }

        // 2. Filter remaining devices to merge un-MAC'd duplicates at the same IP
        let remaining = (try? context.fetch(FetchDescriptor<Device>()))?.filter { !deletedIDs.contains($0.persistentModelID) } ?? []
        var ipGroups: [String: [Device]] = [:]
        for dev in remaining {
            ipGroups[dev.ipAddress, default: []].append(dev)
        }

        for (_, group) in ipGroups where group.count > 1 {
            if let authoritative = group.first(where: { $0.macAddress != nil && ARPTableService.isValidMAC($0.macAddress) }) {
                for dup in group where dup.persistentModelID != authoritative.persistentModelID {
                    if dup.macAddress == nil || !ARPTableService.isValidMAC(dup.macAddress) {
                        if authoritative.customName == nil || authoritative.customName?.isEmpty == true {
                            authoritative.customName = dup.customName
                        }
                        if authoritative.customIcon == nil || authoritative.customIcon?.isEmpty == true {
                            authoritative.customIcon = dup.customIcon
                        }
                        if dup.isWhitelisted {
                            authoritative.isWhitelisted = true
                        }
                        context.delete(dup)
                        deletedIDs.insert(dup.persistentModelID)
                        deletedCount += 1
                    }
                }
            }
        }

        // 3. Purge offline records that have zero user customizations
        if purgeOfflineUncustomized {
            let active = (try? context.fetch(FetchDescriptor<Device>()))?.filter { !deletedIDs.contains($0.persistentModelID) } ?? []
            for dev in active {
                let hasCustom = (dev.customName?.isEmpty == false) || (dev.customIcon?.isEmpty == false) || dev.isWhitelisted
                if !hasCustom && !dev.isOnline {
                    context.delete(dev)
                    deletedIDs.insert(dev.persistentModelID)
                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            try? context.save()
        }
        return deletedCount
    }
}
