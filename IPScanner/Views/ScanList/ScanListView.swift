//
//  ScanListView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

        VStack(spacing: 0) {
            if !viewModel.devices.isEmpty || viewModel.isScanning {
                filterPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(.bar)
                Divider()
            }

            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .searchable(
            text: $viewModel.searchText,
            prompt: Text(viewModel.filterMode == .availableOnly
                ? String(localized: "Search by IP...")
                : String(localized: "Search by IP, MAC, hostname, name..."))
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
        .task {
            viewModel.startPeriodicStatusCheck()
        }
        .onDisappear {
            viewModel.stopPeriodicStatusCheck()
        }
        .refreshable {
            await viewModel.refreshDeviceStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportScanCSV)) { _ in
            #if os(macOS)
            exportData(format: .csv)
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportScanJSON)) { _ in
            #if os(macOS)
            exportData(format: .json)
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareScanResults)) { _ in
            #if os(macOS)
            shareData()
            #endif
        }
    }

    @ViewBuilder
    private var mainContentArea: some View {
        if viewModel.devices.isEmpty && !viewModel.isScanning && viewModel.filterMode != .availableOnly {
            EmptyStateView(startScan: viewModel.startScan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filterMode == .availableOnly {
            if viewModel.filteredAvailableIPs.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.availableIPs.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Free IPs"),
                    systemImage: "network.slash",
                    description: Text(String(localized: "All IP addresses in this subnet are occupied."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                availableIPsList
            }
        } else {
            if viewModel.filteredDevices.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredDevices.isEmpty && viewModel.filterMode == .onlineOnly {
                ContentUnavailableView(
                    String(localized: "No Online Devices"),
                    systemImage: "wifi.slash",
                    description: Text(String(localized: "No active devices currently online."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredDevices.isEmpty && viewModel.filterMode == .whitelistedOnly {
                ContentUnavailableView(
                    String(localized: "No Whitelisted Devices"),
                    systemImage: "shield.slash",
                    description: Text(String(localized: "No devices have been marked as whitelisted yet. Open device details to whitelist trusted devices."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredDevices.isEmpty && viewModel.filterMode == .notWhitelistedOnly {
                ContentUnavailableView(
                    String(localized: "All Devices Whitelisted"),
                    systemImage: "checkmark.shield",
                    description: Text(String(localized: "All discovered devices are currently in your whitelist."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                deviceList
            }
        }
    }

    private var filterPicker: some View {
        @Bindable var viewModel = viewModel
        return Picker(String(localized: "Filter"), selection: $viewModel.filterMode) {
            ForEach(DeviceListFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(String(localized: "Filter devices"))
    }

    private var deviceList: some View {
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
                        columns: appState.visibleColumns,
                        isWhitelisted: persisted?.isWhitelisted ?? false
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .contextMenu {
                    deviceContextMenu(for: device, persisted: persisted)
                }
            }
        }
        .listStyle(.inset)
    }

    private var availableIPsList: some View {
        List {
            if viewModel.isScanning {
                ScanProgressView(phase: viewModel.phase)
            }
            ForEach(viewModel.filteredAvailableIPs, id: \.self) { ip in
                let dummyDevice = ScannedDevice(
                    id: ip,
                    ip: ip,
                    mac: nil,
                    hostname: nil,
                    vendor: nil,
                    firstSeen: Date(),
                    lastSeen: Date(),
                    isOnline: false,
                    isNew: false
                )
                NavigationLink {
                    DeviceDetailView(device: dummyDevice, viewModel: viewModel)
                } label: {
                    AvailableIPRowView(
                        ip: ip,
                        cidr: viewModel.currentCIDR,
                        density: appState.rowDensity
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .contextMenu {
                    Button {
                        copyToClipboard(ip)
                    } label: {
                        Label(String(localized: "Copy IP Address"), systemImage: "doc.on.doc")
                    }

                    Divider()

                    NavigationLink {
                        PingToolView(initialHost: ip)
                    } label: {
                        Label(String(localized: "Ping IP"), systemImage: "point.3.connected.trianglepath.dotted")
                    }

                    NavigationLink {
                        PortScanToolView(initialHost: ip)
                    } label: {
                        Label(String(localized: "Port Scan"), systemImage: "network")
                    }

                    Divider()

                    Button {
                        openURL("http://\(ip)")
                    } label: {
                        Label(String(localized: "Open in Browser (HTTP)"), systemImage: "safari")
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func deviceContextMenu(for device: ScannedDevice, persisted: Device?) -> some View {
        Button {
            toggleWhitelist(for: device, persisted: persisted)
        } label: {
            if persisted?.isWhitelisted == true {
                Label(String(localized: "Remove from Whitelist"), systemImage: "shield.slash")
            } else {
                Label(String(localized: "Add to Whitelist"), systemImage: "checkmark.shield")
            }
        }

        Divider()

        Menu {
            Button {
                copyToClipboard(device.ip)
            } label: {
                Label(String(localized: "IP: \(device.ip)"), systemImage: "doc.on.doc")
            }

            if let mac = device.mac, !mac.isEmpty {
                Button {
                    copyToClipboard(mac)
                } label: {
                    Label(String(localized: "MAC: \(mac)"), systemImage: "doc.on.doc")
                }
            }

            if let hostname = device.hostname, !hostname.isEmpty {
                Button {
                    copyToClipboard(hostname)
                } label: {
                    Label(String(localized: "Hostname: \(hostname)"), systemImage: "doc.on.doc")
                }
            }

            if let customName = persisted?.customName, !customName.isEmpty {
                Button {
                    copyToClipboard(customName)
                } label: {
                    Label(String(localized: "Custom Name: \(customName)"), systemImage: "doc.on.doc")
                }
            }
        } label: {
            Label(String(localized: "Copy"), systemImage: "doc.on.doc")
        }

        Divider()

        NavigationLink {
            PingToolView(initialHost: device.ip)
        } label: {
            Label(String(localized: "Ping"), systemImage: "point.3.connected.trianglepath.dotted")
        }

        NavigationLink {
            PortScanToolView(initialHost: device.ip)
        } label: {
            Label(String(localized: "Port Scan"), systemImage: "network")
        }

        if let mac = device.mac, ARPTableService.isValidMAC(mac) {
            Button {
                sendWakeOnLAN(mac: mac)
            } label: {
                Label(String(localized: "Wake on LAN"), systemImage: "bolt.fill")
            }
        }

        Divider()

        Button {
            openURL("http://\(device.ip)")
        } label: {
            Label(String(localized: "Open in Browser (HTTP)"), systemImage: "safari")
        }

        Button {
            openURL("https://\(device.ip)")
        } label: {
            Label(String(localized: "Open in Browser (HTTPS)"), systemImage: "lock.safari")
        }

        Button {
            openURL("vnc://\(device.ip)")
        } label: {
            Label(String(localized: "Open VNC"), systemImage: "display")
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if !viewModel.devices.isEmpty || viewModel.filterMode == .availableOnly {
            HStack(spacing: 8) {
                switch viewModel.filterMode {
                case .all:
                    if !viewModel.searchText.isEmpty {
                        Text(String(format: String(localized: "%lld of %lld devices"), Int64(viewModel.filteredDevices.count), Int64(viewModel.devices.count)))
                    } else {
                        let onlineCount = viewModel.devices.filter(\.isOnline).count
                        Text(String(format: String(localized: "%lld devices (%lld online)"), Int64(viewModel.devices.count), Int64(onlineCount)))
                    }
                case .onlineOnly:
                    let onlineDevices = viewModel.devices.filter(\.isOnline)
                    if !viewModel.searchText.isEmpty {
                        Text(String(format: String(localized: "%lld of %lld online devices"), Int64(viewModel.filteredDevices.count), Int64(onlineDevices.count)))
                    } else {
                        Text(String(format: String(localized: "%lld online devices"), Int64(onlineDevices.count)))
                    }
                case .whitelistedOnly:
                    let allPersisted = (try? context.fetch(FetchDescriptor<Device>())) ?? []
                    let totalWhitelisted = allPersisted.filter(\.isWhitelisted).count
                    if !viewModel.searchText.isEmpty {
                        Text(String(format: String(localized: "%lld of %lld whitelisted devices"), Int64(viewModel.filteredDevices.count), Int64(totalWhitelisted)))
                    } else {
                        Text(String(format: String(localized: "%lld whitelisted devices"), Int64(viewModel.filteredDevices.count)))
                    }
                case .notWhitelistedOnly:
                    let nonWhitelistedCount = viewModel.filteredDevices.count
                    if !viewModel.searchText.isEmpty {
                        Text(String(format: String(localized: "%lld of %lld untrusted devices"), Int64(viewModel.filteredDevices.count), Int64(nonWhitelistedCount)))
                    } else {
                        Text(String(format: String(localized: "%lld untrusted devices"), Int64(nonWhitelistedCount)))
                    }
                case .availableOnly:
                    let total = viewModel.totalSubnetHostsCount
                    let freeCount = viewModel.availableIPs.count
                    if !viewModel.searchText.isEmpty {
                        Text(String(format: String(localized: "%lld of %lld free IPs"), Int64(viewModel.filteredAvailableIPs.count), Int64(freeCount)))
                    } else if total > 0 {
                        Text(String(format: String(localized: "%lld free IPs of %lld in subnet"), Int64(freeCount), Int64(total)))
                    } else {
                        Text(String(format: String(localized: "%lld free IPs"), Int64(freeCount)))
                    }
                }

                if viewModel.isRefreshingStatus {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel(String(localized: "Updating status…"))
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

        ToolbarItem(placement: .automatic) {
            Button {
                Task { await viewModel.refreshDeviceStatuses() }
            } label: {
                Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isScanning || viewModel.devices.isEmpty || viewModel.isRefreshingStatus)
            .help(String(localized: "Refresh Status (Ping)"))
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        ToolbarItem(placement: .automatic) {
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
                Label(String(localized: "Sort"), systemImage: "arrow.up.arrow.down")
            }
            .help(String(localized: "Sort by"))
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Section(String(localized: "Row size")) {
                    ForEach(RowDensity.allCases) { density in
                        Button {
                            appState.rowDensity = density
                            appState.persist()
                        } label: {
                            Label(density.label, systemImage: appState.rowDensity == density ? "checkmark" : "")
                        }
                    }
                }

                Section(String(localized: "Columns")) {
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
                }
            } label: {
                Label(String(localized: "View"), systemImage: "slider.horizontal.3")
            }
            .help(String(localized: "View options"))
        }

        #if os(iOS)
        ToolbarItem(placement: .automatic) {
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
                    let data: Data
                    let filename: String
                    if viewModel.filterMode == .availableOnly {
                        data = ExportService.availableIPsData(for: viewModel.availableIPs, cidr: viewModel.currentCIDR ?? "", format: .csv)
                        filename = "ipscanner-free-ips.csv"
                    } else {
                        data = ExportService.data(for: viewModel.devices, format: .csv)
                        filename = "ipscanner-scan.csv"
                    }
                    EmailService.compose(
                        subject: "IPScanner scan results",
                        body: "",
                        attachmentName: filename,
                        attachmentData: data,
                        attachmentMime: ExportFormat.csv.mimeType
                    )
                }
            } label: {
                Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel(String(localized: "Export"))
        }
        #endif
    }

    private var selectedFormat: ExportFormat { .csv }

    #if os(macOS)
    private func exportData(format: ExportFormat) {
        let data: Data
        let filename: String
        if viewModel.filterMode == .availableOnly {
            data = ExportService.availableIPsData(for: viewModel.availableIPs, cidr: viewModel.currentCIDR ?? "", format: format)
            filename = "ipscanner-free-ips.\(format.fileExtension)"
        } else {
            data = ExportService.data(for: viewModel.devices, format: format)
            filename = "ipscanner-scan.\(format.fileExtension)"
        }
        FileExporter.save(suggestedFileName: filename, data: data, contentType: format.utType)
    }

    private func shareData() {
        let data: Data
        let filename: String
        if viewModel.filterMode == .availableOnly {
            data = ExportService.availableIPsData(for: viewModel.availableIPs, cidr: viewModel.currentCIDR ?? "", format: .csv)
            filename = "ipscanner-free-ips.csv"
        } else {
            data = ExportService.data(for: viewModel.devices, format: .csv)
            filename = "ipscanner-scan.csv"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)

        let jsonData: Data
        let jsonFilename: String
        if viewModel.filterMode == .availableOnly {
            jsonData = ExportService.availableIPsData(for: viewModel.availableIPs, cidr: viewModel.currentCIDR ?? "", format: .json)
            jsonFilename = "ipscanner-free-ips.json"
        } else {
            jsonData = ExportService.data(for: viewModel.devices, format: .json)
            jsonFilename = "ipscanner-scan.json"
        }
        let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent(jsonFilename)
        try? jsonData.write(to: jsonURL)

        let picker = NSSharingServicePicker(items: [url, jsonURL])
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }),
           let contentView = window.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }
    #endif

    private func exportURL(_ format: ExportFormat) -> URL? {
        let data: Data
        let filename: String
        if viewModel.filterMode == .availableOnly {
            data = ExportService.availableIPsData(for: viewModel.availableIPs, cidr: viewModel.currentCIDR ?? "", format: format)
            filename = "ipscanner-free-ips.\(format.fileExtension)"
        } else {
            data = ExportService.data(for: viewModel.devices, format: format)
            filename = "ipscanner-scan.\(format.fileExtension)"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
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

    // MARK: - Context Menu Helpers

    private func toggleWhitelist(for device: ScannedDevice, persisted: Device?) {
        if let persisted {
            persisted.isWhitelisted.toggle()
            try? context.save()
        } else {
            let mac = device.mac?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasValidMAC = ARPTableService.isValidMAC(mac)
            let newDevice = Device(
                ipAddress: device.ip,
                macAddress: hasValidMAC ? mac : device.mac,
                hostname: device.hostname,
                vendor: device.vendor,
                customName: nil,
                customIcon: nil,
                isWhitelisted: true,
                firstSeen: device.firstSeen,
                lastSeen: device.lastSeen,
                isOnline: device.isOnline
            )
            context.insert(newDevice)
            try? context.save()
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    private func sendWakeOnLAN(mac: String) {
        let service = WakeOnLANService()
        Task {
            try? await service.sendWake(mac: mac)
        }
    }
}
