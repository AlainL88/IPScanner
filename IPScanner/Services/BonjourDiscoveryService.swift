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
        "_http._tcp", "_https._tcp", "_ssh._tcp", "_smb._tcp", "_rfb._tcp",
        "_airplay._tcp", "_airtunes._tcp", "_ipp._tcp", "_printer._tcp",
        "_companion-link._tcp", "_spotify-connect._tcp", "_hap._tcp"
    ]

    public init() {}

    /// Resolves hostnames for a set of IPv4 addresses via mDNS. Returns
    /// `[ip: hostname]` for whichever addresses could be mapped within `duration`.
    public func resolveHostnames(for addresses: Set<String>, duration: TimeInterval = 3) async -> [String: String] {
        var remaining = addresses
        guard !remaining.isEmpty else { return [:] }

        let endpoints = await browseEndpoints(duration: duration)
        var result: [String: String] = [:]

        for endpoint in endpoints {
            guard !remaining.isEmpty else { break }
            let resolved = await resolve(endpoint: endpoint)
            if let hostname = resolved.hostname,
               let ip = resolved.ip,
               !hostname.isEmpty,
               remaining.contains(ip) {
                result[ip] = hostname
                remaining.remove(ip)
            }
        }
        return result
    }

    // MARK: - Private

    private func browseEndpoints(duration: TimeInterval) async -> [NWEndpoint] {
        let accumulator = EndpointAccumulator()
        var browsers: [NWBrowser] = []

        for type in Self.commonServiceTypes {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .init())
            browsers.append(browser)
            browser.browseResultsChangedHandler = { results, _ in
                accumulator.append(results.map(\.endpoint))
            }
            browser.start(queue: .global(qos: .userInitiated))
        }

        // Let the browsers accumulate results for the window, then stop them.
        try? await Task.sleep(for: .seconds(duration))
        for browser in browsers { browser.cancel() }
        return accumulator.endpoints
    }

    /// Resolves an mDNS service endpoint to (hostname, ip) with a bounded timeout.
    private func resolve(endpoint: NWEndpoint) async -> (hostname: String?, ip: String?) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let resumeOnce = ResumeOnce()

        return await withCheckedContinuation { (continuation: CheckedContinuation<(String?, String?), Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let (hostname, ip) = Self.extractHostPort(connection.currentPath?.remoteEndpoint)
                    resumeOnce.run {
                        continuation.resume(returning: (hostname, ip))
                        connection.cancel()
                    }
                case .failed:
                    resumeOnce.run {
                        continuation.resume(returning: (nil, nil))
                        connection.cancel()
                    }
                case .cancelled:
                    resumeOnce.run { continuation.resume(returning: (nil, nil)) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                resumeOnce.run {
                    connection.cancel()
                    continuation.resume(returning: (nil, nil))
                }
            }
        }
    }

    /// Extracts (hostname, ip) from a resolved `.hostPort` endpoint.
    private static func extractHostPort(_ endpoint: NWEndpoint?) -> (hostname: String?, ip: String?) {
        guard let endpoint else { return (nil, nil) }
        guard case .hostPort(let host, _) = endpoint else { return (nil, nil) }
        switch host {
        case .name(let name, _):
            // A hostname that is actually an IP literal (e.g. "192.168.1.5").
            let isIPLiteral = Network.IPv4Address(name) != nil
            return (name, isIPLiteral ? name : nil)
        case .ipv4(let address):
            return (nil, "\(address)")
        case .ipv6(let address):
            return (nil, "\(address)")
        @unknown default:
            return (nil, nil)
        }
    }
}

/// Thread-safe bucket for NWBrowser results.
private final class EndpointAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [NWEndpoint] = []

    func append(_ endpoints: [NWEndpoint]) {
        lock.lock()
        storage.append(contentsOf: endpoints)
        lock.unlock()
    }

    var endpoints: [NWEndpoint] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
