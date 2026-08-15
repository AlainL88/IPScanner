//
//  ExportService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation

public enum ExportFormat: String, CaseIterable, Sendable, Identifiable {
    case csv
    case json

    public var id: String { rawValue }

    public var fileExtension: String { rawValue }

    public var mimeType: String {
        switch self {
        case .csv: return "text/csv"
        case .json: return "application/json"
        }
    }
}

/// Builds CSV/JSON exports from scan results (RFC-4180 quoting for CSV).
public enum ExportService {
    public static func data(for devices: [ScannedDevice], format: ExportFormat) -> Data {
        switch format {
        case .csv: return Data(csvString(for: devices).utf8)
        case .json: return Data(jsonString(for: devices).utf8)
        }
    }

    public static func csvString(for devices: [ScannedDevice]) -> String {
        var lines = ["IP,MAC,Hostname,Vendor,Status,Last Seen"]
        let formatter = ISO8601DateFormatter()
        for device in devices {
            let fields = [
                device.ip,
                device.mac ?? "",
                device.hostname ?? "",
                device.vendor ?? "",
                device.isOnline ? "online" : "offline",
                formatter.string(from: device.lastSeen)
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func jsonString(for devices: [ScannedDevice]) -> String {
        let items = devices.map { device -> [String: String] in
            [
                "ip": device.ip,
                "mac": device.mac ?? "",
                "hostname": device.hostname ?? "",
                "vendor": device.vendor ?? "",
                "status": device.isOnline ? "online" : "offline"
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys]) else {
            return "[]"
        }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
