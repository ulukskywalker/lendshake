//
//  LoanManager.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import Observation
import Supabase

extension LoanManager {
    // MARK: - Auto-Events (Catch-Up Logic)
    
    func checkAutoEvents(for loan: Loan) async throws {
        // Only active loans accrue fees
        guard loan.status == .active else { return }
        
        // Check if Late Fee Policy exists
        guard let feeAmount = loan.lateFeeAmount, feeAmount > 0 else { return }
        
        // Grace Period
        let graceDays = loan.gracePeriodDays
        
        // Determine Deadlines
        var deadlines: [Date] = []
        let schedule = loan.repayment_schedule.lowercased()
        let now = Date()
        let calendar = Calendar.current
        
        if schedule.contains("month") {
            // Monthly Schedule
            // Start from creation/start date
            let startDate = loan.created_at ?? loan.maturity_date // Fallback
            // Loop dates until maturity or now
            
            // Safety: Limit loop
            var checkDate = startDate
            let dayComponent = calendar.component(.day, from: startDate)
            
            // Advance to first month anniversary
            if let firstDue = calendar.date(byAdding: .month, value: 1, to: startDate) {
                checkDate = firstDue
            }
            
            while checkDate <= now {
                deadlines.append(checkDate)
                guard let next = calendar.date(byAdding: .month, value: 1, to: checkDate) else { break }
                checkDate = next
            }
        } else {
            // Lump Sum / Default
            deadlines.append(loan.maturity_date)
        }
        
        // Fetch existing fees
        let existingPayments = try await fetchPayments(for: loan)
        
        // 1. Calculate Missing Late Fees
        let missingFeesCount = LoanMath.calculateMissingLateFees(for: loan, existingPayments: existingPayments)
        
        var feesToAdd: [Payment] = []
        var balanceIncrease: Double = 0
        
        if missingFeesCount > 0 {
            print("DEBUG: Catch-Up found \(missingFeesCount) missing late fees.")
            
            for _ in 0..<missingFeesCount {
                let newFee = Payment(
                    loanId: loan.id!,
                    amount: feeAmount,
                    date: now, // Created now
                    type: .lateFee
                )
                feesToAdd.append(newFee)
                balanceIncrease += feeAmount
            }
        }
        
        // Execute Batch
        if !feesToAdd.isEmpty {
            for var fee in feesToAdd {
                fee.status = .approved
                try await supabase.from("payments").insert(fee).execute()
            }
            // Update Balance logic...
            let currentBalance = loan.remaining_balance ?? loan.principal_amount
            let newBalance = currentBalance + balanceIncrease
            
            // struct BalanceUpdate removed - using file-level helper
            try await supabase.from("loans").update(BalanceUpdate(remaining_balance: newBalance, status: nil, release_document_text: nil)).eq("id", value: loan.id!).execute()
            
            try await fetchLoans()
        }
        
        // 2. Check Interest
        try await checkInterest(for: loan)
    }
    
    private func checkInterest(for loan: Loan) async throws {
        // Only active loans accrue interest
        guard loan.status == .active else { return }
        
        // Handle Fixed vs Percentage
        if loan.interest_type == .fixed {
            // FIXED FEE LOGIC
            // Ensure the one-time fee is applied
            guard loan.interest_rate > 0 else { return } // Here rate is the amount
            
            let existingPayments = try await fetchPayments(for: loan)
            let hasInterest = existingPayments.contains { $0.type == .interest }
            
            if !hasInterest {
                // Apply the One-Time Fixed Fee
                let feePayment = Payment(
                    loanId: loan.id!,
                    amount: loan.interest_rate, // stored as double
                    date: loan.created_at ?? Date(),
                    type: .interest
                )
                
                var payment = feePayment
                payment.status = .approved
                try await supabase.from("payments").insert(payment).execute()
                
                // Update Balance
                let currentBalance = loan.remaining_balance ?? loan.principal_amount
                let newBalance = currentBalance + loan.interest_rate
                
                try await supabase
                    .from("loans")
                    .update(BalanceUpdate(remaining_balance: newBalance, status: nil, release_document_text: nil))
                    .eq("id", value: loan.id!)
                    .execute()
                
                try await fetchLoans()
            }
            
        } else {
            // PERCENTAGE LOGIC (Monthly)
            guard loan.interest_rate > 0 else { return }
            
            let calendar = Calendar.current
            let now = Date()
            let start = loan.created_at ?? loan.maturity_date // Fallback
            
            // Interest accrues monthly on the anniversary of the creation date
            // e.g. Created Jan 5 -> Interest on Feb 5, Mar 5...
            
            var interestDates: [Date] = []
            var checkDate = start
            
            // Advance to first month
            if let first = calendar.date(byAdding: .month, value: 1, to: start) {
                checkDate = first
            } else { return }
            
            while checkDate <= now {
                interestDates.append(checkDate)
                guard let next = calendar.date(byAdding: .month, value: 1, to: checkDate) else { break }
                checkDate = next
            }
            
            if interestDates.isEmpty { return }
            
            // Fetch existing Interest payments to avoid duplicates
            let existingPayments = try await fetchPayments(for: loan)
            
            // Calculate Missing Interest
            let (missingCount, monthlyAmount) = LoanMath.calculateMissingInterest(for: loan, existingPayments: existingPayments)
            
            var interestToAdd: [Payment] = []
            var balanceIncrease: Double = 0
            
            if missingCount > 0 {
                print("DEBUG: Catch-Up found \(missingCount) missing interest payments.")
                
                for _ in 0..<missingCount {
                    let newInterest = Payment(
                        loanId: loan.id!,
                        amount: monthlyAmount,
                        date: now, // Recorded NOW
                        type: .interest
                    )
                    interestToAdd.append(newInterest)
                    balanceIncrease += monthlyAmount
                }
            }
            
            // Batch Insert
            if !interestToAdd.isEmpty {
                for var payment in interestToAdd {
                    payment.status = .approved
                    try await supabase.from("payments").insert(payment).execute()
                }
                
                // Update Balance
                let currentBalance = loan.remaining_balance ?? loan.principal_amount
                let newBalance = currentBalance + balanceIncrease
                
                try await supabase
                    .from("loans")
                    .update(BalanceUpdate(remaining_balance: newBalance, status: nil, release_document_text: nil))
                    .eq("id", value: loan.id!)
                    .execute()
                
                try await fetchLoans()
            }
        }
    }
}




@MainActor
@Observable
class LoanManager {
    var loans: [Loan] = []
    var isLoading: Bool = false
    
    func fetchLoans() async throws {
        self.isLoading = true
        defer { self.isLoading = false }
        
        guard let user = supabase.auth.currentUser else {
            print("DEBUG: Fetch Loans - No Current User")
            return
        }
        
        do {
            let userEmail = user.email ?? ""
            
            let loans: [Loan] = try await supabase
                .from("loans")
                .select()
                .or("lender_id.eq.\(user.id),borrower_email.eq.\(userEmail),borrower_id.eq.\(user.id)")
                .order("created_at", ascending: false)
                .execute()
                .value
            
            print("DEBUG: Fetched \(loans.count) loans for \(userEmail) (ID: \(user.id))")
            self.loans = loans
        } catch {
            print("DEBUG: Fetch Loans Error: \(error)")
            // If table doesn't exist, this will print.
            throw error
        }
    }
    
    func createDraftLoan(
        principal: Double,
        interest: Double,
        interestType: LoanInterestType = .percentage,
        schedule: String,
        lateFee: String,
        maturity: Date,
        borrowerName: String?,
        borrowerEmail: String?,
        borrowerPhone: String?
    ) async throws -> Loan {
        self.isLoading = true
        defer { self.isLoading = false }
        
        guard let user = supabase.auth.currentUser else {
            throw AuthError.notAuthenticated
        }
        
        let loan = Loan(
            lenderId: user.id,
            principal: principal,
            interest: interest,
            interestType: interestType,
            schedule: schedule,
            lateFee: lateFee,
            maturity: maturity,
            borrowerName: borrowerName,
            borrowerEmail: borrowerEmail,
            borrowerPhone: borrowerPhone
        )
        
        // Supabase Insert & Return
        let createdLoan: Loan = try await supabase
            .from("loans")
            .insert(loan)
            .select() // Return the created row
            .single()
            .execute()
            .value
        
        // Refresh local list
        try await fetchLoans()
        
        print("Loan draft created successfully.")
        return createdLoan
    }
    func signLoan(loan: Loan) async throws {
        self.isLoading = true
        defer { self.isLoading = false }
        
        guard let _ = supabase.auth.currentUser else {
            throw AuthError.notAuthenticated
        }
        
        // Fetch Audit Trail IP
        let ipAddress = await fetchPublicIP()
        guard let user = supabase.auth.currentUser else { return }
        let isLender = (loan.lender_id == user.id)
        
        guard let loanId = loan.id else { return }
        
        if isLender {
            // LENDER SIGNING
            var updatedLoan = loan
            updatedLoan.lender_signed_at = Date()
            
            // Generate agreement if missing
            if updatedLoan.agreement_text == nil {
                updatedLoan.agreement_text = AgreementGenerator.generate(for: loan)
            }
            
            struct LenderSignUpdate: Encodable {
                let lender_signed_at: Date
                let agreement_text: String
                let lender_ip: String?
                let status: LoanStatus
            }
            
            let updateData = LenderSignUpdate(
                lender_signed_at: Date(),
                agreement_text: updatedLoan.agreement_text!,
                lender_ip: ipAddress,
                status: .sent
            )
            
            try await supabase
                .from("loans")
                .update(updateData)
                .eq("id", value: loanId)
                .execute()
            
        } else {
            // BORROWER SIGNING
            // Status moves to ACTIVE once borrower signs
            struct BorrowerSignUpdate: Encodable {
                let borrower_signed_at: Date
                let borrower_ip: String?
                let status: LoanStatus
                let borrower_id: UUID // CLAIM the loan
            }
            
            let updateData = BorrowerSignUpdate(
                borrower_signed_at: Date(),
                borrower_ip: ipAddress,
                status: .approved, // Move to approved (waiting for funds), not active yet
                borrower_id: user.id
            )
            
            try await supabase
                .from("loans")
                .update(updateData)
                .eq("id", value: loanId)
                .execute()
        }
        
        // Refresh
        try await fetchLoans()
        print("Loan signed by \(isLender ? "Lender" : "Borrower"). Status updated. IP: \(ipAddress ?? "Unknown")")
    }
    
    func deleteLoan(_ loan: Loan) async throws {
        guard loan.status == .draft else { return } // Only allow deleting drafts
        guard let id = loan.id else { return }
        
        try await supabase
            .from("loans")
            .delete()
            .eq("id", value: id)
            .execute()
        
        try await fetchLoans()
    }
    
    func updateLoanStatus(_ loan: Loan, status: LoanStatus) async throws {
        guard let id = loan.id else { return }
        
        struct StatusUpdate: Encodable {
            let status: LoanStatus
            let remaining_balance: Double?
        }
        
        // If forgiving, set balance to 0. Otherwise keep existing (nil in update struct means ignore/don't change? No, Encodable sends null. We need optional encode).
        // Actually, Supabase update partial: Only fields present in JSON are updated.
        // Swift Encodable sends nil as null or omits? Standard JSONEncoder handling.
        // Let's explicitly separate the structs or logic given we want to change balance only sometimes.
        
        if status == .forgiven {
            struct ForgiveUpdate: Encodable {
                let status: LoanStatus
                let remaining_balance: Double
            }
            try await supabase
                .from("loans")
                .update(ForgiveUpdate(status: status, remaining_balance: 0))
                .eq("id", value: id)
                .execute()
        } else {
            struct SimpleUpdate: Encodable {
                let status: LoanStatus
            }
            try await supabase
                .from("loans")
                .update(SimpleUpdate(status: status))
                .eq("id", value: id)
                .execute()
        }
        
        try await fetchLoans()
    }
    
    func confirmFunding(loan: Loan, proofURL: String?) async throws {
        guard loan.status == .approved else { return }
        guard let loanId = loan.id else { return }
        
        // 1. Create Funding Transaction (Auto-approved)
        var fundingPayment = Payment(
            loanId: loanId,
            amount: loan.principal_amount,
            date: Date(),
            type: .funding,
            proofURL: proofURL
        )
        fundingPayment.status = .approved
        
        try await supabase
            .from("payments")
            .insert(fundingPayment)
            .execute()
        
        // 2. Set Status to Funding Sent (Waiting for borrower confirmation)
        try await updateLoanStatus(loan, status: .funding_sent)
    }
    
    func confirmReceipt(loan: Loan) async throws {
        guard loan.status == .funding_sent else { return }
        // Borrower confirms receipt -> ACTIVE
        try await updateLoanStatus(loan, status: .active)
    }
    
    private func fetchPublicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return String(data: data, encoding: .utf8)
        } catch {
            print("Failed to fetch IP: \(error)")
            return nil
        }
    }
    
    func isLender(of loan: Loan) -> Bool {
        guard let user = supabase.auth.currentUser else { return false }
        return loan.lender_id == user.id
    }

    
    // MARK: - Payment Logic
    
    func fetchPayments(for loan: Loan) async throws -> [Payment] {
        guard let loanId = loan.id else { return [] }
        
        let payments: [Payment] = try await supabase
            .from("payments")
            .select()
            .eq("loan_id", value: loanId)
            .order("date", ascending: false) // Newest first
            .execute()
            .value
            
        return payments
    }
    
    func submitPayment(for loan: Loan, amount: Double, date: Date, proofURL: String?) async throws {
        guard let loanId = loan.id else { return }
        
        let payment = Payment(loanId: loanId, amount: amount, date: date, proofURL: proofURL)
        
        try await supabase
            .from("payments")
            .insert(payment)
            .execute()
            
        // No need to update loan balance yet, only on approval
    }
    
    func updatePaymentStatus(payment: Payment, newStatus: PaymentStatus, loan: Loan) async throws {
        guard let paymentId = payment.id else { return }
        guard let loanId = loan.id else { return }
        
        // 1. Update Payment
        struct PaymentUpdate: Encodable {
            let status: PaymentStatus
        }
        
        try await supabase
            .from("payments")
            .update(PaymentUpdate(status: newStatus))
            .eq("id", value: paymentId)
            .execute()
            
        // 2. If Approved, update Loan Balance
        if newStatus == .approved {
            // We need to fetch the fresh current balance to be safe, or calculate based on local 'liveLoan'
            // For MVP, we'll trust the local + deduction, or better yet, trigger a DB function if possible.
            // But here, client-side logic:
            
            let currentBalance = loan.remaining_balance ?? loan.principal_amount
            let newBalance = max(0, currentBalance - payment.amount)
            
            // struct BalanceUpdate removed - using file-level helper
            
            var nextDetails: BalanceUpdate
            
            if newBalance <= 0 {
                // Generate Release Document
                let releaseDoc = AgreementGenerator.generateRelease(for: loan)
                nextDetails = BalanceUpdate(remaining_balance: 0, status: .completed, release_document_text: releaseDoc)
            } else {
                nextDetails = BalanceUpdate(remaining_balance: newBalance, status: nil, release_document_text: nil)
            }
            
            try await supabase
                .from("loans")
                .update(nextDetails)
                .eq("id", value: loanId)
                .execute()
                
            // Refresh loans to get new balance
            try await fetchLoans()
        }
    }
}

// Helper struct for update
struct BalanceUpdate: Encodable {
    let remaining_balance: Double
    let status: LoanStatus?
    let release_document_text: String?
}

enum AuthError: Error {
    case notAuthenticated
}
