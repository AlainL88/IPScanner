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
        let hostname = String(cString: hostBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return (!hostname.isEmpty && hostname != ip) ? hostname : nil
    }
}
