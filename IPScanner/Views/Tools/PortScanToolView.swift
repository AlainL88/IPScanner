//
//  PortScanToolView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

struct PortScanToolView: View {
    @State private var host: String
    @State private var portsText: String
    @State private var isScanning = false
    @State private var openPorts: [OpenPort] = []

    init(initialHost: String) {
        _host = State(initialValue: initialHost)
        _portsText = State(initialValue: PortScanConfiguration.common.map(String.init).joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "IP Address"), text: $host)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                TextField(String(localized: "Ports"), text: $portsText)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button {
                    scan()
                } label: {
                    HStack {
                        if isScanning {
                            ProgressView()
                        } else {
                            Label(String(localized: "Scan ports"), systemImage: "network")
                        }
                    }
                }
                .disabled(host.isEmpty || isScanning)
            }

            Section(String(localized: "Result")) {
                if isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(String(localized: "Scanning…"))
                            .foregroundStyle(.secondary)
                    }
                } else if !openPorts.isEmpty {
                    ForEach(openPorts, id: \.port) { port in
                        LabeledContent(String(port.port), value: port.serviceName ?? "—")
                    }
                } else if !portsText.isEmpty && !isScanning {
                    Text(String(localized: "All ports closed"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "Port Scan"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func scan() {
        let parsed = portsText
            .split(separator: ",")
            .compactMap { UInt16($0.trimmingCharacters(in: .whitespaces)) }
        guard !parsed.isEmpty else { return }

        isScanning = true
        openPorts = []
        let host = self.host
        let configuration = PortScanConfiguration(ports: parsed)

        Task {
            let service = PortScanService()
            let ports = await service.scan(host: host, configuration: configuration) { _ in }
            await MainActor.run {
                openPorts = ports
                isScanning = false
            }
        }
    }
}
