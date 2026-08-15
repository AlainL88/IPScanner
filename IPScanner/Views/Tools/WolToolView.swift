//
//  WolToolView.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import SwiftUI

struct WolToolView: View {
    @State private var mac: String
    @State private var broadcast: String = "255.255.255.255"
    @State private var isSending = false
    @State private var feedback: (message: String, isError: Bool)?

    init(initialMAC: String) {
        _mac = State(initialValue: initialMAC)
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "MAC Address"), text: $mac)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                TextField("Broadcast", text: $broadcast)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button {
                    send()
                } label: {
                    HStack {
                        if isSending {
                            ProgressView()
                        } else {
                            Label(String(localized: "Send"), systemImage: "bolt.fill")
                        }
                    }
                }
                .disabled(mac.isEmpty || isSending)
            }

            if let feedback {
                Section {
                    Label(feedback.message, systemImage: feedback.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(feedback.isError ? Color.red : Color.statusOnline)
                }
            }
        }
        .navigationTitle(String(localized: "Wake on LAN"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func send() {
        isSending = true
        feedback = nil
        let mac = self.mac
        let broadcast = self.broadcast
        Task {
            let service = WakeOnLANService()
            do {
                try await service.sendWake(mac: mac, broadcast: broadcast)
                await MainActor.run {
                    feedback = (String(localized: "Wake sent"), false)
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    feedback = (error.localizedDescription, true)
                    isSending = false
                }
            }
        }
    }
}
