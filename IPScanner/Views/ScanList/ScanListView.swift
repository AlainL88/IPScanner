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

    /// Resolves the persisted Device record for a scanned device,
    /// prioritizing MAC address matching when available, then IP address.
    private func persistedDevice(for device: ScannedDevice) -> Device? {
        if let mac = device.mac, ARPTableService.isValidMAC(mac) {
            if let match = persistedDevices.first(where: {
                $0.macAddress?.caseInsensitiveCompare(mac) == .orderedSame
            }) {
                return match
            }
        }
        return persistedDevices.first(where: { $0.ipAddress == device.ip })
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if viewModel.devices.isEmpty && !viewModel.isScanning {
                EmptyStateView(startScan: viewModel.startScan)
            } else if viewModel.filteredDevices.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                List {
                    if viewModel.isScanning {
                        ScanProgressView(phase: viewModel.phase)
                    }
                    ForEach(viewModel.filteredDevices) { device in
                        let persisted = persistedDevice(for: device)
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
        .searchable(
            text: $viewModel.searchText,
            prompt: Text(String(localized: "Search by IP, MAC, hostname, name..."))
        )
        .navigationTitle(title)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if !viewModel.devices.isEmpty {
            HStack {
                if !viewModel.searchText.isEmpty {
                    Text(String(format: String(localized: "%lld of %lld devices"), Int64(viewModel.filteredDevices.count), Int64(viewModel.devices.count)))
                } else {
                    let onlineCount = viewModel.devices.filter(\.isOnline).count
                    Text(String(format: String(localized: "%lld devices (%lld online)"), Int64(viewModel.devices.count), Int64(onlineCount)))
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
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
                    Toggle(column.label, isOn: Binding(
                        get: { appState.visibleColumns.contains(column) },
                        set: { isVisible in
                            if isVisible {
                                appState.visibleColumns.insert(column)
                            } else {
                                appState.visibleColumns.remove(column)
                            }
                            appState.persist()
                        }
                    ))
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
