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
        try await supabase
            .from("loans")
            .insert(loan)
            .select()
            .single()
            .execute()
            .value
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
