//
//  ScanSession.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import SwiftData

/// A point-in-time snapshot of one scan, stored locally (not synced) so history
/// stays private and compact. Devices are stored as Codable value snapshots
/// instead of relationships, which keeps the model simple and CloudKit-safe.
@Model
final class ScanSession {
    var startedAt: Date
    var cidr: String
    var duration: TimeInterval
    var deviceSnapshots: [DeviceSnapshot]

    init(
        startedAt: Date = .now,
        cidr: String,
        duration: TimeInterval = 0,
        deviceSnapshots: [DeviceSnapshot] = []
    ) {
        self.startedAt = startedAt
        self.cidr = cidr
        self.duration = duration
        self.deviceSnapshots = deviceSnapshots
    }
}

struct DeviceSnapshot: Codable, Hashable, Sendable {
    var ip: String
    var mac: String?
    var hostname: String?
    var vendor: String?
    var isOnline: Bool
    var lastSeen: Date

    init(
        ip: String,
        mac: String? = nil,
        hostname: String? = nil,
        vendor: String? = nil,
        isOnline: Bool = true,
        lastSeen: Date = .now
    ) {
        self.ip = ip
        self.mac = mac
        self.hostname = hostname
        self.vendor = vendor
        self.isOnline = isOnline
        self.lastSeen = lastSeen
    }
}
