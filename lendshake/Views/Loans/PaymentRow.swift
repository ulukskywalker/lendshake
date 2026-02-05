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
                    
                    HStack(spacing: 4) {
                        Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if payment.proof_url != nil {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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
