//
//  SidebarView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \CustomNetworkRange.sortOrder) private var ranges: [CustomNetworkRange]
    @State private var showingAddRange = false

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selection) {
            Section(String(localized: "Networks")) {
                Label(String(localized: "Local network"), systemImage: "wifi")
                    .tag(SidebarItem.network(.localSubnet))
                ForEach(ranges) { range in
                    Label(range.name, systemImage: range.icon)
                        .tag(SidebarItem.network(.custom(range.persistentModelID)))
                }
            }

            Section {
                Label(String(localized: "Scan history"), systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.history)
                Label(String(localized: "Settings"), systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("IPScanner")
        .toolbar {
            ToolbarItem {
                Button {
                    showingAddRange = true
                } label: {
                    Label(String(localized: "Add network"), systemImage: "plus")
                }
                .accessibilityLabel(String(localized: "Add network"))
            }
        }
        .sheet(isPresented: $showingAddRange) {
            NavigationStack {
                CustomRangesView()
            }
        }
    }
}
