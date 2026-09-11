//
//  BonjourDiscoveryService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//
//  Best-effort mDNS enrichment: browses common service types with NWBrowser and
//  resolves each discovered service to a hostname/IP so the coordinator can
//  attach friendly names to the devices it found via ping.

import Foundation
import Network

public actor BonjourDiscoveryService {
    /// Service types most likely to be advertised by home/lab devices.
    private static let commonServiceTypes = [
        "_http._tcp", "_https._tcp", "_ssh._tcp", "_sftp-ssh._tcp", "_smb._tcp",
        "_afpovertcp._tcp", "_rfb._tcp", "_airplay._tcp", "_raop._tcp", "_airtunes._tcp",
        "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_scanner._tcp",
        "_companion-link._tcp", "_apple-mobdev2._tcp", "_device-info._tcp",
        "_hap._tcp", "_home-assistant._tcp", "_shelly._tcp", "_sonos._tcp",
        "_spotify-connect._tcp", "_googlecast._tcp", "_workstation._tcp", "_matter._tcp"
    ]

    public init() {}

    /// Resolves hostnames for a set of IPv4 addresses via mDNS. Returns
    /// `[ip: hostname]` for whichever addresses could be mapped within `duration`.
    public func resolveHostnames(for addresses: Set<String>, duration: TimeInterval = 2.5) async -> [String: String] {
        guard !addresses.isEmpty else { return [:] }

        let discovered = await browseEndpoints(duration: duration)
        guard !discovered.isEmpty else { return [:] }

        var result: [String: String] = [:]

        await withTaskGroup(of: (ip: String, hostname: String)?.self) { group in
            for item in discovered {
                group.addTask {
                    guard let ip = await self.resolveIP(for: item.endpoint) else { return nil }
                    let cleanName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else { return nil }
                    return (ip, cleanName)
                }
            }

            for await mapping in group {
                if let (ip, hostname) = mapping, addresses.contains(ip) {
                    if result[ip] == nil {
                        result[ip] = hostname
                    }
                }
            }
        }

        return result
    }

    // MARK: - Private

    private func browseEndpoints(duration: TimeInterval) async -> [(name: String, endpoint: NWEndpoint)] {
        let accumulator = DiscoveredItemAccumulator()
        var browsers: [NWBrowser] = []

        for type in Self.commonServiceTypes {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .init())
            browsers.append(browser)
            browser.browseResultsChangedHandler = { results, _ in
                var items: [(name: String, endpoint: NWEndpoint)] = []
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        items.append((name, result.endpoint))
                    }
                }
                accumulator.append(items)
            }
            browser.start(queue: .global(qos: .userInitiated))
        }

        // Let the browsers accumulate results for the window, then stop them.
        try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
        for browser in browsers { browser.cancel() }
        return accumulator.items
    }

    /// Resolves an mDNS service endpoint to an IPv4 string without requiring TCP connection handshakes.
    private func resolveIP(for endpoint: NWEndpoint) async -> String? {
        let connection = NWConnection(to: endpoint, using: .udp)
        let resumeOnce = ResumeOnce()

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ip = Self.extractIPv4(connection.currentPath?.remoteEndpoint)
                    resumeOnce.run {
                        connection.cancel()
                        continuation.resume(returning: ip)
                    }
                case .failed, .cancelled:
                    resumeOnce.run {
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                resumeOnce.run {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Extracts IPv4 address string from remote endpoint, stripping any interface scope (e.g. %en0).
    private static func extractIPv4(_ endpoint: NWEndpoint?) -> String? {
        guard let endpoint else { return nil }
        guard case .hostPort(let host, _) = endpoint else { return nil }
        switch host {
        case .ipv4(let address):
            let raw = "\(address)"
            return raw.components(separatedBy: "%").first
        case .name(let name, _):
            if IPv4Address(string: name) != nil {
                return name
            }
            return nil
        default:
            return nil
        }
    }
}

/// Thread-safe bucket for discovered Bonjour service items.
private final class DiscoveredItemAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(name: String, endpoint: NWEndpoint)] = []

    func append(_ items: [(name: String, endpoint: NWEndpoint)]) {
        lock.lock()
        storage.append(contentsOf: items)
        lock.unlock()
    }

    var items: [(name: String, endpoint: NWEndpoint)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
