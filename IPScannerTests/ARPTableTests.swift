//
//  ARPTableTests.swift
//  IPScannerTests
//
//  Created by Alain Lima on 15/08/2026.
//

import XCTest
@testable import IPScanner

final class ARPTableTests: XCTestCase {
    #if os(macOS)
    func testReadIsWellFormed() {
        let entries = ARPTableService.read()
        // Validate every entry's shape; the table may legitimately be empty on a
        // host with no LAN traffic yet.
        var debugLog: [String] = []
        debugLog.append("CTL_NET = \(CTL_NET)")
        debugLog.append("PF_ROUTE = \(PF_ROUTE)")
        debugLog.append("AF_INET = \(AF_INET)")
        debugLog.append("NET_RT_FLAGS = \(NET_RT_FLAGS)")
        debugLog.append("RTF_LLINFO = \(RTF_LLINFO)")
        debugLog.append("sandbox_check = \(sandbox_check(getpid(), nil, 0))")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        let errPipe = Pipe()
        process.standardError = errPipe
        process.arguments = ["-an"]
        let pipe = Pipe()
        process.standardOutput = pipe
        var processOutput = ""
        var errOutput = ""
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            processOutput = String(decoding: data, as: UTF8.self)
            errOutput = String(decoding: errData, as: UTF8.self)
        } catch {
            processOutput = "ERROR: \(error)"
        }
        debugLog.append("exit=\(process.terminationStatus), out=\(processOutput.count)b, err=\(errOutput)")
        let lines = processOutput.components(separatedBy: "\n")
        let matching = lines.filter { $0.contains("192.168.5.71") || $0.contains("192.168.5.101") }
        debugLog.append("PROCESS /usr/sbin/arp -an total lines: \(lines.count), matching: \(matching)")
        XCTFail("DEBUG LOG:\n" + debugLog.joined(separator: "\n"))
    }

    func testReadDoesNotCrashOnMacOS() {
        // Smoke test: exercising the real sysctl path must not crash or hang.
        XCTAssertNoThrow(ARPTableService.read())
    }

    func testMacLookupUnknown() {
        XCTAssertNil(ARPTableService.macAddress(for: "203.0.113.250"))
    }
    #endif
}
