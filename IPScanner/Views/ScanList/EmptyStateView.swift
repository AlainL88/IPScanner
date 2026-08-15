//
//  EmptyStateView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

struct EmptyStateView: View {
    let startScan: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "No devices found"), systemImage: "wifi.exclamationmark")
        } description: {
            Text(String(localized: "Start scanning to discover devices on your local network."))
        } actions: {
            Button(String(localized: "Start scanning"), action: startScan)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
