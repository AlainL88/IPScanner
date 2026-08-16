//
//  RootView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var appState = AppState()
    @State private var scanViewModel: ScanViewModel?

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            NavigationStack {
                contentColumn
            }
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
                ScanListView(viewModel: scanViewModel, target: target)
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
}
