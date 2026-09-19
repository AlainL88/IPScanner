//
//  DNSResolver.swift
//  IPScanner
//
//  Created by Alain Lima on 11/09/2026.
//

import Foundation

/// Fast reverse DNS resolver using BSD getnameinfo.
public enum DNSResolver {
    /// Performs a reverse DNS lookup (PTR query) for an IPv4 address.
    /// Returns the resolved hostname or nil if resolution fails or returns an IP literal.
    public static func reverseLookup(ip: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_flags = AI_NUMERICHOST

        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &res) == 0, let addrInfo = res else {
            return nil
        }
        defer { freeaddrinfo(res) }

        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            addrInfo.pointee.ai_addr,
            addrInfo.pointee.ai_addrlen,
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NAMEREQD
        )
        guard result == 0 else { return nil }
        let rawHostname = String(cString: hostBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanHostname(rawHostname)
    }

    /// Cleans a resolved hostname by trimming whitespaces, removing trailing dots,
    /// stripping ".local" suffixes for display if present, and discarding IP literals.
    public static func cleanHostname(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasSuffix(".") {
            name.removeLast()
        }
        if name.lowercased().hasSuffix(".local") {
            name = String(name.dropLast(6))
        }
        // Strip Apple CompanionLink hex prefix (e.g. "2A7D354E4C9B@MacBook Air")
        if let atIndex = name.firstIndex(of: "@") {
            let prefix = name[..<atIndex]
            if prefix.count >= 8 && prefix.allSatisfy({ $0.isHexDigit }) {
                name = String(name[name.index(after: atIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard !name.isEmpty else { return nil }
        // If it is an IPv4 literal, discard it
        if IPv4Address(string: name) != nil {
            return nil
        }
        return name
    }
}
