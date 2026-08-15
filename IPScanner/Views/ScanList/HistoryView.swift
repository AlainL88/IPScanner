//
//  HistoryView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanSession.startedAt, order: .reverse) private var sessions: [ScanSession]
    @State private var selectedSession: ScanSession?

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    String(localized: "No previous scans"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text("")
                )
            } else {
                List(sessions) { session in
                    Button {
                        selectedSession = session
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text(session.cidr + " · " + String(format: String(localized: "%lld devices found"), session.deviceSnapshots.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(session)
                            try? context.save()
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(String(localized: "Scan history"))
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
        }
    }
}

private struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let session: ScanSession

    var body: some View {
        NavigationStack {
            List(session.deviceSnapshots, id: \.ip) { snapshot in
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.hostname ?? snapshot.ip)
                        .font(.body.weight(.medium))
                    Text(snapshot.ip + (snapshot.mac.map { " · \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .shortened))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: exportURL(.csv), preview: SharePreview(String(localized: "Export CSV"))) {
                            Label(String(localized: "Export CSV"), systemImage: "doc.text")
                        }
                        ShareLink(item: exportURL(.json), preview: SharePreview(String(localized: "Export JSON"))) {
                            Label(String(localized: "Export JSON"), systemImage: "curlybraces")
                        }
                    } label: {
                        Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func exportURL(_ format: ExportFormat) -> URL {
        let devices = session.deviceSnapshots.map { snapshot in
            ScannedDevice(
                id: snapshot.ip,
                ip: snapshot.ip,
                mac: snapshot.mac,
                hostname: snapshot.hostname,
                vendor: snapshot.vendor,
                firstSeen: snapshot.lastSeen,
                lastSeen: snapshot.lastSeen,
                isOnline: snapshot.isOnline,
                isNew: false
            )
        }
        let data = ExportService.data(for: devices, format: format)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ipscanner-session.\(format.fileExtension)")
        try? data.write(to: url)
        return url
    }
}
