//
//  PersistenceController.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import SwiftData

/// Builds the SwiftData container.
///
/// Two stores are used:
///  - "Cloud" syncs personalized data (Device + CustomNetworkRange) via CloudKit.
///  - "Local" keeps scan history on-device only.
///
/// If the CloudKit-backed store can't be created (contributor without an iCloud
/// container, iCloud disabled, etc.) we fall back to a purely local store so the
/// app always launches.
enum PersistenceController {
    static let container: ModelContainer = {
        let allModels = Schema([Device.self, CustomNetworkRange.self, ScanSession.self])

        let cloudConfig = ModelConfiguration(
            "Cloud",
            schema: Schema([Device.self, CustomNetworkRange.self]),
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        let localConfig = ModelConfiguration(
            "Local",
            schema: Schema([ScanSession.self]),
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: allModels, configurations: [cloudConfig, localConfig])
        } catch {
            NSLog("SwiftData/CloudKit container unavailable (%@); using a local-only store.", String(describing: error))
            let localOnly = ModelConfiguration(schema: allModels, isStoredInMemoryOnly: false)
            do {
                return try ModelContainer(for: allModels, configurations: [localOnly])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    /// In-memory container for SwiftUI previews and tests.
    static let previewContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: Schema([Device.self, CustomNetworkRange.self, ScanSession.self]),
            configurations: [config]
        )
    }()
}
