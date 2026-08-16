//
//  ScanListView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI
import SwiftData

struct ScanListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomNetworkRange.sortOrder) private var ranges: [CustomNetworkRange]
    @Query(sort: \Device.ipAddress) private var persistedDevices: [Device]

    let viewModel: ScanViewModel
    let target: NetworkTarget
    @State private var showingTools = false

    /// ip -> persisted Device, for resolving custom names/icons/whitelist.
    private var persistedByIP: [String: Device] {
        Dictionary(persistedDevices.map { ($0.ipAddress, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        Group {
            if viewModel.devices.isEmpty && !viewModel.isScanning {
                EmptyStateView(startScan: viewModel.startScan)
            } else {
                List {
                    if viewModel.isScanning {
                        ScanProgressView(phase: viewModel.phase)
                    }
                    ForEach(viewModel.filteredDevices) { device in
                        let persisted = persistedByIP[device.ip]
                        NavigationLink {
                            DeviceDetailView(device: device, viewModel: viewModel)
                        } label: {
                            DeviceRowView(
                                device: device,
                                displayName: persisted?.customName ?? device.hostname ?? device.ip,
                                icon: persisted?.customIcon ?? Device.inferredIcon(for: device.hostname, ip: device.ip),
                                density: appState.rowDensity,
                                columns: appState.visibleColumns
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(title)
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
        }
        .sheet(isPresented: $showingTools) {
            let host = viewModel.devices.first?.ip ?? ""
            ToolsView(initialHost: host, initialMAC: persistedMAC(for: host))
        }
    }

    private func persistedMAC(for ip: String) -> String? {
        let ip = ip
        let request = FetchDescriptor<Device>(predicate: #Predicate { $0.ipAddress == ip })
        return (try? context.fetch(request))?.first?.macAddress
    }

    private var title: String {
        switch target {
        case .localSubnet:
            return String(localized: "Local network")
        case .custom(let id):
            return ranges.first(where: { $0.persistentModelID == id })?.name ?? String(localized: "Networks")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if viewModel.isScanning {
                Button {
                    viewModel.stopScan()
                } label: {
                    Label(String(localized: "Stop"), systemImage: "stop.fill")
                }
                .accessibilityLabel(String(localized: "Stop"))
            } else {
                Button {
                    viewModel.startScan()
                } label: {
                    Label(String(localized: "Scan"), systemImage: "play.fill")
                }
                .accessibilityLabel(String(localized: "Scan"))
            }
        }

        ToolbarItemGroup {
            Button {
                showingTools = true
            } label: {
                Label(String(localized: "Tools"), systemImage: "wrench.and.screwdriver")
            }
            .accessibilityLabel(String(localized: "Tools"))

            Menu {
                ForEach(SortKey.allCases) { key in
                    Button {
                        appState.sortKey = key
                        appState.persist()
                    } label: {
                        Label(key.label, systemImage: appState.sortKey == key ? "checkmark" : "")
                    }
                }
                Divider()
                Button {
                    appState.sortAscending.toggle()
                    appState.persist()
                } label: {
                    Label(
                        appState.sortAscending ? String(localized: "Ascending") : String(localized: "Descending"),
                        systemImage: appState.sortAscending ? "arrow.up" : "arrow.down"
                    )
                }
            } label: {
                Label(String(localized: "Sort by"), systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel(String(localized: "Sort by"))

            Menu {
                ForEach(DeviceColumn.allCases) { column in
                    Button {
                        if appState.visibleColumns.contains(column) {
                            appState.visibleColumns.remove(column)
                        } else {
                            appState.visibleColumns.insert(column)
                        }
                        appState.persist()
                    } label: {
                        Label(column.label, systemImage: appState.visibleColumns.contains(column) ? "checkmark" : "")
                    }
                }
            } label: {
                Label(String(localized: "Columns"), systemImage: "rectangle.grid.1x2")
            }
            .accessibilityLabel(String(localized: "Column visibility"))

            Menu {
                ForEach(RowDensity.allCases) { density in
                    Button {
                        appState.rowDensity = density
                        appState.persist()
                    } label: {
                        Label(density.label, systemImage: appState.rowDensity == density ? "checkmark" : "")
                    }
                }
            } label: {
                Label(String(localized: "Row size"), systemImage: "textformat.size")
            }
            .accessibilityLabel(String(localized: "Row size"))

            Menu {
                if let csvURL = exportURL(.csv) {
                    ShareLink(item: csvURL, preview: SharePreview(String(localized: "Export CSV"))) {
                        Label(String(localized: "Export CSV"), systemImage: "doc.text")
                    }
                }
                if let jsonURL = exportURL(.json) {
                    ShareLink(item: jsonURL, preview: SharePreview(String(localized: "Export JSON"))) {
                        Label(String(localized: "Export JSON"), systemImage: "curlybraces")
                    }
                }
                Button(String(localized: "Send by email")) {
                    EmailService.compose(
                        subject: "IPScanner scan results",
                        body: "",
                        attachmentName: "ipscanner-scan.\(selectedFormat.fileExtension)",
                        attachmentData: ExportService.data(for: viewModel.devices, format: .csv),
                        attachmentMime: ExportFormat.csv.mimeType
                    )
                }
            } label: {
                Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel(String(localized: "Export"))
        }
    }

    private var selectedFormat: ExportFormat { .csv }

    private func exportURL(_ format: ExportFormat) -> URL? {
        let data = ExportService.data(for: viewModel.devices, format: format)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ipscanner-scan.\(format.fileExtension)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.9), in: Capsule())
            .padding(.bottom, 12)
            .accessibilityLabel(message)
    }
}
