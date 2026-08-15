//
//  P2PTransferService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//
//  Peer-to-peer exchange of scan results between two instances of IPScanner,
//  using Bonjour discovery (NWListener/NWBrowser) and TCP (NWConnection).
//  The payload is the same JSON the app exports.

import Foundation
import Network

public actor P2PTransferService {
    public static let serviceType = "_ipscanner._tcp"
    public static let defaultPort: UInt16 = 49491

    public init() {}

    /// Starts advertising this instance and receiving JSON payloads from peers.
    /// Returns the live listener so the caller can cancel it later.
    public func startListening(onReceive: @escaping @Sendable (Data) -> Void) throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        guard let port = NWEndpoint.Port(rawValue: Self.defaultPort) else {
            throw P2PError.invalidPort
        }

        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInitiated))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, _, _ in
                if let data {
                    onReceive(data)
                }
                connection.cancel()
            }
        }
        let name = ProcessInfo.processInfo.hostName.isEmpty ? "IPScanner" : ProcessInfo.processInfo.hostName
        listener.service = NWListener.Service(name: name, type: Self.serviceType)
        listener.start(queue: .global(qos: .userInitiated))
        return listener
    }

    /// Discovers other running instances of IPScanner on the local network.
    public func discoverPeers(duration: TimeInterval = 3) async -> [NWEndpoint] {
        let accumulator = EndpointAccumulator()
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .init())
        browser.browseResultsChangedHandler = { results, _ in
            accumulator.append(results.map(\.endpoint))
        }
        browser.start(queue: .global(qos: .userInitiated))

        try? await Task.sleep(for: .seconds(duration))
        browser.cancel()
        return accumulator.endpoints
    }

    /// Sends a JSON payload to a discovered peer.
    public func sendJSON(_ payload: Data, to endpoint: NWEndpoint) async throws {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let resumeOnce = ResumeOnce()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
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
                    resumeOnce.run { continuation.resume(throwing: P2PError.cancelled) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    public enum P2PError: LocalizedError, Sendable {
        case invalidPort
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .invalidPort:
                return "Invalid P2P port."
            case .cancelled:
                return "Peer transfer was cancelled."
            }
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
