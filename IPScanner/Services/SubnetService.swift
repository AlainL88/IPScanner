//
//  SubnetService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation

#if os(macOS)
import IOKit
#endif

/// A single IPv4 network interface (address, netmask, broadcast, and hardware MAC address).
public struct NetworkInterface: Sendable, Equatable {
    public let name: String
    public let ipAddress: String
    public let netmask: String
    public let prefixLength: UInt8
    public let broadcastAddress: String?
    public let hardwareAddress: String?

    public init(
        name: String,
        ipAddress: String,
        netmask: String,
        prefixLength: UInt8,
        broadcastAddress: String?,
        hardwareAddress: String? = nil
    ) {
        self.name = name
        self.ipAddress = ipAddress
        self.netmask = netmask
        self.prefixLength = prefixLength
        self.broadcastAddress = broadcastAddress
        self.hardwareAddress = hardwareAddress
    }

    /// Canonical network CIDR (e.g. "192.168.5.0/24") — used as the scan target and display.
    public var cidr: String {
        if let ip = IPv4Address(string: ipAddress) {
            let net = IPv4CIDR.networkAddress(of: ip, prefix: prefixLength)
            return "\(net.description)/\(prefixLength)"
        }
        return "\(ipAddress)/\(prefixLength)"
    }
}

/// Determines the primary local IPv4 subnet via `getifaddrs`.
public enum SubnetService {
    /// Returns the first usable non-loopback IPv4 interface. Prefers interfaces
    /// named `en*`/`eth*` (the typical Wi-Fi/Ethernet ones) and skips link-local.
    public static func primaryIPv4Interface() -> NetworkInterface? {
        var hardwareAddresses = [String: String]()
        var candidates = [NetworkInterface]()
        var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPtr) == 0 else { return nil }
        defer { freeifaddrs(ifaddrsPtr) }

        // Pass 1: Extract hardware MAC addresses from AF_LINK entries
        var ptr = ifaddrsPtr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_LINK) else { continue }
            let ifName = String(cString: current.pointee.ifa_name)
            let saLen = Int(addr.pointee.sa_len)
            guard saLen >= 8 else { continue }
            let raw = UnsafeRawPointer(addr)
            let nlen = Int(raw.loadUnaligned(fromByteOffset: 5, as: UInt8.self))
            let alen = Int(raw.loadUnaligned(fromByteOffset: 6, as: UInt8.self))
            if alen == 6 && 8 + nlen + 6 <= saLen {
                let macBytes = (0..<6).map { raw.loadUnaligned(fromByteOffset: 8 + nlen + $0, as: UInt8.self) }
                let mac = macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")
                if ARPTableService.isValidMAC(mac) {
                    hardwareAddresses[ifName] = mac
                }
            }
        }

        #if os(macOS)
        // In the macOS App Sandbox, getifaddrs redacts AF_LINK MAC addresses to 02:00:00:00:00:00.
        // Fall back to IOKit IOEthernetInterface to obtain the real hardware MAC address.
        let ioKitAddresses = LocalHardwareAddress.allHardwareAddresses()
        for (ifName, mac) in ioKitAddresses {
            if hardwareAddresses[ifName] == nil {
                hardwareAddresses[ifName] = mac
            }
        }
        #endif

        // Pass 2: Extract usable IPv4 candidates and attach hardware MAC
        ptr = ifaddrsPtr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            guard let addr = current.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let flags = current.pointee.ifa_flags
            guard flags & UInt32(IFF_LOOPBACK) == 0 else { continue }

            let ip = Self.ipString(from: addr)
            guard ip != "0.0.0.0" else { continue }
            // Skip link-local (169.254.x.x): not routable for scanning.
            guard let parsed = IPv4Address(string: ip), !(parsed.a == 169 && parsed.b == 254) else { continue }

            let name = String(cString: current.pointee.ifa_name)
            let netmask = current.pointee.ifa_netmask.map { Self.ipString(from: $0) } ?? "255.255.255.0"
            // On broadcast interfaces Swift exposes the ifa_ifu union as ifa_dstaddr,
            // which holds the broadcast address.
            let broadcast = current.pointee.ifa_dstaddr.map { Self.ipString(from: $0) }
            let prefix = prefixLength(fromNetmask: netmask)

            candidates.append(
                NetworkInterface(
                    name: name,
                    ipAddress: ip,
                    netmask: netmask,
                    prefixLength: prefix,
                    broadcastAddress: broadcast,
                    hardwareAddress: hardwareAddresses[name]
                )
            )
        }

        // Prefer en*/eth*, then the first candidate overall.
        if let preferred = candidates.first(where: { $0.name.hasPrefix("en") || $0.name.hasPrefix("eth") }) {
            return preferred
        }
        return candidates.first
    }

    /// Converts a sockaddr into a dotted-quad IPv4 string.
    static func ipString(from addr: UnsafePointer<sockaddr>) -> String {
        guard addr.pointee.sa_family == sa_family_t(AF_INET) else { return "" }
        var sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &sin.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }

    /// Computes the CIDR prefix length from a netmask like "255.255.255.0".
    public static func prefixLength(fromNetmask mask: String) -> UInt8 {
        guard let addr = IPv4Address(string: mask) else { return 0 }
        var value = addr.uint32
        var count: UInt8 = 0
        while value & 0x8000_0000 != 0 {
            count += 1
            value <<= 1
        }
        return count
    }

    /// True for RFC 1918 private ranges: 10/8, 172.16/12, 192.168/16.
    public static func isPrivateIP(_ ip: String) -> Bool {
        guard let addr = IPv4Address(string: ip) else { return false }
        if addr.a == 10 { return true }
        if addr.a == 172, (16...31).contains(addr.b) { return true }
        if addr.a == 192, addr.b == 168 { return true }
        return false
    }
}

#if os(macOS)
/// Reads local interface hardware MAC addresses via IOKit IOEthernetInterface.
/// Works inside the macOS App Sandbox where getifaddrs AF_LINK is redacted to 02:00:00:00:00:00.
enum LocalHardwareAddress {
    static func allHardwareAddresses() -> [String: String] {
        var result = [String: String]()
        let matching = IOServiceMatching("IOEthernetInterface") as NSMutableDictionary
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let bsdName = IORegistryEntryCreateCFProperty(service, "BSD Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
                continue
            }
            var parent: io_object_t = 0
            guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(parent) }

            if let macData = IORegistryEntryCreateCFProperty(parent, "IOMACAddress" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
                let mac = macData.map { String(format: "%02X", $0) }.joined(separator: ":")
                if ARPTableService.isValidMAC(mac) {
                    result[bsdName] = mac
                }
            }
        }
        return result
    }
}
#endif
