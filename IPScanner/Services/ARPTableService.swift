//
//  ARPTableService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//
//  Reads the local ARP cache via the public BSD API: sysctl(PF_ROUTE / AF_INET /
//  NET_RT_FLAGS / RTF_LLINFO). No special entitlements are required. The cache
//  only holds hosts that have already been "contacted" on the network, which is
//  exactly why the scanner runs a ping sweep first to populate it.

import Foundation

#if os(iOS)
// net/route.h is a private header on iOS, so the routing types the sysctl call
// needs are not exposed to Swift. These definitions mirror the (stable) xnu ABI
// exactly; macOS provides them through the SDK instead.
private let NET_RT_FLAGS: Int32 = 2
private let RTF_LLINFO: Int32 = 0x400
private let RTM_VERSION: UInt8 = 5

private struct rt_metrics {
    var rmx_locks: UInt32 = 0
    var rmx_mtu: UInt32 = 0
    var rmx_hopcount: UInt32 = 0
    var rmx_expire: Int32 = 0
    var rmx_recvpipe: UInt32 = 0
    var rmx_sendpipe: UInt32 = 0
    var rmx_ssthresh: UInt32 = 0
    var rmx_rtt: UInt32 = 0
    var rmx_rttvar: UInt32 = 0
    var rmx_pksent: UInt32 = 0
    var rmx_filler: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
}

private struct rt_msghdr {
    var rtm_msglen: UInt16 = 0
    var rtm_version: UInt8 = 0
    var rtm_type: UInt8 = 0
    var rtm_index: UInt16 = 0
    var rtm_flags: Int32 = 0
    var rtm_addrs: Int32 = 0
    var rtm_pid: Int32 = 0
    var rtm_seq: Int32 = 0
    var rtm_errno: Int32 = 0
    var rtm_use: Int32 = 0
    var rtm_inits: UInt32 = 0
    var rtm_rmx: rt_metrics = rt_metrics()
}
#endif

public struct ARPEntry: Sendable, Hashable {
    public let ipAddress: String
    /// nil when the entry is incomplete (host not answered yet).
    public let macAddress: String?
    public let interface: String?
}

public enum ARPTableService {
    /// Reads the whole ARP table as a list of entries.
    public static func read() -> [ARPEntry] {
        var mib = [Int32]([CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO])
        var length = 0
        let sizeResult = mib.withUnsafeMutableBufferPointer { bp -> Bool in
            sysctl(bp.baseAddress, 6, nil, &length, nil, 0) == 0
        }
        guard sizeResult, length > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: length)
        let readResult = mib.withUnsafeMutableBufferPointer { bp -> Bool in
            sysctl(bp.baseAddress, 6, &buffer, &length, nil, 0) == 0
        }
        guard readResult else { return [] }

        var entries: [ARPEntry] = []
        var offset = 0
        let headerSize = MemoryLayout<rt_msghdr>.size

        // Walk the message buffer: each chunk is a rt_msghdr followed by a
        // variable number of sockaddrs (indexed by the rtm_addrs bitmask).
        while offset + headerSize <= buffer.count {
            let header = readStruct(rt_msghdr.self, from: buffer, at: offset)
            guard header.rtm_version == RTM_VERSION else { break }
            let msglen = Int(header.rtm_msglen)
            guard msglen >= headerSize, offset + msglen <= buffer.count else { break }

            if header.rtm_flags & RTF_LLINFO != 0 {
                let resolvedHeaderSize = resolveHeaderSize(in: buffer, offset: offset, msglen: msglen)
                let parsed = parseAddresses(header: header, buffer: buffer, headerOffset: offset, msglen: msglen, headerSize: resolvedHeaderSize)
                if let ip = parsed.ip {
                    entries.append(ARPEntry(ipAddress: ip, macAddress: parsed.mac, interface: parsed.interface))
                }
            }
            offset += msglen
        }
        return entries
    }

    /// Convenience lookup for a single IP. O(n); used once per scanned host.
    public static func macAddress(for ip: String) -> String? {
        read().first(where: { $0.ipAddress == ip })?.macAddress
    }

    /// Placeholder link-layer addresses used by virtual/tunnel interfaces.
    /// They carry no vendor information and would only confuse the UI.
    public static func isPlaceholderMAC(_ mac: String) -> Bool {
        switch mac {
        case "00:00:00:00:00:00", "02:00:00:00:00:00", "FF:FF:FF:FF:FF:FF":
            return true
        default:
            return false
        }
    }

    // MARK: - Parsing

    /// The rt_msghdr layout is nominally 92 bytes, but a few iOS kernels use a
    /// slightly different routing structure. We probe nearby sizes and pick the
    /// one whose first sockaddr looks valid (AF_INET for RTA_DST, AF_LINK for
    /// RTA_GATEWAY), so MAC parsing stays correct on any device.
    private static func resolveHeaderSize(in buffer: [UInt8], offset: Int, msglen: Int) -> Int {
        let nominal = MemoryLayout<rt_msghdr>.size
        let messageEnd = offset + msglen
        for delta in [0, -4, 4, -8, 8] {
            let candidate = nominal + delta
            let pos = offset + candidate
            guard pos + 8 <= messageEnd else { continue }
            let saLen = buffer[pos]
            let family = buffer[pos + 1]
            let validFamily = family == sa_family_t(AF_INET) || family == sa_family_t(AF_LINK)
            if validFamily && Int(saLen) > 0 && pos + Int(saLen) <= messageEnd {
                return candidate
            }
        }
        return nominal
    }

    private static func parseAddresses(
        header: rt_msghdr,
        buffer: [UInt8],
        headerOffset: Int,
        msglen: Int,
        headerSize: Int
    ) -> (ip: String?, mac: String?, interface: String?) {
        var cursor = headerOffset + headerSize
        let end = headerOffset + msglen
        let mask = header.rtm_addrs
        var ip: String?
        var mac: String?
        var interface: String?

        var bit: Int32 = 0
        while cursor < end && bit < 16 {
            if mask & (Int32(1) << bit) != 0 {
                let sockaddrLength = readStruct(sockaddr.self, from: buffer, at: cursor).sa_len
                guard sockaddrLength > 0, cursor + Int(sockaddrLength) <= buffer.count else { break }

                switch bit {
                case 0: // RTA_DST -> IPv4 address
                    if readStruct(sockaddr.self, from: buffer, at: cursor).sa_family == sa_family_t(AF_INET) {
                        ip = readIPv4String(buffer, at: cursor)
                    }
                case 1: // RTA_GATEWAY -> link-layer (MAC + interface)
                    if readStruct(sockaddr.self, from: buffer, at: cursor).sa_family == sa_family_t(AF_LINK) {
                        let sdl = readStruct(sockaddr_dl.self, from: buffer, at: cursor)
                        let link = readLinkLayer(sdl, buffer: buffer, cursor: cursor)
                        mac = link.mac
                        interface = link.interface
                    }
                default:
                    break
                }
                cursor += Int(sockaddrLength)
            }
            bit += 1
        }
        return (ip, mac, interface)
    }

    /// Reads a BSD struct out of the sysctl buffer without requiring alignment
    /// at `offset` (the buffer is byte-indexed, so the base pointer is not
    /// guaranteed to be aligned for every struct type).
    private static func readStruct<T>(_ type: T.Type, from buffer: [UInt8], at offset: Int) -> T {
        buffer.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
    }

    /// sockaddr_in layout: len(1), family(1), port(2), address(4).
    private static func readIPv4String(_ buffer: [UInt8], at cursor: Int) -> String {
        let a = buffer[cursor + 4]
        let b = buffer[cursor + 5]
        let c = buffer[cursor + 6]
        let d = buffer[cursor + 7]
        return "\(a).\(b).\(c).\(d)"
    }

    /// sockaddr_dl layout: len(1), family(1), index(2), type(1), nlen(1),
    /// alen(1), slen(1), data[nlen + alen...]. The interface name sits at the
    /// start of data, followed by the MAC (alen == 6).
    private static func readLinkLayer(_ sdl: sockaddr_dl, buffer: [UInt8], cursor: Int) -> (mac: String?, interface: String?) {
        let nameLength = Int(sdl.sdl_nlen)
        let addressLength = Int(sdl.sdl_alen)
        let dataStart = cursor + 8
        guard dataStart + nameLength + addressLength <= buffer.count else { return (nil, nil) }

        let interface = nameLength > 0
            ? String(bytes: buffer[dataStart..<(dataStart + nameLength)], encoding: .utf8)
            : nil

        guard addressLength == 6 else { return (nil, interface) }
        let macBytes = buffer[(dataStart + nameLength)..<(dataStart + nameLength + addressLength)]
        let mac = macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        // Tunnel/virtual links (VPN, utun, ...) report placeholder link-layer
        // addresses like 02:00:00:00:00:00; hide them instead of showing junk.
        return (isPlaceholderMAC(mac) ? nil : mac, interface)
    }
}
