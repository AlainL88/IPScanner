//
//  IPScannerApp.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

@main
struct IPScannerApp: App {
    init() {
        // Defensive: no-ops and disables Crashlytics when GoogleService-Info.plist
        // is missing, so the app always builds and runs from a fresh clone.
        CrashReportingService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            Text("IPScanner")
        }
    }
}
