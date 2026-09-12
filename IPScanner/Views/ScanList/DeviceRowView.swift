//
//  DeviceRowView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

struct DeviceRowView: View {
    let device: ScannedDevice
    /// Resolved label: custom name (persisted) > hostname > IP.
    let displayName: String
    /// Resolved icon: custom icon (persisted) > inferred from hostname/IP.
    let icon: String
    let density: RowDensity
    let columns: Set<DeviceColumn>

    var body: some View {
        HStack(spacing: Theme.spacing) {
            iconBadge

            VStack(alignment: .leading, spacing: density == .compact ? 2 : 3) {
                titleRow
                subtitleContent
            }

            Spacer(minLength: 8)

            if columns.contains(.status) {
                statusIndicator
            }
        }
        .frame(minHeight: density.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(displayName)
                .font(isDisplayNameAnIP ? .system(.body, design: .monospaced).weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if device.isNew {
                Text(String(localized: "New"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.statusNew, in: Capsule())
                    .accessibilityLabel(String(localized: "New"))
            }
        }
    }

    // MARK: - Subtitle Content

    @ViewBuilder
    private var subtitleContent: some View {
        switch density {
        case .compact:
            let allItems = networkInfoItems + hardwareInfoItems
            if !allItems.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(allItems.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            bulletSeparator
                        }
                        itemLabel(item)
                    }
                }
                .lineLimit(1)
            }
        case .comfortable, .spacious:
            let net = networkInfoItems
            let hw = hardwareInfoItems
            if !net.isEmpty && !hw.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        ForEach(Array(net.enumerated()), id: \.offset) { index, item in
                            if index > 0 { bulletSeparator }
                            itemLabel(item)
                        }
                    }
                    .lineLimit(1)

                    HStack(spacing: 5) {
                        ForEach(Array(hw.enumerated()), id: \.offset) { index, item in
                            if index > 0 { bulletSeparator }
                            itemLabel(item)
                        }
                    }
                    .lineLimit(1)
                }
            } else if !net.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(net.enumerated()), id: \.offset) { index, item in
                        if index > 0 { bulletSeparator }
                        itemLabel(item)
                    }
                }
                .lineLimit(1)
            } else if !hw.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(hw.enumerated()), id: \.offset) { index, item in
                        if index > 0 { bulletSeparator }
                        itemLabel(item)
                    }
                }
                .lineLimit(1)
            }
        }
    }

    private var bulletSeparator: some View {
        Text("·")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary.opacity(0.6))
    }

    @ViewBuilder
    private func itemLabel(_ item: SubtitleItem) -> some View {
        HStack(spacing: 3) {
            if let iconName = item.iconName {
                Image(systemName: iconName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(item.text)
                .font(item.isMonospaced ? .system(.caption, design: .monospaced) : .caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Subtitle Items Parsing

    private var isDisplayNameAnIP: Bool {
        displayName == device.ip
    }

    private var networkInfoItems: [SubtitleItem] {
        var items: [SubtitleItem] = []
        if columns.contains(.ip), displayName != device.ip {
            items.append(SubtitleItem(text: device.ip, isMonospaced: true, iconName: nil))
        }
        if columns.contains(.hostname), let hostname = device.hostname, !hostname.isEmpty, displayName != hostname {
            items.append(SubtitleItem(text: hostname, isMonospaced: false, iconName: nil))
        }
        return items
    }

    private var hardwareInfoItems: [SubtitleItem] {
        var items: [SubtitleItem] = []
        if columns.contains(.vendor), let vendor = device.vendor, !vendor.isEmpty {
            items.append(SubtitleItem(text: vendor, isMonospaced: false, iconName: nil))
        }
        if columns.contains(.mac), let mac = device.mac, !mac.isEmpty {
            items.append(SubtitleItem(text: mac, isMonospaced: true, iconName: nil))
        }
        if columns.contains(.lastSeen) {
            items.append(SubtitleItem(text: relativeLastSeen, isMonospaced: false, iconName: "clock"))
        }
        return items
    }

    private var relativeLastSeen: String {
        let elapsed = Date().timeIntervalSince(device.lastSeen)
        if elapsed < 60 {
            return String(localized: "Just now")
        } else if elapsed < 3600 {
            let minutes = max(1, Int(elapsed / 60))
            return String(format: String(localized: "%ldm ago"), minutes)
        } else if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            return String(format: String(localized: "%ldh ago"), hours)
        } else {
            return device.lastSeen.formatted(date: .abbreviated, time: .omitted)
        }
    }

    // MARK: - Icon Badge & Status

    private var iconBadge: some View {
        let size: CGFloat = {
            switch density {
            case .compact: return 34
            case .comfortable: return 42
            case .spacious: return 48
            }
        }()

        let symbolSize: CGFloat = {
            switch density {
            case .compact: return 16
            case .comfortable: return 20
            case .spacious: return 24
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: density == .compact ? 8 : 10)
                .fill(Color.accentColor.opacity(0.12))
            Image(systemName: icon)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(device.isOnline ? Color.statusOnline : Color.statusOffline)
                .frame(width: 9, height: 9)
        }
        .accessibilityLabel(device.isOnline ? String(localized: "Online") : String(localized: "Offline"))
    }
}

private struct SubtitleItem {
    let text: String
    let isMonospaced: Bool
    let iconName: String?
}
