//
//  ResumeOnce.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation

/// Ensures a continuation (or any one-shot action) is executed exactly once,
/// no matter how many times a network callback fires afterwards.
final class ResumeOnce: @unchecked Sendable {
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
