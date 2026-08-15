//
//  DeviceRowView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

struct DeviceRowView: View {
    let device: ScannedDevice
    let density: RowDensity
    let columns: Set<DeviceColumn>

    var body: some View {
        HStack(spacing: Theme.spacing) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if device.isNew {
                        Text(String(localized: "New"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.statusNew, in: Capsule())
                            .accessibilityLabel(String(localized: "New"))
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            statusDot
        }
        .frame(minHeight: density.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.smallCornerRadius)
                .fill(Color.accentColor.opacity(0.14))
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private var statusDot: some View {
        Circle()
            .fill(device.isOnline ? Color.statusOnline : Color.statusOffline)
            .frame(width: 10, height: 10)
            .accessibilityLabel(device.isOnline ? String(localized: "Online") : String(localized: "Offline"))
    }

    private var icon: String {
        Device.inferredIcon(for: device.hostname, ip: device.ip)
    }

    private var displayName: String {
        device.hostname ?? device.ip
    }

    private var subtitle: String {
        var parts: [String] = [device.ip]
        if columns.contains(.vendor), let vendor = device.vendor, !vendor.isEmpty {
            parts.append(vendor)
        }
        if columns.contains(.mac), let mac = device.mac, !mac.isEmpty {
            parts.append(mac)
        }
        return parts.joined(separator: "  ·  ")
    }
}
