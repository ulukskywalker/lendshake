//
//  LoanHeaderCard.swift
//  lendshake
//
//  Created by Assistant on 2/4/26.
//

import SwiftUI

struct LoanHeaderCard: View {
    let loan: Loan
    let isLender: Bool
    
    var isOverdue: Bool {
        Date() > loan.nextPaymentDate
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(isLender ? "YOU ARE LENDING" : "YOU ARE BORROWING")
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background((isLender ? Color.lsPrimary : Color.orange).opacity(0.1))
                .foregroundStyle(isLender ? Color.lsPrimary : Color.orange)
                .cornerRadius(20)
            
            Text(loan.status.title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text((loan.remaining_balance ?? loan.principal_amount).formatted(.currency(code: "USD")))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(isLender ? Color.lsPrimary : Color.orange)
            
            Text("Remaining Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if !isLender && loan.status == .active {
                Divider()
                    .padding(.vertical, 8)
                
                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("Next Due")
                            .font(.caption)
                            .foregroundStyle(isOverdue ? .red : .secondary)
                        
                        if isOverdue {
                            Text("OVERDUE")
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(4)
                        } else {
                            Text(loan.nextPaymentDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.headline)
                                .bold()
                        }
                    }
                    
                    VStack(spacing: 4) {
                        Text("Min Payment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(loan.minimumPaymentAmount.formatted(.currency(code: "USD")))
                            .font(.headline)
                            .bold()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
