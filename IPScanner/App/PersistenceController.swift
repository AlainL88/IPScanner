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
/// CloudKit is only attempted when the app is actually signed with the iCloud
/// container entitlement. Otherwise — fresh clones, builds without the
/// capability, simulators without iCloud — we use a purely local store so the
/// app always launches without crashing.
enum PersistenceController {
    static let container: ModelContainer = {
        let allModels = Schema([Device.self, CustomNetworkRange.self, ScanSession.self])

        // When running under XCTest, stay local-only so the test host doesn't attempt CloudKit connections
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                        NSClassFromString("XCTestCase") != nil

        if !isTesting {
            do {
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
                return try ModelContainer(for: allModels, configurations: [cloudConfig, localConfig])
            } catch {
                NSLog("SwiftData/CloudKit container unavailable (%@); using a local-only store.", String(describing: error))
            }
        }

        // Local-only store — fallback when CloudKit is unavailable (e.g. unsigned simulator or no account).
        let localOnly = ModelConfiguration(schema: allModels, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: allModels, configurations: [localOnly])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// In-memory container for SwiftUI previews and tests.
    static let previewContainer: ModelContainer = {
        makeInMemoryContainer()
    }()

    /// Creates a fresh in-memory container for isolated tests.
    static func makeInMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(
            for: Schema([Device.self, CustomNetworkRange.self, ScanSession.self]),
            configurations: [config]
        )
    }
}
