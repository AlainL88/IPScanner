//
//  SimplePing.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//
//  A Swift port of Apple's SimplePing sample: ICMP echo request/reply over a
//  SOCK_DGRAM socket with IPPROTO_ICMP (no special entitlements required on
//  iOS/macOS). Replaces the delegate-based API with a plain synchronous call
//  that `PingService` runs on a background dispatch queue.
//
//  Only public surface used by the app: `ping(host:identifier:sequence:timeout:)`,
//  `makeEchoRequest(...)` and `inetChecksum(...)` (the last two are unit-tested).

import Foundation
import QuartzCore

public struct PingResult: Sendable, Hashable {
    public let address: String
    public let succeeded: Bool
    public let roundTripTime: TimeInterval?
    public let errorDescription: String?

    public init(address: String, succeeded: Bool, roundTripTime: TimeInterval?, errorDescription: String?) {
        self.address = address
        self.succeeded = succeeded
        self.roundTripTime = roundTripTime
        self.errorDescription = errorDescription
    }
}

public enum SimplePing {
    public struct EchoReply: Equatable, Sendable {
        public let type: UInt8
        public let identifier: UInt16
        public let sequence: UInt16
    }

    /// Performs one ICMP echo round trip. Blocking up to `timeout` seconds —
    /// call from a background queue, never from the main actor.
    public static func ping(
        host: String,
        identifier: UInt16,
        sequence: UInt16,
        timeout: TimeInterval = 1.5
    ) -> PingResult {
        let start = CACurrentMediaTime()

        guard var address = makeSockAddr(host) else {
            return PingResult(address: host, succeeded: false, roundTripTime: nil, errorDescription: "Host resolution failed")
        }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else {
            return PingResult(address: host, succeeded: false, roundTripTime: nil, errorDescription: "socket() failed: \(errno)")
        }
        defer { close(fd) }

        // Bound the receive wait so a dead host times out instead of hanging.
        var tv = timeval()
        tv.tv_sec = Int(timeout)
        tv.tv_usec = Int32((timeout - TimeInterval(Int(timeout))) * 1_000_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let packet = makeEchoRequest(identifier: identifier, sequence: sequence)
        let sent = packet.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &address) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, packet.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else {
            return PingResult(address: host, succeeded: false, roundTripTime: nil, errorDescription: "sendto() failed: \(errno)")
        }

        // Read replies until a matching echo reply arrives or the socket times out.
        var buffer = [UInt8](repeating: 0, count: 512)
        while true {
            let received = recvfrom(fd, &buffer, buffer.count, 0, nil, nil)
            if received < 0 {
                let error = errno
                if error == EAGAIN || error == EWOULDBLOCK {
                    return PingResult(address: host, succeeded: false, roundTripTime: nil, errorDescription: "Timeout")
                }
                return PingResult(address: host, succeeded: false, roundTripTime: nil, errorDescription: "recvfrom() failed: \(error)")
            }
            let data = Data(buffer.prefix(received))
            // On Darwin, ICMP sockets deliver received packets with the IPv4
            // header included. Skip it (IHL * 4 bytes) before parsing ICMP.
            let icmpData: Data
            if data.count >= 20, data[data.startIndex] >> 4 == 4 {
                let ihl = Int(data[data.startIndex] & 0x0F) * 4
                icmpData = data.dropFirst(ihl)
            } else {
                icmpData = data
            }
            if let reply = parseEchoReply(icmpData),
               reply.type == 0, // echo reply
               reply.identifier == identifier,
               reply.sequence == sequence {
                return PingResult(address: host, succeeded: true, roundTripTime: CACurrentMediaTime() - start, errorDescription: nil)
            }
        }
    }

    /// Builds an ICMP echo-request datagram with a computed checksum.
    public static func makeEchoRequest(
        identifier: UInt16,
        sequence: UInt16,
        payload: Data = Data(repeating: 0, count: 8)
    ) -> Data {
        var packet = Data()
        packet.append(8)            // ICMP type: echo request
        packet.append(0)            // code
        packet.append(0); packet.append(0) // checksum placeholder
        packet.append(UInt8(identifier >> 8))
        packet.append(UInt8(identifier & 0xFF))
        packet.append(UInt8(sequence >> 8))
        packet.append(UInt8(sequence & 0xFF))
        packet.append(payload)

        let sum = inetChecksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    /// Parses the ICMP header of a received datagram (type, id, sequence).
    public static func parseEchoReply(_ data: Data) -> EchoReply? {
        guard data.count >= 8 else { return nil }
        let bytes = [UInt8](data)
        let type = bytes[0]
        guard type == 0 || type == 8 else { return nil }
        return EchoReply(
            type: type,
            identifier: (UInt16(bytes[4]) << 8) | UInt16(bytes[5]),
            sequence: (UInt16(bytes[6]) << 8) | UInt16(bytes[7])
        )
    }

    /// Internet checksum (RFC 1071): one's complement of the 16-bit word sum.
    public static func inetChecksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        let bytes = [UInt8](data)
        var index = 0
        while index + 1 < bytes.count {
            sum += (UInt32(bytes[index]) << 8) | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return UInt16((~sum) & 0xFFFF)
    }

    // MARK: - BSD socket helpers

    private static func makeSockAddr(_ host: String, port: UInt16 = 0) -> sockaddr_in? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let addrInfo = result else {
            freeaddrinfo(result)
            return nil
        }
        defer { freeaddrinfo(result) }
        var sin = addrInfo.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        sin.sin_port = port.bigEndian
        return sin
    }
}
