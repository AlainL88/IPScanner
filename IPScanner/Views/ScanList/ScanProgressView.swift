//
//  ScanProgressView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

struct ScanProgressView: View {
    let phase: ScanPhase

    var body: some View {
        HStack(spacing: Theme.spacing) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if case .pinging(let completed, let total) = phase, total > 0 {
                    ProgressView(value: Double(completed), total: Double(total))
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch phase {
        case .idle, .subnetDetection, .finishing:
            return String(localized: "Preparing…")
        case .pinging:
            return String(localized: "Scanning…")
        case .arpReading:
            return String(localized: "Reading ARP cache…")
        case .bonjourDiscovery:
            return String(localized: "Discovering services…")
        }
    }
}
