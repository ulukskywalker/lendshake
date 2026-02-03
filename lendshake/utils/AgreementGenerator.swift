//
//  AgreementGenerator.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import Foundation

struct AgreementGenerator {
    static func generate(for loan: Loan) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        
        let principalString = formatter.string(from: NSNumber(value: loan.principal_amount)) ?? "$\(loan.principal_amount)"
        let dateString = loan.maturity_date.formatted(date: .long, time: .omitted)
        let lenderName = "Lender" // Ideally we fetch current user's name, but for MVP "Lender"
        let borrowerName = loan.borrower_name ?? "Borrower"
        
        return """
        PROMISSORY NOTE
        
        1. THE PARTIES
        This Promissory Note ("Note") is made between:
        
        Lender: \(lenderName)
        Borrower: \(borrowerName)
        
        2. THE LOAN
        The Lender agrees to lend the Borrower the principal sum of \(principalString).
        
        3. INTEREST
        This Note bears interest at a rate of \(loan.interest_rate)% per annum.
        
        4. REPAYMENT
        The Borrower agrees to repay the full principal and accrued interest by \(dateString).
        Repayment Schedule: \(loan.repayment_schedule)
        
        5. LATE FEES
        \(loan.late_fee_policy.isEmpty ? "No late fees specified." : "If any payment is not received by the due date, the Borrower agrees to pay a late fee of: \(loan.late_fee_policy) for each overdue installment.")
        
        6. GOVERNING LAW
        This Note shall be governed by the laws of the State of Residence of the Lender.
        
        IN WITNESS WHEREOF, the parties execute this Note as of the dates set forth below.
        """
    }
}
