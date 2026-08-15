//
//  CustomNetworkRange.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import SwiftData

/// A user-defined network range to scan (CIDR or arbitrary start/end), shown in
/// the sidebar. Synced via CloudKit alongside Device metadata.
@Model
final class CustomNetworkRange {
    var name: String
    var cidr: String
    var icon: String
    var sortOrder: Int

    init(name: String, cidr: String, icon: String = "network", sortOrder: Int = 0) {
        self.name = name
        self.cidr = cidr
        self.icon = icon
        self.sortOrder = sortOrder
    }
}
