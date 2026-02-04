//
//  LoanManager.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import Observation
import Supabase

struct Loan: Codable, Identifiable, Hashable {
    var id: UUID?
    let lender_id: UUID
    let principal_amount: Double
    let interest_rate: Double
    let repayment_schedule: String
    let late_fee_policy: String
    let maturity_date: Date
    let borrower_name: String?
    let borrower_email: String?
    let borrower_phone: String?
    var status: LoanStatus
    let created_at: Date?
    
    // Agreement Fields
    var agreement_text: String?
    var lender_signed_at: Date?
    var borrower_signed_at: Date?
    var lender_ip: String?
    var borrower_ip: String?
    
    // Helper to initialize for creation
    init(
        lenderId: UUID,
        principal: Double,
        interest: Double,
        schedule: String,
        lateFee: String,
        maturity: Date,
        borrowerName: String?,
        borrowerEmail: String?,
        borrowerPhone: String?
    ) {
        self.id = nil // Supabase will generate
        self.lender_id = lenderId
        self.principal_amount = principal
        self.interest_rate = interest
        self.repayment_schedule = schedule
        self.late_fee_policy = lateFee
        self.maturity_date = maturity
        self.borrower_name = borrowerName
        self.borrower_email = borrowerEmail
        self.borrower_phone = borrowerPhone
        self.status = .draft
        self.created_at = nil
        self.agreement_text = nil
        self.lender_signed_at = nil
        self.borrower_signed_at = nil
        self.lender_ip = nil
        self.borrower_ip = nil
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
            let loans: [Loan] = try await supabase
                .from("loans")
                .select()
                .eq("lender_id", value: user.id)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            print("DEBUG: Fetched \(loans.count) loans.")
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
        let isLender = self.isLender(of: loan)
        
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
            }
            
            let updateData = BorrowerSignUpdate(
                borrower_signed_at: Date(),
                borrower_ip: ipAddress,
                status: .active
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
        }
        
        try await supabase
            .from("loans")
            .update(StatusUpdate(status: status))
            .eq("id", value: id)
            .execute()
        
        try await fetchLoans()
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
}

enum AuthError: Error {
    case notAuthenticated
}
