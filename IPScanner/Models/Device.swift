//
//  Device.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import SwiftData

/// A device known to the scanner — the cumulative record ("seen over time").
///
/// The personalized fields (custom name/icon, whitelist) live directly on the
/// model rather than on a separate DeviceMetadataOverride relationship so the
/// whole model stays CloudKit-safe (no relationship restrictions). This is the
/// entity that syncs via SwiftData CloudKit.
@Model
final class Device {
    var ipAddress: String
    var macAddress: String?
    var hostname: String?
    var vendor: String?
    var customName: String?
    var customIcon: String?
    var isWhitelisted: Bool
    var firstSeen: Date
    var lastSeen: Date
    var isOnline: Bool

    init(
        ipAddress: String,
        macAddress: String? = nil,
        hostname: String? = nil,
        vendor: String? = nil,
        customName: String? = nil,
        customIcon: String? = nil,
        isWhitelisted: Bool = false,
        firstSeen: Date = .now,
        lastSeen: Date = .now,
        isOnline: Bool = true
    ) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendor = vendor
        self.customName = customName
        self.customIcon = customIcon
        self.isWhitelisted = isWhitelisted
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.isOnline = isOnline
    }

    /// Display name: custom > hostname > IP.
    var displayName: String {
        customName ?? hostname ?? ipAddress
    }

    /// Icon for the row: custom SF Symbol, else inferred from the hostname/IP.
    var effectiveIcon: String {
        customIcon ?? Self.inferredIcon(for: hostname, ip: ipAddress)
    }

    static func inferredIcon(for hostname: String?, ip: String) -> String {
        let name = (hostname ?? "").lowercased()
        if name.contains("apple") || name.contains("iphone") || name.contains("ipad") {
            return "iphone"
        }
        if name.contains("mac") || name.contains("mbp") || name.contains("imac") {
            return "laptopcomputer"
        }
        if name.contains("tv") || name.contains("apple-tv") {
            return "tv"
        }
        if name.contains("printer") {
            return "printer"
        }
        if name.contains("router") || name.contains("nas") {
            return "server.rack"
        }
        return "desktopcomputer"
    }
}
