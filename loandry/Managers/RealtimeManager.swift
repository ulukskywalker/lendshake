//
//  RealtimeManager.swift
//  loandry
//
//  Created by Assistant on 2/13/26.
//

import Foundation
import Supabase
import SwiftUI

protocol RealtimeManagerDelegate: AnyObject {
    func handleLoanInsert(_ loan: Loan)
    func handleLoanUpdate(_ loan: Loan, oldStatus: LoanStatus?)
    func handleLoanDelete(_ deleted: RealtimeManager.DeletedRecord)
    func handlePaymentInsert(payment: Payment)
    func handlePaymentUpdate(payment: Payment, oldStatus: PaymentStatus?)
    func getLoans() -> [Loan]
}

@MainActor
class RealtimeManager {
    private let logger = AppLogger(.loans)
    weak var delegate: RealtimeManagerDelegate?

    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeChangesTask: Task<Void, Never>?
    private var realtimeSubscriptionUserID: UUID?
    private var paymentsRealtimeChannel: RealtimeChannelV2?
    private var paymentsRealtimeChangesTask: Task<Void, Never>?
    private var paymentsRealtimeSubscriptionUserID: UUID?
    
    private static let realtimeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func subscribe(for user: User) {
        subscribeToLoans(for: user)
        subscribeToPayments(for: user)
    }

    func unsubscribe() {
        realtimeChangesTask?.cancel(); realtimeChangesTask = nil
        if let existing = realtimeChannel { Task { await existing.unsubscribe() }; realtimeChannel = nil }
        
        paymentsRealtimeChangesTask?.cancel(); paymentsRealtimeChangesTask = nil
        if let existing = paymentsRealtimeChannel { Task { await existing.unsubscribe() }; paymentsRealtimeChannel = nil }
    }

    private func subscribeToLoans(for user: User) {
        if realtimeSubscriptionUserID == user.id, realtimeChannel != nil, realtimeChangesTask != nil { return }
        unsubscribe()
        
        let channel = supabase.realtimeV2.channel("public:loans")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "loans")
        
        realtimeChangesTask = Task {
            for await change in changes {
                if Task.isCancelled { break }
                await handleLoanChange(change, userId: user.id, userEmail: user.email ?? "")
            }
        }
        
        Task {
            do {
                try await channel.subscribeWithError()
                self.realtimeChannel = channel
                self.realtimeSubscriptionUserID = user.id
            } catch {
                logger.error("Loans realtime subscribe error: \(error)")
                unsubscribe()
            }
        }
    }
    
    private func handleLoanChange(_ change: AnyAction, userId: UUID, userEmail: String) async {
        let decoder = Self.realtimeDecoder
        switch change {
        case .insert(let action):
            guard let loan = try? action.decodeRecord(as: Loan.self, decoder: decoder) else { return }
            if loan.lender_id == userId || loan.borrower_id == userId || loan.borrower_email == userEmail {
                delegate?.handleLoanInsert(loan)
            }
        case .update(let action):
            guard let loan = try? action.decodeRecord(as: Loan.self, decoder: decoder) else { return }
            let previousStatus = decodeStatus(from: action.oldRecord, type: LoanStatusSnapshot.self)?.status
            delegate?.handleLoanUpdate(loan, oldStatus: previousStatus)
        case .delete(let action):
            guard let data = try? JSONEncoder().encode(action.oldRecord),
                  let deleted = try? decoder.decode(DeletedRecord.self, from: data) else { return }
            delegate?.handleLoanDelete(deleted)
        }
    }
    
    private func subscribeToPayments(for user: User) {
        if paymentsRealtimeSubscriptionUserID == user.id, paymentsRealtimeChannel != nil, paymentsRealtimeChangesTask != nil { return }
        
        paymentsRealtimeChangesTask?.cancel(); paymentsRealtimeChangesTask = nil
        if let existing = paymentsRealtimeChannel { Task { await existing.unsubscribe() }; paymentsRealtimeChannel = nil }

        let channel = supabase.realtimeV2.channel("public:payments")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "payments")

        paymentsRealtimeChangesTask = Task {
            for await change in changes {
                if Task.isCancelled { break }
                await handlePaymentChange(change)
            }
        }

        Task {
            do {
                try await channel.subscribeWithError()
                self.paymentsRealtimeChannel = channel
                self.paymentsRealtimeSubscriptionUserID = user.id
            } catch {
                logger.error("Payments realtime subscribe error: \(error)")
                paymentsRealtimeChangesTask?.cancel(); paymentsRealtimeChangesTask = nil
            }
        }
    }

    private func handlePaymentChange(_ change: AnyAction) async {
        let decoder = Self.realtimeDecoder
        switch change {
        case .insert(let action):
            guard let payment = try? action.decodeRecord(as: Payment.self, decoder: decoder) else { return }
            delegate?.handlePaymentInsert(payment: payment)
        case .update(let action):
            guard let payment = try? action.decodeRecord(as: Payment.self, decoder: decoder) else { return }
            let oldStatus = decodeStatus(from: action.oldRecord, type: PaymentStatusSnapshot.self)?.status
            guard oldStatus != payment.status else { return }
            delegate?.handlePaymentUpdate(payment: payment, oldStatus: oldStatus)
        case .delete: break
        }
    }

    private func decodeStatus<T: Decodable>(from oldRecord: [String: AnyJSON], type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(oldRecord) else { return nil }
        return try? Self.realtimeDecoder.decode(T.self, from: data)
    }

    private struct LoanStatusSnapshot: Decodable { let status: LoanStatus? }
    private struct PaymentStatusSnapshot: Decodable { let status: PaymentStatus? }
    struct DeletedRecord: Decodable { let id: UUID }
    struct RepaymentAttentionRecord: Decodable { let loan_id: UUID; let status: PaymentStatus; let date: Date }
}
