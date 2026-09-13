//
//  ExportService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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

    public var utType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
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

    public static func availableIPsData(for ips: [String], cidr: String, format: ExportFormat) -> Data {
        switch format {
        case .csv: return Data(availableIPsCSVString(for: ips, cidr: cidr).utf8)
        case .json: return Data(availableIPsJSONString(for: ips, cidr: cidr).utf8)
        }
    }

    public static func availableIPsCSVString(for ips: [String], cidr: String) -> String {
        var lines = ["IP,Status,Subnet"]
        for ip in ips {
            lines.append("\(csvEscape(ip)),available,\(csvEscape(cidr))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func availableIPsJSONString(for ips: [String], cidr: String) -> String {
        let items = ips.map { ip -> [String: String] in
            [
                "ip": ip,
                "status": "available",
                "subnet": cidr
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

#if os(macOS)
@MainActor
public enum FileExporter {
    public static func save(suggestedFileName: String, data: Data, contentType: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })
        if let targetWindow {
            panel.beginSheetModal(for: targetWindow) { response in
                if response == .OK, let targetURL = panel.url {
                    try? data.write(to: targetURL)
                }
            }
        } else {
            let response = panel.runModal()
            if response == .OK, let targetURL = panel.url {
                try? data.write(to: targetURL)
            }
        }
    }
}
#endif
