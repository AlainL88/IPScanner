//
//  AppState.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import SwiftUI
import SwiftData
import Observation

// MARK: - Supporting types

enum SortKey: String, CaseIterable, Identifiable, Sendable {
    case name
    case ip
    case mac
    case lastSeen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return String(localized: "Name")
        case .ip: return String(localized: "IP")
        case .mac: return String(localized: "MAC")
        case .lastSeen: return String(localized: "Last seen")
        }
    }
}

enum DeviceColumn: String, CaseIterable, Identifiable, Sendable {
    case ip
    case mac
    case hostname
    case vendor
    case lastSeen
    case status

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ip: return String(localized: "IP")
        case .mac: return String(localized: "MAC")
        case .hostname: return String(localized: "Hostname")
        case .vendor: return String(localized: "Vendor")
        case .lastSeen: return String(localized: "Last seen")
        case .status: return String(localized: "Status")
        }
    }
}

enum NetworkTarget: Hashable, Sendable {
    /// The primary local subnet discovered at runtime.
    case localSubnet
    /// A user-defined CustomNetworkRange, referenced by its SwiftData identifier.
    case custom(PersistentIdentifier)
}

enum SidebarItem: Hashable {
    case network(NetworkTarget)
    case history
    case settings
}

// MARK: - App state

/// Global, app-wide user interface state and preferences. Owned by the root view.
@MainActor
@Observable
final class AppState {
    var selection: SidebarItem?

    var rowDensity: RowDensity = .comfortable
    var sortKey: SortKey = .name
    var sortAscending = true
    var visibleColumns: Set<DeviceColumn> = [.ip, .mac, .hostname, .vendor, .status]
    var isCumulativeMode = false
    var showOnlyNew = false
    var notificationsEnabled = false
    var backgroundScanEnabled = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadPreferences()
    }

    func loadPreferences() {
        rowDensity = RowDensity(rawValue: defaults.string(forKey: Keys.rowDensity) ?? "") ?? .comfortable
        sortKey = SortKey(rawValue: defaults.string(forKey: Keys.sortKey) ?? "") ?? .name
        sortAscending = defaults.object(forKey: Keys.sortAscending) as? Bool ?? true
        visibleColumns = Set((defaults.stringArray(forKey: Keys.visibleColumns) ?? []).compactMap(DeviceColumn.init(rawValue:)))
        isCumulativeMode = defaults.bool(forKey: Keys.cumulativeMode)
        showOnlyNew = defaults.bool(forKey: Keys.showOnlyNew)
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        backgroundScanEnabled = defaults.bool(forKey: Keys.backgroundScanEnabled)
    }

    func persist() {
        defaults.set(rowDensity.rawValue, forKey: Keys.rowDensity)
        defaults.set(sortKey.rawValue, forKey: Keys.sortKey)
        defaults.set(sortAscending, forKey: Keys.sortAscending)
        defaults.set(visibleColumns.map(\.rawValue), forKey: Keys.visibleColumns)
        defaults.set(isCumulativeMode, forKey: Keys.cumulativeMode)
        defaults.set(showOnlyNew, forKey: Keys.showOnlyNew)
        defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        defaults.set(backgroundScanEnabled, forKey: Keys.backgroundScanEnabled)
    }

    private enum Keys {
        static let rowDensity = "pref.rowDensity"
        static let sortKey = "pref.sortKey"
        static let sortAscending = "pref.sortAscending"
        static let visibleColumns = "pref.visibleColumns"
        static let cumulativeMode = "pref.cumulativeMode"
        static let showOnlyNew = "pref.showOnlyNew"
        static let notificationsEnabled = "pref.notificationsEnabled"
        static let backgroundScanEnabled = "pref.backgroundScanEnabled"
    }
}
