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
    // Non-optional properties carry declaration-level defaults so the schema is
    // valid for CloudKit (which requires every attribute to be optional or have
    // a default value) regardless of how instances are initialized.
    var ipAddress: String = ""
    var macAddress: String?
    var hostname: String?
    var vendor: String?
    var customName: String?
    var customIcon: String?
    var isWhitelisted: Bool = false
    var firstSeen: Date = Foundation.Date.now
    var lastSeen: Date = Foundation.Date.now
    var isOnline: Bool = true

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
        if name.contains("watch") {
            return "applewatch"
        }
        if name.contains("homepod") {
            return "homepod.fill"
        }
        if name.contains("ipad") {
            return "ipad"
        }
        if name.contains("iphone") {
            return "iphone"
        }
        if name.contains("mac") || name.contains("mbp") || name.contains("imac") || name.contains("macbook") {
            return "laptopcomputer"
        }
        if name.contains("tv") || name.contains("apple-tv") || name.contains("bravia") || name.contains("samsung") || name.contains("lg") {
            return "tv"
        }
        if name.contains("apple") {
            return "iphone"
        }
        if name.contains("printer") || name.contains("brother") || name.contains("epson") || name.contains("canon") || name.contains("hp") {
            return "printer"
        }
        if name.contains("router") || name.contains("gateway") || name.contains("fritz") || name.contains("openwrt") {
            return "wifi.router"
        }
        if name.contains("nas") || name.contains("synology") || name.contains("qnap") || name.contains("truenas") || name.contains("unraid") {
            return "server.rack"
        }
        if name.contains("cam") || name.contains("camera") || name.contains("nvr") || name.contains("reolink") || name.contains("hikvision") {
            return "camera.fill"
        }
        if name.contains("hue") || name.contains("light") || name.contains("shelly") || name.contains("sonoff") || name.contains("tasmota") || name.contains("esphome") || name.contains("tuya") {
            return "lightbulb.fill"
        }
        if name.contains("playstation") || name.contains("ps4") || name.contains("ps5") || name.contains("xbox") || name.contains("nintendo") || name.contains("switch") {
            return "gamecontroller.fill"
        }
        if name.contains("speaker") || name.contains("sonos") || name.contains("bose") {
            return "speaker.wave.2.fill"
        }
        if name.contains("pi") || name.contains("raspberry") {
            return "terminal.fill"
        }
        return "desktopcomputer"
    }
}
