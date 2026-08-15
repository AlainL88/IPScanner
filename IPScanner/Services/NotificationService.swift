//
//  NotificationService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import UserNotifications

/// Local notifications for "new device found" and "device went offline" events.
/// iOS runs these through UNUserNotificationCenter; the strings are localized
/// via the app's String Catalog.
public actor NotificationService {
    public static let shared = NotificationService()

    public init() {}

    /// Requests authorization and returns whether it was granted.
    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Current notification permission status.
    public var authorizationStatus: UNAuthorizationStatus {
        get async {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    public func notifyNewDevice(_ device: ScannedDevice) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "New device found")
        content.body = String(localized: "\(deviceDisplayName(device)) is now online (\(device.ip)).")
        content.sound = .default
        await deliver(content: content, identifier: "new-device-\(device.id)")
    }

    public func notifyDeviceWentOffline(_ device: ScannedDevice) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Device offline")
        content.body = String(localized: "\(deviceDisplayName(device)) (\(device.ip)) stopped responding.")
        content.sound = .default
        await deliver(content: content, identifier: "offline-\(device.id)")
    }

    private func deviceDisplayName(_ device: ScannedDevice) -> String {
        device.hostname ?? device.ip
    }

    private func deliver(content: UNNotificationContent, identifier: String) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            NSLog("Notification failed: %@", String(describing: error))
        }
    }
}
