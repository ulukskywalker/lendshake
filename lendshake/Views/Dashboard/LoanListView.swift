//
//  LoanListView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct LoanListView: View {
    let loans: [Loan]
    @Environment(LoanManager.self) var loanManager
    
    var body: some View {
        List(loans) { loan in
            NavigationLink(destination: LoanDetailView(loan: loan)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if loanManager.isLender(of: loan) {
                            Text("Lending to")
                                .font(.caption)
                                .foregroundStyle(.gray)
                            Text(loan.borrower_name ?? "Unknown")
                                .font(.headline)
                        } else {
                            Text("Borrowing from")
                                .font(.caption)
                                .foregroundStyle(.gray)
                            Text("Lender") // We need to fetch Lender Profile to show name, placeholder for now
                                .font(.headline)
                        }
                    }
                    HStack {
                        LoanStatusBadge(status: loan.status)
                        
                        Spacer()
                        
                        Text(loan.principal_amount, format: .currency(code: "USD"))
                            .bold()
                    }
                }
            }
        }
    }
}

#Preview {
    LoanListView(loans: [])
}
