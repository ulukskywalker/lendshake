//
//  PaymentRow.swift
//  lendshake
//
//  Created by Assistant on 2/3/26.
//

import SwiftUI

struct PaymentRow: View {
    let payment: Payment
    
    var body: some View {
        HStack {
            if payment.type == .funding {
                // Formatting for the Funding Event
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Money Sent to Borrower")
                            .font(.headline)
                    }
                    Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26) // Align with text above
                }
                
                Spacer()
                
                Text(payment.amount.formatted(.currency(code: "USD")))
                    .bold()
                    .foregroundStyle(.blue)
            } else {
                // Formatting for Repayments
                VStack(alignment: .leading) {
                    Text(payment.amount.formatted(.currency(code: "USD")))
                        .bold()
                    Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(payment.status.title)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.1))
                    .foregroundStyle(statusColor)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .trailing) {
            // Show Proof Button if URL exists (exclude Funding events which utilize type)
            // Funding event handles its own unique display
            if let path = payment.proof_url, payment.type != .funding {
                Button {
                    fetchAndShowProof(path: path)
                } label: {
                    Image(systemName: "photo.badge.checkmark")
                        .foregroundStyle(.gray)
                }
                .padding(.trailing, 80) // Offset from status badge
            }
        }
        .sheet(item: $proofURL) { url in
            NavigationStack {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .navigationTitle("Proof of Payment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { proofURL = nil }
                    }
                }
            }
        }
    }
    
    @State private var proofURL: URL? = nil
    
    private func fetchAndShowProof(path: String) {
        Task {
            do {
                if let url = try await StorageManager.shared.getSignedURL(path: path) {
                    proofURL = url
                }
            } catch {
                print("Failed to get signed URL: \(error)")
            }
        }
    }
    
    var statusColor: Color {
        switch payment.status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}
extension URL: Identifiable {
    public var id: String { absoluteString }
}
