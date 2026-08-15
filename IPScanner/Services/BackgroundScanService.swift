//
//  BackgroundScanService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import SwiftData
#if os(iOS)
import BackgroundTasks
#endif

/// Periodic background scanning.
///
/// iOS: registered as a BGAppRefreshTask. Note that iOS heavily throttles
/// background refreshes — this is "best effort" and not guaranteed to run on a
/// schedule (same limitation as every local-network scanner; it is not a bug).
/// macOS: a foreground timer drives `runScanNow()` with no background limits.
public actor BackgroundScanService {
    public static let identifier = "com.alain.IPScanner.refresh"

    public init() {}

    #if os(iOS)
    /// Registers the BGAppRefreshTask handler. Call once at app launch.
    public func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            Task { await self.handle(task: task) }
        }
    }

    /// Submits the next refresh request.
    public func scheduleNext(earliestBeginIn: TimeInterval = 60) {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestBeginIn)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Runs a bounded scan for the background refresh, updates Device records,
    /// and re-schedules the next one.
    public func handle(task: BGTask) {
        task.expirationHandler = { [weak task] in
            task?.setTaskCompleted(success: false)
        }
        Task {
            await runScanNow()
            task.setTaskCompleted(success: true)
        }
    }
    #endif

    /// Scans the primary subnet and updates persistence. Reusable from the
    /// macOS timer and the iOS background task.
    public func runScanNow(includeBonjour: Bool = false) async {
        guard let cidr = SubnetService.primaryIPv4Interface()?.cidr else { return }

        let coordinator = NetworkScannerCoordinator()
        var responders: [ScannedDevice] = []
        let stream = await coordinator.scan(cidr: cidr, includeBonjour: includeBonjour)
        for await event in stream {
            if case .device(let device) = event {
                responders.append(device)
            }
        }

        let seenIPs = Set(responders.map(\.ip))
        await MainActor.run {
            let context = PersistenceController.container.mainContext
            for device in responders {
                DeviceStore.upsert(device, in: context)
            }
            DeviceStore.markOffline(excluding: seenIPs, in: context)
            try? context.save()
        }

        #if os(iOS)
        scheduleNext()
        #endif
    }
}
