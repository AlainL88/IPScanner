//
//  CrashReportingServiceTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class CrashReportingServiceTests: XCTestCase {
    /// The whole point of the optional integration: without GoogleService-Info.plist
    /// Crashlytics must stay disabled and Firebase must never be configured.
    func testDisabledWhenPlistMissing() {
        let service = CrashReportingService()
        service.configure(
            bundle: Bundle(for: Self.self),
            firebaseConfigure: { XCTFail("Firebase must not be configured without a plist") }
        )
        XCTAssertFalse(service.isEnabled)
    }

    /// Guard against the plist check being inverted: a bundle that has the plist
    /// must enable Crashlytics.
    func testEnabledWhenPlistPresent() throws {
        let bundle = Bundle(for: Self.self)
        guard bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            throw XCTSkip("Test bundle has no GoogleService-Info.plist")
        }
        let service = CrashReportingService()
        service.configure(bundle: bundle, firebaseConfigure: {})
        XCTAssertTrue(service.isEnabled)
    }
}
