//
//  LoanService.swift
//  loandry
//
//  Created by Assistant on 2/16/26.
//

import Foundation
import Supabase

struct LoanService {
    static let shared = LoanService()
    private init() {}
    
    func fetchLoans(userId: UUID, email: String) async throws -> [Loan] {
        try await supabase
            .from("loans")
            .select()
            .or("lender_id.eq.\(userId),borrower_email.eq.\(email),borrower_id.eq.\(userId)")
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    
    func fetchPayments(loanId: UUID) async throws -> [Payment] {
        try await supabase
            .from("payments")
            .select()
            .eq("loan_id", value: loanId)
            .order("date", ascending: false)
            .execute()
            .value
    }
    
    func createLoan(_ loan: Loan) async throws -> Loan {
        let insertData = InsertLoan(
            lender_id: loan.lender_id,
            borrower_id: loan.borrower_id,
            principal_amount: loan.principal_amount,
            interest_rate: loan.interest_rate,
            interest_type: loan.interest_type,
            repayment_schedule: loan.repayment_schedule,
            late_fee_policy: loan.late_fee_policy,
            maturity_date: loan.maturity_date,
            first_payment_date: loan.first_payment_date,
            borrower_name: loan.borrower_name,
            borrower_email: loan.borrower_email,
            borrower_phone: loan.borrower_phone,
            lender_name_snapshot: loan.lender_name_snapshot,
            borrower_name_snapshot: loan.borrower_name_snapshot,
            status: loan.status,
            remaining_balance: loan.remaining_balance
        )
        
        return try await supabase
            .from("loans")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value
    }
    
    // Private DTO to ensure we omit 'id' and 'created_at' so Postgres defaults trigger
    private struct InsertLoan: Encodable {
        let lender_id: UUID
        let borrower_id: UUID?
        let principal_amount: Double
        let interest_rate: Double
        let interest_type: LoanInterestType?
        let repayment_schedule: String
        let late_fee_policy: String
        let maturity_date: Date
        let first_payment_date: Date?
        let borrower_name: String?
        let borrower_email: String?
        let borrower_phone: String?
        let lender_name_snapshot: String?
        let borrower_name_snapshot: String?
        let status: LoanStatus
        let remaining_balance: Double?
    }
    
    func deleteLoan(id: UUID) async throws {
        try await supabase
            .from("loans")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    
    func transitionStatus(loanId: UUID, status: LoanStatus, reason: String?) async throws {
        let params: [String: String] = [
            "p_loan_id": loanId.uuidString,
            "p_new_status": status.rawValue,
            "p_reason": reason ?? ""
        ]
        _ = try await supabase
            .rpc("transition_loan_status", params: params)
            .execute()
    }
    
    func submitPayment(_ payment: Payment) async throws {
        try await supabase
            .from("payments")
            .insert(payment)
            .execute()
    }
    
    func approvePayment(paymentId: UUID) async throws {
        let params: [String: String] = ["p_payment_id": paymentId.uuidString]
        _ = try await supabase
            .rpc("approve_payment_and_recompute_balance", params: params)
            .execute()
    }
    
    func rejectPayment(paymentId: UUID, reason: String) async throws {
        let params: [String: String] = [
            "p_payment_id": paymentId.uuidString,
            "p_reason": reason
        ]
        _ = try await supabase
            .rpc("reject_payment_with_reason", params: params)
            .execute()
    }
    
    func updatePaymentStatus(paymentId: UUID, status: PaymentStatus) async throws {
        struct PaymentUpdate: Encodable {
            let status: PaymentStatus
        }
        try await supabase
            .from("payments")
            .update(PaymentUpdate(status: status))
            .eq("id", value: paymentId)
            .execute()
    }
}
