//
//  OUILookupService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation

/// Resolves a device vendor from the first 6 hex digits of a MAC address using
/// the bundled `oui-database.json` (generated from the public IEEE OUI registry,
/// https://standards-oui.ieee.org/oui/oui.txt).
public actor OUILookupService {
    public struct Entry: Sendable, Hashable {
        public let prefix: String
        public let vendor: String
    }

    private let database: [String: String]

    public init(bundle: Bundle = .main, fileName: String = "oui-database") {
        var db: [String: String] = [:]
        if let url = bundle.url(forResource: fileName, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            db = decoded
        }
        database = db
    }

    /// Number of OUI prefixes loaded from the bundled dataset.
    public var count: Int { database.count }

    /// Looks up the vendor for a MAC address ("AA:BB:CC:DD:EE:FF", dashes or
    /// dots allowed; case-insensitive). Returns nil for unknown or malformed MACs.
    public func vendorName(forMAC mac: String) -> String? {
        guard let prefix = Self.normalizedPrefix(from: mac) else { return nil }
        return database[prefix]
    }

    /// Normalizes a MAC to its 6-hex-digit OUI prefix, or nil when invalid.
    public static func normalizedPrefix(from mac: String) -> String? {
        let cleaned = mac
            .uppercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard cleaned.count >= 6, cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(cleaned.prefix(6))
    }
}
