//
//  PingToolView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

struct PingToolView: View {
    @State private var host: String
    @State private var isPinging = false
    @State private var result: PingResult?

    init(initialHost: String) {
        _host = State(initialValue: initialHost)
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "IP Address"), text: $host)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                Button {
                    ping()
                } label: {
                    HStack {
                        if isPinging {
                            ProgressView()
                        } else {
                            Label(String(localized: "Ping"), systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    }
                }
                .disabled(host.isEmpty || isPinging)
            }

            if let result {
                Section(String(localized: "Result")) {
                    LabeledContent(
                        String(localized: "Status"),
                        value: result.succeeded ? String(localized: "Online") : (result.errorDescription ?? String(localized: "Offline"))
                    )
                    if let rtt = result.roundTripTime {
                        LabeledContent("RTT", value: String(format: "%.1f ms", rtt * 1000))
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Ping"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func ping() {
        isPinging = true
        result = nil
        let host = self.host
        Task {
            let service = PingService(timeout: 2)
            let pingResult = await service.ping(host: host)
            await MainActor.run {
                result = pingResult
                isPinging = false
            }
        }
    }
}
