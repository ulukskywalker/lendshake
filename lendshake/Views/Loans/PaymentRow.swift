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
        HStack(spacing: 12) {
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
            } else if payment.type == .lateFee {
                 // LATE FEE
                 VStack(alignment: .leading) {
                     HStack {
                         Image(systemName: "exclamationmark.circle.fill")
                             .foregroundStyle(.red)
                         Text("Late Fee")
                             .font(.headline)
                             .foregroundStyle(.red)
                     }
                     Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                         .font(.caption)
                         .foregroundStyle(.secondary)
                         .padding(.leading, 26)
                 }
                 
                 Spacer()
                 
                 Text("+" + payment.amount.formatted(.currency(code: "USD")))
                     .bold()
                     .foregroundStyle(.red)
            } else if payment.type == .interest {
                // INTEREST
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "percent")
                            .foregroundStyle(.purple)
                            .padding(6)
                            .background(Circle().fill(Color.purple.opacity(0.1)))
                        Text("Interest Accrued")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 38)
                }
                
                Spacer()
                
                Text("+" + payment.amount.formatted(.currency(code: "USD")))
                    .bold()
                    .foregroundStyle(.purple)
            } else {
                // Formatting for Repayments
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        Text("Repayment")
                            .font(.headline)
                    }
                    
                    HStack(spacing: 4) {
                        Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                        
                        if payment.proof_url != nil {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(payment.amount.formatted(.currency(code: "USD")))
                        .bold()
                    
                    Text(payment.status.title)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.1))
                        .foregroundStyle(statusColor)
                        .cornerRadius(8)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    var statusColor: Color {
        switch payment.status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}
