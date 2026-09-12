//
//  AvailableIPRowView.swift
//  IPScanner
//
//  Created by Alain Lima on 12/09/2026.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AvailableIPRowView: View {
    let ip: String
    let cidr: String?
    let density: RowDensity

    @State private var isCopied = false

    var body: some View {
        HStack(spacing: 14) {
            iconBadge

            VStack(alignment: .leading, spacing: density == .compact ? 3 : 5) {
                Text(ip)
                    .font(.system(size: titleFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                subtitleRow
            }

            Spacer(minLength: 8)

            copyButton
        }
        .frame(minHeight: density.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleFontSize: CGFloat {
        switch density {
        case .compact: return 13.5
        case .comfortable: return 14.5
        case .spacious: return 16
        }
    }

    private var subtitleFontSize: CGFloat {
        switch density {
        case .compact: return 11.5
        case .comfortable: return 12
        case .spacious: return 13
        }
    }

    private var subtitleRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.statusOnline)
                    .frame(width: 7, height: 7)
                Text(String(localized: "Available"))
                    .font(.system(size: subtitleFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let cidr {
                Text("·")
                    .font(.system(size: subtitleFontSize, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.6))

                Text(cidr)
                    .font(.system(size: subtitleFontSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private var iconBadge: some View {
        let size: CGFloat = {
            switch density {
            case .compact: return 30
            case .comfortable: return 36
            case .spacious: return 42
            }
        }()

        let symbolSize: CGFloat = {
            switch density {
            case .compact: return 15
            case .comfortable: return 18
            case .spacious: return 21
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: density == .compact ? 6 : 8)
                .fill(Color.statusOnline.opacity(0.12))
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(Color.statusOnline)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var copyButton: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                if isCopied {
                    Text(String(localized: "Copied"))
                        .font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(isCopied ? Color.statusOnline : Color.secondary)
            .padding(.horizontal, isCopied ? 10 : 8)
            .padding(.vertical, 6)
            .background(
                isCopied ? Color.statusOnline.opacity(0.12) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCopied ? String(localized: "Copied") : String(localized: "Copy IP"))
    }

    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = ip
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        #endif

        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}
