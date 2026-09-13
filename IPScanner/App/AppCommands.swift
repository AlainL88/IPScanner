//
//  AppCommands.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

extension Notification.Name {
    static let exportScanCSV = Notification.Name("com.alain.ipscanner.exportScanCSV")
    static let exportScanJSON = Notification.Name("com.alain.ipscanner.exportScanJSON")
    static let shareScanResults = Notification.Name("com.alain.ipscanner.shareScanResults")
}

#if os(macOS)
struct FileMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button(String(localized: "Export CSV...")) {
                NotificationCenter.default.post(name: .exportScanCSV, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button(String(localized: "Export JSON...")) {
                NotificationCenter.default.post(name: .exportScanJSON, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Share...")) {
                NotificationCenter.default.post(name: .shareScanResults, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
#endif
