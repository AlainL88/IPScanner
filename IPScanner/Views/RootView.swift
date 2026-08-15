//
//  RootView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var appState = AppState()
    @State private var scanViewModel: ScanViewModel?
    @State private var selectedDeviceIP: String?

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .environment(appState)
        .task {
            if scanViewModel == nil {
                scanViewModel = ScanViewModel(context: context, appState: appState)
            }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch appState.selection {
        case .network(let target):
            if let scanViewModel {
                ScanListView(viewModel: scanViewModel, target: target, selectedDeviceIP: $selectedDeviceIP)
            }
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        case .none:
            ContentUnavailableView(
                String(localized: "Networks"),
                systemImage: "network",
                description: Text(String(localized: "Select a network to scan"))
            )
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let ip = selectedDeviceIP,
           let scanViewModel,
           let device = scanViewModel.devices.first(where: { $0.ip == ip }) {
            DeviceDetailView(device: device, viewModel: scanViewModel)
        } else {
            ContentUnavailableView(
                String(localized: "Select a device"),
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("")
            )
        }
    }
}
