//
//  DeviceDetailView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct DeviceDetailView: View {
    @Environment(\.modelContext) private var context
    let device: ScannedDevice
    let viewModel: ScanViewModel

    @State private var persistedDevice: Device?
    @State private var showingIconPicker = false
    @State private var pingResult: PingResult?
    @State private var isPortScanning = false
    @State private var openPorts: [OpenPort]?
    @State private var customName = ""
    @State private var showingMACInfo = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.groupedSpacing) {
                header
                infoSection
                metadataSection
                actionButtons
                if let pingResult {
                    pingResultView(pingResult)
                }
                if isPortScanning && openPorts == nil {
                    portScanningProgressView
                }
                if let openPorts {
                    portScanResultView(ports: openPorts)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { loadPersistedDevice() }
        .onDisappear { saveCustomName() }
        .onChange(of: nameFocused) { _, isFocused in
            if !isFocused {
                saveCustomName()
            }
        }
        .sheet(isPresented: $showingIconPicker) { iconPickerSheet }
        .alert(String(localized: "Why is the MAC missing?"), isPresented: $showingMACInfo) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "The MAC address could not be resolved from the local ARP table. The device may be protected by a stealth firewall, offline, or located across a network bridge or router."))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.spacing) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 88, height: 88)
            .accessibilityHidden(true)

            Text(displayName)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Circle()
                    .fill(device.isOnline ? Color.statusOnline : Color.statusOffline)
                    .frame(width: 8, height: 8)
                Text(device.isOnline ? String(localized: "Online") : String(localized: "Offline"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(spacing: 0) {
            infoRow(label: String(localized: "IP Address"), value: device.ip, isMonospaced: true)
            Divider()
            macRow
            Divider()
            infoRow(label: String(localized: "Hostname"), value: device.hostname ?? "—")
            Divider()
            infoRow(label: String(localized: "Vendor"), value: resolvedVendor ?? "—")
            Divider()
            infoRow(label: String(localized: "First seen"), value: formatted(device.firstSeen))
            Divider()
            infoRow(label: String(localized: "Last seen"), value: formatted(device.lastSeen))
        }
        .textSelection(.enabled)
        .padding(.horizontal, Theme.spacing)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func infoRow(label: String, value: String, isMonospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(isMonospaced ? .system(.subheadline, design: .monospaced).weight(.medium) : .subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
        .contextMenu {
            if value != "—" {
                Button {
                    copyToClipboard(value)
                } label: {
                    Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var resolvedMAC: String? {
        if let mac = device.mac, ARPTableService.isValidMAC(mac) {
            return mac
        }
        if let persistedMAC = persistedDevice?.macAddress, ARPTableService.isValidMAC(persistedMAC) {
            return persistedMAC
        }
        if let liveMAC = ARPTableService.macAddress(for: device.ip), ARPTableService.isValidMAC(liveMAC) {
            return liveMAC
        }
        return device.mac
    }

    private var resolvedVendor: String? {
        if let v = device.vendor, !v.isEmpty { return v }
        if let v = persistedDevice?.vendor, !v.isEmpty { return v }
        if let mac = resolvedMAC {
            return OUILookupService.shared.vendorNameSync(forMAC: mac)
        }
        return nil
    }

    /// MAC row with an info button when the address is unavailable (iOS exposes
    /// no neighbor ARP info, so it shows N/A instead of a fake value).
    private var macRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "MAC Address"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if let mac = resolvedMAC, !mac.isEmpty {
                Text(mac)
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            } else {
                Text(String(localized: "N/A"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                Button {
                    showingMACInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Why is the MAC missing?"))
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            if let mac = resolvedMAC, !mac.isEmpty {
                Button {
                    copyToClipboard(mac)
                } label: {
                    Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(String(localized: "Customization"))
                .font(.headline)

            HStack {
                Text(String(localized: "Name"))
                Spacer()
                TextField(
                    String(localized: "Name"),
                    text: $customName,
                    prompt: Text(device.hostname ?? device.ip)
                )
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit {
                    nameFocused = false
                    saveCustomName()
                }
                .frame(maxWidth: 240)
                .accessibilityLabel(String(localized: "Name"))
            }

            HStack {
                Text(String(localized: "Choose icon"))
                Spacer()
                Button {
                    showingIconPicker = true
                } label: {
                    Image(systemName: persistedDevice?.customIcon ?? icon)
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel(String(localized: "Choose icon"))
            }

            Toggle(String(localized: "Whitelist"), isOn: whitelistBinding)
        }
        .padding(Theme.spacing)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private var whitelistBinding: Binding<Bool> {
        Binding(
            get: { persistedDevice?.isWhitelisted ?? false },
            set: { newValue in
                persistedDevice?.isWhitelisted = newValue
                persistedDevice?.lastSeen = Date()
                try? context.save()
            }
        )
    }

    // MARK: - Actions

    private var actionButtons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.spacing) {
            actionButton(String(localized: "Open in browser"), systemImage: "safari") {
                openURL("http://\(device.ip)")
            }
            actionButton(String(localized: "Open VNC"), systemImage: "display") {
                openURL("vnc://\(device.ip)")
            }
            actionButton(String(localized: "Ping"), systemImage: "point.3.connected.trianglepath.dotted") {
                ping()
            }
            actionButton(String(localized: "Scan ports"), systemImage: "network") {
                scanPorts()
            }
            actionButton(String(localized: "Wake on LAN"), systemImage: "bolt.fill") {
                wake()
            }
            #if os(macOS)
            actionButton(String(localized: "Export"), systemImage: "square.and.arrow.up") {
                exportDevice()
            }
            #else
            ShareLink(
                item: deviceShareURL,
                preview: SharePreview(String(localized: "Export"))
            ) {
                actionButtonLabel(String(localized: "Export"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionButtonLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func actionButtonLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .foregroundStyle(Color.accentColor)
        .contentShape(Rectangle())
    }

    // MARK: - Ping result

    private func pingResultView(_ result: PingResult) -> some View {
        Label {
            Text(result.succeeded
                ? String(format: "%.1f ms", (result.roundTripTime ?? 0) * 1000)
                : (result.errorDescription ?? String(localized: "Offline")))
        } icon: {
            Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.succeeded ? Color.statusOnline : Color.statusOffline)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    // MARK: - Port scan results

    private var portScanningProgressView: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(String(localized: "Scanning ports…"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func portScanResultView(ports: [OpenPort]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack {
                Text(String(localized: "Open ports"))
                    .font(.headline)
                Spacer()
                if isPortScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(ports.isEmpty ? String(localized: "All ports closed") : String(format: String(localized: "%lld open ports"), ports.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !ports.isEmpty {
                VStack(spacing: 0) {
                    ForEach(ports, id: \.port) { port in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.statusOnline)
                                .font(.footnote)
                            Text(String(format: String(localized: "Port %lld"), Int64(port.port)))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if let service = port.serviceName {
                                Text(service.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 6)
                        if port != ports.last {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(Theme.spacing)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Sheets

    private struct IconCategory: Identifiable {
        let id: String
        let title: String
        let icons: [String]
    }

    private var iconCategories: [IconCategory] {
        [
            IconCategory(
                id: "computers",
                title: String(localized: "Computers & Tablets"),
                icons: [
                    "desktopcomputer",
                    "laptopcomputer",
                    "macmini",
                    "macstudio",
                    "macpro.gen3",
                    "ipad",
                    "ipad.landscape",
                    "terminal.fill"
                ]
            ),
            IconCategory(
                id: "mobile",
                title: String(localized: "Mobile & Wearables"),
                icons: [
                    "iphone",
                    "applewatch",
                    "headphones",
                    "airpods",
                    "airpodspro",
                    "airtag"
                ]
            ),
            IconCategory(
                id: "network",
                title: String(localized: "Networking & Servers"),
                icons: [
                    "network",
                    "wifi.router",
                    "server.rack",
                    "externaldrive.fill",
                    "externaldrive.connected.to.line.below",
                    "antenna.radiowaves.left.and.right",
                    "point.3.connected.trianglepath.dotted",
                    "shield.checkerboard"
                ]
            ),
            IconCategory(
                id: "smarthome",
                title: String(localized: "Smart Home & IoT"),
                icons: [
                    "homepod.fill",
                    "homepodmini.fill",
                    "camera.fill",
                    "lightbulb.fill",
                    "powerplug.fill",
                    "switch.2",
                    "sensor.fill",
                    "thermometer.medium",
                    "lock.fill",
                    "roller.shade.closed",
                    "blinds.horizontal.closed",
                    "fan.fill",
                    "air.purifier.fill",
                    "sun.max.fill",
                    "ev.charger.fill"
                ]
            ),
            IconCategory(
                id: "media",
                title: String(localized: "Audio, Video & Gaming"),
                icons: [
                    "tv.fill",
                    "appletv.fill",
                    "speaker.wave.2.fill",
                    "speaker.wave.3.fill",
                    "hifispeaker.fill",
                    "videoprojector.fill",
                    "gamecontroller.fill"
                ]
            ),
            IconCategory(
                id: "office",
                title: String(localized: "Office & Peripherals"),
                icons: [
                    "printer.fill",
                    "printer.dotmatrix.fill",
                    "scanner.fill",
                    "display",
                    "keyboard.fill",
                    "creditcard.fill"
                ]
            ),
            IconCategory(
                id: "other",
                title: String(localized: "Other"),
                icons: [
                    "car.fill",
                    "battery.100percent.bolt",
                    "bolt.fill",
                    "questionmark.circle.fill"
                ]
            )
        ]
    }

    private var iconPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if persistedDevice?.customIcon != nil {
                        Button {
                            persistedDevice?.customIcon = nil
                            try? context.save()
                            showingIconPicker = false
                        } label: {
                            Label(String(localized: "Reset to default icon"), systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal)
                    }

                    ForEach(iconCategories) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                                ForEach(category.icons, id: \.self) { name in
                                    let isSelected = persistedDevice?.customIcon == name || (persistedDevice?.customIcon == nil && icon == name)
                                    Button {
                                        persistedDevice?.customIcon = name
                                        persistedDevice?.lastSeen = Date()
                                        try? context.save()
                                        showingIconPicker = false
                                    } label: {
                                        ZStack(alignment: .topTrailing) {
                                            RoundedRectangle(cornerRadius: Theme.smallCornerRadius)
                                                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: Theme.smallCornerRadius)
                                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                                )

                                            Image(systemName: name)
                                                .font(.system(size: 26))
                                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(Color.accentColor)
                                                    .padding(4)
                                            }
                                        }
                                        .frame(height: 58)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(name)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(String(localized: "Choose icon"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { showingIconPicker = false }
                }
            }
        }
    }

    // MARK: - Helpers

    private var icon: String {
        persistedDevice?.customIcon ?? Device.inferredIcon(for: device.hostname, ip: device.ip)
    }

    private var displayName: String {
        persistedDevice?.customName ?? device.hostname ?? device.ip
    }

    #if os(macOS)
    private func exportDevice() {
        let json = ExportService.jsonString(for: [device])
        let filename = "device-\(device.ip).json"
        FileExporter.save(suggestedFileName: filename, data: Data(json.utf8), contentType: .json)
    }
    #endif

    private var deviceShareURL: URL {
        let json = ExportService.jsonString(for: [device])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("device-\(device.ip).json")
        try? Data(json.utf8).write(to: url)
        return url
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func loadPersistedDevice() {
        let ip = device.ip
        var mac = device.mac?.trimmingCharacters(in: .whitespacesAndNewlines)
        if mac == nil || !ARPTableService.isValidMAC(mac) {
            if let liveMAC = ARPTableService.macAddress(for: ip), ARPTableService.isValidMAC(liveMAC) {
                mac = liveMAC
            }
        }
        let hasValidMAC = ARPTableService.isValidMAC(mac)

        let hostname = device.hostname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let allDevices = (try? context.fetch(FetchDescriptor<Device>())) ?? []

        // 1. Match by MAC address, preferring customized records
        if hasValidMAC, let mac {
            let matching = allDevices.filter {
                guard let existingMAC = $0.macAddress else { return false }
                return existingMAC.caseInsensitiveCompare(mac) == .orderedSame
            }
            if !matching.isEmpty {
                let sortedMatching = matching.sorted { a, b in
                    let aHasCustom = (a.customName?.isEmpty == false) || (a.customIcon?.isEmpty == false) || a.isWhitelisted
                    let bHasCustom = (b.customName?.isEmpty == false) || (b.customIcon?.isEmpty == false) || b.isWhitelisted
                    if aHasCustom != bHasCustom {
                        return aHasCustom && !bHasCustom
                    }
                    return a.lastSeen > b.lastSeen
                }
                let chosen = sortedMatching.first!
                persistedDevice = chosen

                if matching.count > 1 {
                    let duplicates = matching.filter { $0.persistentModelID != chosen.persistentModelID }
                    let preservedName = sortedMatching.compactMap(\.customName).first(where: { !$0.isEmpty })
                    let preservedIcon = sortedMatching.compactMap(\.customIcon).first(where: { !$0.isEmpty })
                    if chosen.customName == nil || chosen.customName?.isEmpty == true {
                        chosen.customName = preservedName
                    }
                    if chosen.customIcon == nil || chosen.customIcon?.isEmpty == true {
                        chosen.customIcon = preservedIcon
                    }
                    if matching.contains(where: \.isWhitelisted) {
                        chosen.isWhitelisted = true
                    }
                    for dup in duplicates {
                        context.delete(dup)
                    }
                }
            }
        }

        // 2. Match by distinct hostname, preferring customized records
        if persistedDevice == nil, let hostname, !hostname.isEmpty {
            let matching = allDevices.filter {
                guard let existingHost = $0.hostname?.trimmingCharacters(in: .whitespacesAndNewlines), !existingHost.isEmpty else { return false }
                return existingHost.caseInsensitiveCompare(hostname) == .orderedSame
            }
            if let customMatch = matching.first(where: {
                ($0.customName != nil && !$0.customName!.isEmpty) ||
                ($0.customIcon != nil && !$0.customIcon!.isEmpty) ||
                $0.isWhitelisted
            }) {
                persistedDevice = customMatch
            } else {
                persistedDevice = matching.first
            }
        }

        // 3. Fallback: match by IP address, preferring customized records
        if persistedDevice == nil {
            let matching = allDevices.filter { $0.ipAddress == ip }
            if let customMatch = matching.first(where: {
                ($0.customName != nil && !$0.customName!.isEmpty) ||
                ($0.customIcon != nil && !$0.customIcon!.isEmpty) ||
                $0.isWhitelisted
            }) {
                persistedDevice = customMatch
            } else {
                persistedDevice = matching.first
            }
        }

        if persistedDevice == nil {
            let vendor = device.vendor ?? (mac != nil ? OUILookupService.shared.vendorNameSync(forMAC: mac!) : nil)
            let newDevice = Device(
                ipAddress: device.ip,
                macAddress: hasValidMAC ? mac : device.mac,
                hostname: device.hostname,
                vendor: vendor,
                firstSeen: device.firstSeen,
                lastSeen: device.lastSeen,
                isOnline: device.isOnline
            )
            context.insert(newDevice)
            try? context.save()
            persistedDevice = newDevice
        } else if let persisted = persistedDevice {
            if persisted.ipAddress != device.ip {
                persisted.ipAddress = device.ip
            }
            if hasValidMAC, let mac {
                persisted.macAddress = mac
                // Deduplicate any other records sharing this MAC
                let duplicates = allDevices.filter {
                    $0.persistentModelID != persisted.persistentModelID &&
                    $0.macAddress?.caseInsensitiveCompare(mac) == .orderedSame
                }
                if !duplicates.isEmpty {
                    let allMatching = [persisted] + duplicates
                    let sortedMatching = allMatching.sorted { a, b in
                        let aHasCustom = (a.customName?.isEmpty == false) || (a.customIcon?.isEmpty == false) || a.isWhitelisted
                        let bHasCustom = (b.customName?.isEmpty == false) || (b.customIcon?.isEmpty == false) || b.isWhitelisted
                        if aHasCustom != bHasCustom {
                            return aHasCustom && !bHasCustom
                        }
                        return a.lastSeen > b.lastSeen
                    }
                    if persisted.customName == nil || persisted.customName?.isEmpty == true {
                        persisted.customName = sortedMatching.compactMap(\.customName).first(where: { !$0.isEmpty })
                    }
                    if persisted.customIcon == nil || persisted.customIcon?.isEmpty == true {
                        persisted.customIcon = sortedMatching.compactMap(\.customIcon).first(where: { !$0.isEmpty })
                    }
                    if allMatching.contains(where: \.isWhitelisted) {
                        persisted.isWhitelisted = true
                    }
                    for dup in duplicates {
                        context.delete(dup)
                    }
                }
            }
            if let hostname = device.hostname, !hostname.isEmpty, persisted.hostname == nil {
                persisted.hostname = hostname
            }
            let vendor = device.vendor ?? (mac != nil ? OUILookupService.shared.vendorNameSync(forMAC: mac!) : nil)
            if let vendor, !vendor.isEmpty, persisted.vendor == nil {
                persisted.vendor = vendor
            }
            try? context.save()
        }

        customName = persistedDevice?.customName ?? ""
    }

    /// Persists the inline name field. An empty (or whitespace-only) value clears
    /// the custom name and falls back to hostname/IP.
    private func saveCustomName() {
        if persistedDevice == nil {
            loadPersistedDevice()
        }
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        persistedDevice?.customName = trimmed.isEmpty ? nil : trimmed
        persistedDevice?.lastSeen = Date()
        try? context.save()
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    private func ping() {
        pingResult = nil
        let ip = device.ip
        Task {
            let service = PingService(timeout: 2)
            let result = await service.ping(host: ip)
            await MainActor.run { pingResult = result }
        }
    }

    private func wake() {
        guard let mac = resolvedMAC, !mac.isEmpty else { return }
        let service = WakeOnLANService()
        Task {
            try? await service.sendWake(mac: mac)
        }
    }

    private func scanPorts() {
        guard !isPortScanning else { return }
        isPortScanning = true
        openPorts = nil
        let ip = device.ip
        let config = PortScanConfiguration(ports: PortScanConfiguration.common)
        Task {
            let service = PortScanService()
            let ports = await service.scan(host: ip, configuration: config) { _ in }
            await MainActor.run {
                openPorts = ports
                isPortScanning = false
            }
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
}
