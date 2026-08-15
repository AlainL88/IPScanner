//
//  CustomRangesView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI
import SwiftData

struct CustomRangesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomNetworkRange.sortOrder) private var ranges: [CustomNetworkRange]

    @State private var name = ""
    @State private var cidr = ""
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section(String(localized: "Add network")) {
                TextField(String(localized: "Range name"), text: $name)
                TextField(String(localized: "CIDR"), text: $cidr)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button(String(localized: "Add")) {
                    addRange()
                }
                .disabled(name.isEmpty || cidr.isEmpty)
            }

            Section(String(localized: "Networks")) {
                ForEach(ranges) { range in
                    Label(range.name, systemImage: range.icon)
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(ranges[index])
                    }
                    try? context.save()
                }
            }
        }
        .navigationTitle(String(localized: "Custom networks"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Done")) { dismiss() }
            }
        }
    }

    private func addRange() {
        guard IPv4CIDR.parse(cidr) != nil else {
            validationMessage = String(localized: "Invalid network range")
            return
        }
        let maxOrder = ranges.map(\.sortOrder).max() ?? 0
        context.insert(CustomNetworkRange(name: name, cidr: cidr, sortOrder: maxOrder + 1))
        try? context.save()
        name = ""
        cidr = ""
        validationMessage = nil
    }
}
