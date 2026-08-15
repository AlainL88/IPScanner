//
//  WakeOnLANService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import Network

/// Builds and sends Wake-on-LAN magic packets.
///
/// A magic packet is 6 bytes of `0xFF` followed by the target MAC address
/// repeated 16 times (102 bytes total), broadcast over UDP.
public enum MagicPacket {
    /// Builds the 102-byte magic packet for a MAC, or nil for malformed input.
    public static func build(forMAC mac: String) -> Data? {
        guard let macBytes = parseMAC(mac) else { return nil }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(macBytes)
        }
        return packet
    }

    /// Parses "AA:BB:CC:DD:EE:FF" (dashes/dots also accepted) into 6 bytes.
    public static func parseMAC(_ mac: String) -> Data? {
        let cleaned = mac
            .uppercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard cleaned.count == 12, cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes = Data()
        bytes.reserveCapacity(6)
        var index = cleaned.startIndex
        for _ in 0..<6 {
            let end = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<end], radix: 16) else { return nil }
            bytes.append(byte)
            index = end
        }
        return bytes
    }
}

/// Sends magic packets over UDP broadcast (default 255.255.255.255:9).
public struct WakeOnLANService: Sendable {
    public init() {}

    public func sendWake(
        mac: String,
        broadcast: String = "255.255.255.255",
        port: UInt16 = 9
    ) async throws {
        guard let packet = MagicPacket.build(forMAC: mac) else {
            throw WakeOnLANError.invalidMAC
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw WakeOnLANError.invalidPort
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(broadcast),
            port: nwPort,
            using: .udp
        )
        let resumeOnce = ResumeOnce()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if let error {
                            resumeOnce.run { continuation.resume(throwing: error) }
                        } else {
                            resumeOnce.run { continuation.resume(returning: ()) }
                        }
                        connection.cancel()
                    })
                case .failed(let error):
                    resumeOnce.run { continuation.resume(throwing: error) }
                    connection.cancel()
                case .cancelled:
                    resumeOnce.run { continuation.resume(throwing: WakeOnLANError.cancelled) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    public enum WakeOnLANError: LocalizedError, Sendable {
        case invalidMAC
        case invalidPort
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .invalidMAC:
                return "Invalid MAC address."
            case .invalidPort:
                return "Invalid port."
            case .cancelled:
                return "Wake-on-LAN send was cancelled."
            }
        }
    }
}

/// Ensures a continuation is resumed exactly once, no matter how many times the
/// connection callback fires afterwards.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func run(_ action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        action()
    }
}
