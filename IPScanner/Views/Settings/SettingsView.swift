//
//  SettingsView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI
#if os(iOS)
import UIKit
import BackgroundTasks
#endif

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingCrashConfirm = false

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section(String(localized: "Notifications")) {
                Toggle(String(localized: "Notifications"), isOn: $appState.notificationsEnabled)
                    .onChange(of: appState.notificationsEnabled) { _, enabled in
                        appState.persist()
                        if enabled {
                            Task { _ = await NotificationService.shared.requestAuthorization() }
                        }
                    }
            }

            Section(String(localized: "Background scanning")) {
                Toggle(String(localized: "Background scanning"), isOn: $appState.backgroundScanEnabled)
                    .onChange(of: appState.backgroundScanEnabled) { _, enabled in
                        appState.persist()
                        #if os(iOS)
                        if enabled {
                            let service = BackgroundScanService()
                            Task { await service.scheduleNext() }
                        } else {
                            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundScanService.identifier)
                        }
                        #endif
                    }
                Text(String(localized: "On iOS, background scans are best-effort and may be delayed by the system."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Appearance")) {
                Picker(String(localized: "Row size"), selection: $appState.rowDensity) {
                    ForEach(RowDensity.allCases) { density in
                        Text(density.label).tag(density)
                    }
                }
                .onChange(of: appState.rowDensity) { _, _ in appState.persist() }
            }

            Section(String(localized: "About")) {
                LabeledContent(String(localized: "Version"), value: versionString)
                LabeledContent(
                    String(localized: "Crash reporting"),
                    value: CrashReportingService.shared.isEnabled
                        ? String(localized: "Crashlytics enabled")
                        : String(localized: "Crashlytics disabled")
                )
                Button {
                    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                    var body = "Descrivi il tuo problema:\n\nApp: IPScanner\nVersione App: \(appVersion)"
                    #if os(iOS)
                    body += "\nVersione iOS: \(UIDevice.current.systemVersion)"
                    #endif
                    EmailService.compose(
                        subject: "Richiesta di supporto: IPScanner",
                        body: body,
                        recipients: ["support@aldeveloping.it"]
                    )
                } label: {
                    Label(String(localized: "Contact support"), systemImage: "envelope")
                }
                #if DEBUG
                Button(String(localized: "Test Crash"), role: .destructive) {
                    showingCrashConfirm = true
                }
                .confirmationDialog(String(localized: "Test Crash"), isPresented: $showingCrashConfirm, titleVisibility: .visible) {
                    Button(String(localized: "Test Crash"), role: .destructive) {
                        CrashReportingService.shared.triggerTestCrash()
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {}
                }
                #endif
            }
        }
        .navigationTitle(String(localized: "Settings"))
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(format: String(localized: "Version %@"), "\(version) (\(build))")
    }
}
