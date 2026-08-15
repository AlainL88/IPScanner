//
//  ToolsView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

/// Container for the three network tools, presented as a sheet.
struct ToolsView: View {
    @Environment(\.dismiss) private var dismiss
    let initialHost: String
    let initialMAC: String?

    @State private var selectedTool = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tools", selection: $selectedTool) {
                    Text(String(localized: "Ping")).tag(0)
                    Text(String(localized: "Port Scan")).tag(1)
                    Text(String(localized: "Wake on LAN")).tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTool {
                case 0:
                    PingToolView(initialHost: initialHost)
                case 1:
                    PortScanToolView(initialHost: initialHost)
                default:
                    WolToolView(initialMAC: initialMAC ?? "")
                }
            }
            .navigationTitle(String(localized: "Tools"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
    }
}
