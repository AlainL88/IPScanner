//
//  CrashReportingService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// Wraps Firebase Crashlytics behind a defensive, optional integration.
///
/// Crashlytics is only initialized when a `GoogleService-Info.plist` is present
/// in the app bundle. Without it the app runs normally and Crashlytics stays
/// disabled — no crash, no blocking alert. This lets anyone build and run the
/// project from a fresh clone that does not have Firebase credentials.
public final class CrashReportingService: @unchecked Sendable {
    /// Shared instance configured once from the app entry point.
    public static let shared = CrashReportingService()

    /// Whether Crashlytics is active for this run.
    public private(set) var isEnabled = false

    /// Internal so the unit tests can build isolated instances.
    init() {}

    /// Configures Crashlytics if and only if the GoogleService-Info.plist is
    /// present and its BUNDLE_ID matches the running app. The `firebaseConfigure`
    /// closure is injected for tests.
    public func configure(
        bundle: Bundle = .main,
        firebaseConfigure: (() -> Void)? = nil
    ) {
        guard let plistPath = bundle.path(forResource: "GoogleService-Info", ofType: "plist") else {
            isEnabled = false
            NSLog("Crashlytics disabled: GoogleService-Info.plist not found")
            return
        }

        // Guard against a stale or mismatched plist initializing Firebase with
        // credentials that belong to a different bundle.
        if let plist = NSDictionary(contentsOfFile: plistPath),
           let plistBundleID = plist["BUNDLE_ID"] as? String,
           let appBundleID = bundle.bundleIdentifier,
           plistBundleID != appBundleID {
            isEnabled = false
            NSLog("Crashlytics disabled: GoogleService-Info.plist BUNDLE_ID (%@) does not match %@", plistBundleID, appBundleID)
            return
        }

        isEnabled = true
        if let firebaseConfigure {
            firebaseConfigure()
        } else {
            #if canImport(FirebaseCore)
            FirebaseApp.configure()
            #endif
        }
    }

    /// Triggers a deliberate crash to verify end-to-end delivery to Crashlytics.
    /// Exposed behind a hidden "Test Crash" button in DEBUG builds only.
    public func triggerTestCrash() {
        #if DEBUG
        guard isEnabled else {
            NSLog("Test Crash ignored: Crashlytics not enabled")
            return
        }
        fatalError("Intentional test crash — verify in the Crashlytics console")
        #else
        NSLog("Test Crash unavailable outside DEBUG builds")
        #endif
    }
}
