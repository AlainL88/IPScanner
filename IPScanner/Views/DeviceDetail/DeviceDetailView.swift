//
//  DeviceDetailView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI
import SwiftData
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
    @State private var showingRename = false
    @State private var showingIconPicker = false
    @State private var pingResult: PingResult?
    @State private var renameText = ""

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
            }
            .padding()
        }
        .navigationTitle(device.hostname ?? device.ip)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { loadPersistedDevice() }
        .sheet(isPresented: $showingRename) { renameSheet }
        .sheet(isPresented: $showingIconPicker) { iconPickerSheet }
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
            infoRow(label: String(localized: "IP Address"), value: device.ip)
            Divider()
            infoRow(label: String(localized: "MAC Address"), value: device.mac ?? "—")
            Divider()
            infoRow(label: String(localized: "Hostname"), value: device.hostname ?? "—")
            Divider()
            infoRow(label: String(localized: "Vendor"), value: device.vendor ?? "—")
            Divider()
            infoRow(label: String(localized: "First seen"), value: formatted(device.firstSeen))
            Divider()
            infoRow(label: String(localized: "Last seen"), value: formatted(device.lastSeen))
        }
        .padding(.horizontal, Theme.spacing)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 8)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(String(localized: "Customization"))
                .font(.headline)

            HStack {
                Text(String(localized: "Name"))
                Spacer()
                Button {
                    renameText = persistedDevice?.customName ?? displayName
                    showingRename = true
                } label: {
                    Text(persistedDevice?.customName ?? displayName)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: "Rename"))
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
            actionButton(String(localized: "Wake on LAN"), systemImage: "bolt.fill") {
                wake()
            }
            ShareLink(
                item: deviceShareURL,
                preview: SharePreview(String(localized: "Export"))
            ) {
                actionButtonLabel(String(localized: "Export"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
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

    // MARK: - Sheets

    private var renameSheet: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "Name"), text: $renameText)
            }
            .navigationTitle(String(localized: "Rename"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { showingRename = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        persistedDevice?.customName = renameText.isEmpty ? nil : renameText
                        try? context.save()
                        showingRename = false
                    }
                }
            }
        }
    }

    private var iconPickerSheet: some View {
        NavigationStack {
            let icons = ["desktopcomputer", "laptopcomputer", "iphone", "ipad", "tv", "printer", "server.rack", "router", "camera.fill", "speaker.wave.2.fill", "gamecontroller.fill", "hdd.fill"]
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Theme.spacing) {
                    ForEach(icons, id: \.self) { name in
                        Button {
                            persistedDevice?.customIcon = name
                            try? context.save()
                            showingIconPicker = false
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 28))
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
                                .foregroundStyle(persistedDevice?.customIcon == name ? Color.accentColor : Color.secondary)
                        }
                        .accessibilityLabel(name)
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "Choose icon"))
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
        let request = FetchDescriptor<Device>(predicate: #Predicate { $0.ipAddress == ip })
        persistedDevice = (try? context.fetch(request))?.first
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
        guard let mac = device.mac, !mac.isEmpty else { return }
        let service = WakeOnLANService()
        Task {
            try? await service.sendWake(mac: mac)
        }
    }
}
