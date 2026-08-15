//
//  Theme.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

/// Row density options for the device list.
enum RowDensity: String, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable
    case spacious

    var id: String { rawValue }

    var rowHeight: CGFloat {
        switch self {
        case .compact: return 44
        case .comfortable: return 60
        case .spacious: return 76
        }
    }

    var label: String {
        switch self {
        case .compact: return String(localized: "Compact")
        case .comfortable: return String(localized: "Comfortable")
        case .spacious: return String(localized: "Spacious")
        }
    }
}

/// Shared design tokens. All colors are adaptive asset-catalog colors so
/// Light/Dark Mode is automatic. Swift symbols for those assets are generated
/// by Xcode (Color.statusOnline, Color.statusOffline, Color.statusNew, ...).
enum Theme {
    static let cornerRadius: CGFloat = 12
    static let smallCornerRadius: CGFloat = 8
    static let spacing: CGFloat = 12
    static let groupedSpacing: CGFloat = 16
}
