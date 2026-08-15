//
//  IPAddress.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation

/// A minimal IPv4 address value type used across the scanner (subnet math,
/// ping sweeps, persistence keys, export). Kept intentionally small and pure.
public struct IPv4Address: Hashable, Sendable, Codable, CustomStringConvertible {
    public let a: UInt8
    public let b: UInt8
    public let c: UInt8
    public let d: UInt8

    public init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    /// Parses a dotted-quad string such as "192.168.1.5". Returns nil for any
    /// malformed input, including leading zeros ("192.168.1.05").
    public init?(string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets = [UInt8]()
        octets.reserveCapacity(4)
        for part in parts {
            guard let value = UInt8(part), String(value) == String(part) else { return nil }
            octets.append(value)
        }
        self.init(octets[0], octets[1], octets[2], octets[3])
    }

    public var description: String { "\(a).\(b).\(c).\(d)" }

    /// The address as a 32-bit integer with the octets in network byte order
    /// (a is the most significant byte). Enables cheap arithmetic/iteration.
    public var uint32: UInt32 {
        (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(c) << 8) | UInt32(d)
    }

    public init(uint32: UInt32) {
        self.init(
            UInt8((uint32 >> 24) & 0xFF),
            UInt8((uint32 >> 16) & 0xFF),
            UInt8((uint32 >> 8) & 0xFF),
            UInt8(uint32 & 0xFF)
        )
    }

    /// The next address, or nil at 255.255.255.255.
    public func next() -> IPv4Address? {
        let value = uint32
        guard value < UInt32.max else { return nil }
        return IPv4Address(uint32: value + 1)
    }

    /// Heuristic host check for typical /24 LANs: excludes .0 and .255.
    public var isHostAddress: Bool { d != 0 && d != 255 }
}

/// CIDR parsing and host-range expansion. Pure and unit-testable.
public enum IPv4CIDR {
    /// Parses "network/prefix" (e.g. "192.168.1.0/24"). Returns nil on invalid
    /// network or prefix (0...32).
    public static func parse(_ cidr: String) -> (network: IPv4Address, prefix: UInt8)? {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let ip = IPv4Address(string: String(parts[0])),
              let prefix = UInt8(parts[1]),
              prefix <= 32 else {
            return nil
        }
        return (ip, prefix)
    }

    /// Expands a CIDR to its host addresses, excluding the network and broadcast
    /// addresses, capped at `maxHosts`. RFC 3021 /31 and /32 are handled as
    /// point-to-point/loopback addresses.
    public static func hostAddresses(_ cidr: String, maxHosts: Int = 4096) -> [IPv4Address] {
        guard let (network, prefix) = parse(cidr) else { return [] }
        return hostAddresses(network: network, prefix: prefix, maxHosts: maxHosts)
    }

    public static func hostAddresses(network: IPv4Address, prefix: UInt8, maxHosts: Int = 4096) -> [IPv4Address] {
        guard prefix <= 32 else { return [] }

        if prefix == 32 {
            return maxHosts >= 1 ? [network] : []
        }
        if prefix == 31 {
            var result = [IPv4Address]()
            result.append(network)
            if let next = network.next(), result.count < maxHosts {
                result.append(next)
            }
            return result
        }

        let hostBits = 32 - Int(prefix)
        let hostMask: UInt32 = hostBits >= 32 ? .max : (UInt32(1) << hostBits) - 1
        let base = network.uint32 & ~hostMask
        let broadcast = base | hostMask

        var result = [IPv4Address]()
        result.reserveCapacity(min(maxHosts, 1024))
        var current = base &+ 1 // skip the network address itself
        while current < broadcast && result.count < maxHosts {
            result.append(IPv4Address(uint32: current))
            current &+= 1
        }
        return result
    }

    /// Broadcast address for a given network/prefix.
    public static func broadcast(of network: IPv4Address, prefix: UInt8) -> IPv4Address {
        let hostBits = 32 - Int(prefix)
        let hostMask: UInt32 = hostBits >= 32 ? .max : (UInt32(1) << hostBits) - 1
        return IPv4Address(uint32: network.uint32 | hostMask)
    }
}
