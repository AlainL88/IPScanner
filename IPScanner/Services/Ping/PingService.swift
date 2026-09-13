//
//  PingService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation

/// Runs ICMP ping sweeps. A single `SimplePing` exchange is blocking (bounded by
/// a socket timeout), so each ping is dispatched onto a concurrent GCD queue
/// rather than blocking the cooperative pool.
public actor PingService {
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.alain.ipscanner.ping", qos: .userInitiated, attributes: .concurrent)
    private static let counterLock = NSLock()
    private nonisolated(unsafe) static var counter: UInt16 = 0

    public init(timeout: TimeInterval = 1.5) {
        self.timeout = timeout
    }

    private static func nextIdentifier() -> UInt16 {
        counterLock.lock()
        counter &+= 1
        let value = counter
        counterLock.unlock()
        return value
    }

    /// Pings a single host, with optional retries on failure (e.g. to avoid WiFi sleep/drop false negatives).
    public func ping(host: String, retries: Int = 0, timeout: TimeInterval? = nil) async -> PingResult {
        let actualTimeout = timeout ?? self.timeout
        var attemptsLeft = max(0, retries)

        while true {
            let identifier = Self.nextIdentifier()
            let result = await withCheckedContinuation { continuation in
                queue.async {
                    let res = SimplePing.ping(host: host, identifier: identifier, sequence: 1, timeout: actualTimeout)
                    continuation.resume(returning: res)
                }
            }
            if result.succeeded || attemptsLeft == 0 {
                return result
            }
            attemptsLeft -= 1
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Pings a list of hosts with limited concurrency, reporting each result as
    /// it completes. Returns the results in input order.
    public func pingSweep(
        addresses: [String],
        concurrency: Int = 32,
        onResult: @escaping @Sendable (PingResult) -> Void
    ) async -> [PingResult] {
        let semaphore = AsyncSemaphore(count: concurrency)
        return await withTaskGroup(of: PingResult.self) { group in
            for address in addresses {
                group.addTask { [self] in
                    await semaphore.wait()
                    defer { semaphore.signal() }
                    let result = await self.ping(host: address, retries: 1)
                    onResult(result)
                    return result
                }
            }
            var results = [PingResult]()
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
}
