//
//  AgreementGenerator.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import Foundation

struct AgreementGenerator {
    static func generate(for loan: Loan, lenderName: String? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        
        let principalString = formatter.string(from: NSNumber(value: loan.principal_amount)) ?? "$\(loan.principal_amount)"
        let dateString = loan.maturity_date.formatted(date: .long, time: .omitted)
        let trimmedLenderName = lenderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLenderName = (trimmedLenderName?.isEmpty == false ? trimmedLenderName : nil) ?? "Lender"
        let borrowerName = loan.borrower_name ?? "Borrower"
        
        let interest = loan.interest_rate
        let interestClause: String
        
        if interest == 0 {
            interestClause = "This Note shall bear no interest."
        } else {
            interestClause = "This Note bears interest at a rate of \(interest)% per annum."
        }
        
        return """
        PROMISSORY NOTE
        
        1. THE PARTIES
        This Promissory Note ("Note") is made between:
        
        Lender: \(resolvedLenderName)
        Borrower: \(borrowerName)
        
        2. THE LOAN
        The Lender agrees to lend the Borrower the principal sum of \(principalString).
        
        3. INTEREST
        \(interestClause)
        
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
    
    static func generateRelease(for loan: Loan) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        
        let principalString = formatter.string(from: NSNumber(value: loan.principal_amount)) ?? "$\(loan.principal_amount)"
        let dateString = Date().formatted(date: .long, time: .omitted)
        let borrowerName = loan.borrower_name ?? "Borrower"
        
        return """
        RELEASE OF PROMISSORY NOTE
        
        Date: \(dateString)
        
        1. RECITALS
        Reference is made to that certain Promissory Note in the original principal amount of \(principalString) made by \(borrowerName) ("Borrower").
        
        2. SATISFACTION
        The Lender acknowledges that the Borrower has satisfied all obligations under the Note. The debt is hereby discharged in full.
        
        3. RELEASE
        The Lender hereby releases and forever discharges the Borrower from any and all claims, demands, and liabilities arising out of or relating to the Note.
        
        4. CANCELLATION
        The original Note is hereby cancelled and rendered void.
        
        [ ELECTRONICALLY GENERATED ON LENDSHAKE ]
        """
    }
}
