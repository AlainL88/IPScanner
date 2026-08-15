//
//  PortScanService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import Network

public struct OpenPort: Sendable, Hashable {
    public let port: UInt16
    public let serviceName: String?
}

public struct PortScanConfiguration: Sendable {
    public var ports: [UInt16]
    public var timeout: TimeInterval
    public var concurrency: Int

    public init(ports: [UInt16], timeout: TimeInterval = 0.8, concurrency: Int = 24) {
        self.ports = ports
        self.timeout = timeout
        self.concurrency = concurrency
    }

    /// The well-known ports most relevant on a home/LAN device.
    public static let common: [UInt16] = [
        21, 22, 23, 25, 53, 80, 110, 111, 135, 139,
        143, 443, 445, 993, 995, 1723, 3306, 3389, 5900, 8080
    ]
}

/// Concurrent TCP port scanner built on NWConnection. Concurrency is bounded so
/// a large port list doesn't flood the network.
public actor PortScanService {
    public init() {}

    /// Scans `host` across the configured ports, reporting each open port as it
    /// is found. Returns the open ports sorted by port number.
    public func scan(
        host: String,
        configuration: PortScanConfiguration,
        onResult: @escaping @Sendable (OpenPort) -> Void
    ) async -> [OpenPort] {
        let semaphore = AsyncSemaphore(count: configuration.concurrency)

        return await withTaskGroup(of: OpenPort?.self) { group in
            var open: [OpenPort] = []
            for port in configuration.ports {
                group.addTask {
                    await semaphore.wait()
                    defer { semaphore.signal() }
                    guard await Self.isOpen(host: host, port: port, timeout: configuration.timeout) else {
                        return nil
                    }
                    let result = OpenPort(port: port, serviceName: Self.serviceName(for: port))
                    onResult(result)
                    return result
                }
            }
            for await result in group {
                if let result {
                    open.append(result)
                }
            }
            return open.sorted { $0.port < $1.port }
        }
    }

    /// Maps a port to its conventional service name (used for display only).
    public static func serviceName(for port: UInt16) -> String? {
        switch port {
        case 21: return "ftp"
        case 22: return "ssh"
        case 23: return "telnet"
        case 25: return "smtp"
        case 53: return "dns"
        case 80: return "http"
        case 110: return "pop3"
        case 111: return "sunrpc"
        case 135: return "msrpc"
        case 139: return "netbios"
        case 143: return "imap"
        case 443: return "https"
        case 445: return "smb"
        case 993: return "imaps"
        case 995: return "pop3s"
        case 1723: return "pptp"
        case 3306: return "mysql"
        case 3389: return "rdp"
        case 5900: return "vnc"
        case 8080: return "http-alt"
        default: return nil
        }
    }

    /// Checks whether a TCP connection to host:port succeeds within `timeout`.
    private static func isOpen(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let resumeOnce = ResumeOnce()

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce.run {
                        continuation.resume(returning: true)
                        connection.cancel()
                    }
                case .failed:
                    resumeOnce.run {
                        continuation.resume(returning: false)
                        connection.cancel()
                    }
                case .cancelled:
                    resumeOnce.run { continuation.resume(returning: false) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            // Timeout guard: if the connect hasn't resolved in time, give up.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resumeOnce.run {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
