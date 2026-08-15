//
//  PortScanTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
import Network
@testable import IPScanner

final class PortScanTests: XCTestCase {
    func testCommonPortList() {
        let ports = PortScanConfiguration.common
        XCTAssertTrue(ports.contains(22))
        XCTAssertTrue(ports.contains(80))
        XCTAssertTrue(ports.contains(443))
    }

    func testServiceNameMapping() {
        XCTAssertEqual(PortScanService.serviceName(for: 80), "http")
        XCTAssertEqual(PortScanService.serviceName(for: 443), "https")
        XCTAssertEqual(PortScanService.serviceName(for: 22), "ssh")
        XCTAssertNil(PortScanService.serviceName(for: 12345))
    }

    /// Integration: a real TCP listener on loopback must be detected as open.
    func testScansLocalListener() async throws {
        let listener = try NWListener(using: .tcp)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInitiated))
        }

        // The ephemeral port is only known after the listener reports .ready.
        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let once = ResumeOnce()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume(returning: listener.port!.rawValue) }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
        defer { listener.cancel() }

        let service = PortScanService()
        let open = await service.scan(
            host: "127.0.0.1",
            configuration: PortScanConfiguration(ports: [port], timeout: 2, concurrency: 4)
        ) { _ in }

        XCTAssertEqual(open.map(\.port), [port])
    }

    func testScansClosedPort() async {
        let service = PortScanService()
        let open = await service.scan(
            host: "127.0.0.1",
            configuration: PortScanConfiguration(ports: [1], timeout: 0.3, concurrency: 4)
        ) { _ in }
        XCTAssertTrue(open.isEmpty)
    }
}
