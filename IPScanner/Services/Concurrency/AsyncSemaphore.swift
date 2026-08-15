//
//  AsyncSemaphore.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation

/// A tiny async semaphore used to bound concurrency in sweeps (ping, port scan).
public final class AsyncSemaphore: @unchecked Sendable {
    private let lock = NSLock()
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(count: Int) {
        self.permits = max(0, count)
    }

    public func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if permits > 0 {
                permits -= 1
                lock.unlock()
                continuation.resume() // never actually suspends
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    public func signal() {
        lock.lock()
        defer { lock.unlock() }
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
