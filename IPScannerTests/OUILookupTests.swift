//
//  OUILookupTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class OUILookupTests: XCTestCase {
    func testDatasetLoadsFromAppBundle() async {
        // The dataset is bundled with the app; the hosted test reads it via the
        // app's main bundle.
        let service = OUILookupService(bundle: .main)
        let count = await service.count
        XCTAssertGreaterThan(count, 10_000, "bundled OUI dataset should contain the full IEEE registry")
    }

    func testKnownAppleOUI() async {
        let service = OUILookupService(bundle: .main)
        let vendor = await service.vendorName(forMAC: "F4:5C:89:AB:CD:EF")
        XCTAssertEqual(vendor?.lowercased(), "apple, inc.")
    }

    func testLookupIsCaseAndSeparatorInsensitive() async {
        let service = OUILookupService(bundle: .main)
        let viaLower = await service.vendorName(forMAC: "f4-5c-89-ab-cd-ef")
        let viaDots = await service.vendorName(forMAC: "F45C.89AB.CDEF")
        XCTAssertEqual(viaLower, viaDots)
        XCTAssertNotNil(viaLower)
    }

    func testUnknownOUI() async {
        let service = OUILookupService(bundle: .main)
        let vendor = await service.vendorName(forMAC: "FF:FF:FF:00:00:01")
        XCTAssertNil(vendor)
    }

    func testMalformedMAC() async {
        let service = OUILookupService(bundle: .main)
        let empty = await service.vendorName(forMAC: "")
        let junk = await service.vendorName(forMAC: "not-a-mac")
        XCTAssertNil(empty)
        XCTAssertNil(junk)
    }

    func testNormalizedPrefix() {
        XCTAssertEqual(OUILookupService.normalizedPrefix(from: "F4-5C-89-AB-CD-EF"), "F45C89")
        XCTAssertNil(OUILookupService.normalizedPrefix(from: "XYZ"))
    }
}
