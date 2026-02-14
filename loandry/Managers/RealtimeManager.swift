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
        realtimeChangesTask?.cancel()
        realtimeChangesTask = nil
        if let existing = realtimeChannel {
            Task { await existing.unsubscribe() }
            realtimeChannel = nil
        }
        paymentsRealtimeChangesTask?.cancel()
        paymentsRealtimeChangesTask = nil
        if let existing = paymentsRealtimeChannel {
            Task { await existing.unsubscribe() }
            paymentsRealtimeChannel = nil
        }
    }

    private func subscribeToLoans(for user: User) {
        if realtimeSubscriptionUserID == user.id,
           realtimeChannel != nil,
           realtimeChangesTask != nil {
            return
        }
        
        unsubscribe()
        
        let channel = supabase.realtimeV2.channel("public:loans")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "loans"
        )
        
        realtimeChangesTask = Task {
            for await change in changes {
                if Task.isCancelled { break }
                await handleRealtimeChange(change, userId: user.id, userEmail: user.email ?? "")
            }
        }
        
        Task {
            do {
                try await channel.subscribeWithError()
                self.realtimeChannel = channel
                self.realtimeSubscriptionUserID = user.id
            } catch {
                await AlertReporter.shared.capture(
                    error: error,
                    category: .loans,
                    summary: "Loans realtime subscription failed",
                    severity: .critical,
                    metadata: ["user_id": user.id.uuidString]
                )
                unsubscribe()
            }
        }
    }
    
    private func handleRealtimeChange(_ change: AnyAction, userId: UUID, userEmail: String) async {
        let decoder = Self.realtimeDecoder
        
        switch change {
        case .insert(let action):
            guard let loan = try? action.decodeRecord(as: Loan.self, decoder: decoder) else { return }
            if shouldInclude(loan, userId: userId, userEmail: userEmail) {
                delegate?.handleLoanInsert(loan)
            }
        case .update(let action):
            guard let loan = try? action.decodeRecord(as: Loan.self, decoder: decoder) else { return }
            let previousStatus = decodeLoanStatus(from: action.oldRecord)
            delegate?.handleLoanUpdate(loan, oldStatus: previousStatus)

        case .delete(let action):
            let oldRecord = action.oldRecord
            guard let data = try? JSONEncoder().encode(oldRecord),
                  let deleted = try? decoder.decode(DeletedRecord.self, from: data) else { return }
            delegate?.handleLoanDelete(deleted)
        }
    }
    
    struct DeletedRecord: Decodable {
        let id: UUID
    }
    
    private func shouldInclude(_ loan: Loan, userId: UUID, userEmail: String) -> Bool {
        return loan.lender_id == userId ||
               loan.borrower_id == userId ||
               loan.borrower_email == userEmail
    }

    private func decodeLoanStatus(from oldRecord: [String: AnyJSON]) -> LoanStatus? {
        guard let data = try? JSONEncoder().encode(oldRecord),
              let snapshot = try? Self.realtimeDecoder.decode(LoanStatusSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.status
    }

    private struct LoanStatusSnapshot: Decodable {
        let status: LoanStatus?
    }

    private func subscribeToPayments(for user: User) {
        if paymentsRealtimeSubscriptionUserID == user.id,
           paymentsRealtimeChannel != nil,
           paymentsRealtimeChangesTask != nil {
            return
        }

        paymentsRealtimeChangesTask?.cancel()
        paymentsRealtimeChangesTask = nil
        if let existing = paymentsRealtimeChannel {
            Task { await existing.unsubscribe() }
            paymentsRealtimeChannel = nil
        }

        let channel = supabase.realtimeV2.channel("public:payments")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "payments"
        )

        paymentsRealtimeChangesTask = Task {
            for await change in changes {
                if Task.isCancelled { break }
                await handlePaymentRealtimeChange(change, currentUserID: user.id)
            }
        }

        Task {
            do {
                try await channel.subscribeWithError()
                self.paymentsRealtimeChannel = channel
                self.paymentsRealtimeSubscriptionUserID = user.id
            } catch {
                await AlertReporter.shared.capture(
                    error: error,
                    category: .loans,
                    summary: "Payments realtime subscription failed",
                    severity: .critical,
                    metadata: ["user_id": user.id.uuidString]
                )
                paymentsRealtimeChangesTask?.cancel()
                paymentsRealtimeChangesTask = nil
            }
        }
    }

    private func handlePaymentRealtimeChange(_ change: AnyAction, currentUserID: UUID) async {
        let decoder = Self.realtimeDecoder

        switch change {
        case .insert(let action):
            guard let payment = try? action.decodeRecord(as: Payment.self, decoder: decoder) else { return }
            delegate?.handlePaymentInsert(payment: payment)
            
            guard let loans = delegate?.getLoans(),
                  let loan = loans.first(where: { $0.id == payment.loan_id }),
                  loan.lender_id == currentUserID,
                  let paymentID = payment.id else {
                return
            }
            
            await NotificationManager.shared.postEventNotification(
                eventID: "payment.\(paymentID.uuidString).pending",
                title: "Payment Needs Approval",
                body: "A borrower submitted a repayment for your review.",
                deepLink: loanDeepLink(loanID: payment.loan_id, paymentID: paymentID)
            )

        case .update(let action):
            guard let payment = try? action.decodeRecord(as: Payment.self, decoder: decoder) else { return }

            let oldStatus = decodePaymentStatus(from: action.oldRecord)
            guard oldStatus != payment.status else { return }

            delegate?.handlePaymentUpdate(payment: payment, oldStatus: oldStatus)
            
            guard let loans = delegate?.getLoans(),
                  let loan = loans.first(where: { $0.id == payment.loan_id }),
                  let paymentID = payment.id else {
                return
            }
            
            let isLender = loan.lender_id == currentUserID
            if !isLender, oldStatus == .pending, payment.status == .approved {
                await NotificationManager.shared.postEventNotification(
                    eventID: "payment.\(paymentID.uuidString).approved",
                    title: "Payment Approved",
                    body: "Your repayment was approved by the lender.",
                    deepLink: loanDeepLink(loanID: payment.loan_id, paymentID: paymentID)
                )
            } else if !isLender, oldStatus == .pending, payment.status == .rejected {
                await NotificationManager.shared.postEventNotification(
                    eventID: "payment.\(paymentID.uuidString).rejected",
                    title: "Payment Rejected",
                    body: "Your repayment was rejected. Please review details.",
                    deepLink: loanDeepLink(loanID: payment.loan_id, paymentID: paymentID)
                )
            }

        case .delete:
            break
        }
    }

    private func decodePaymentStatus(from oldRecord: [String: AnyJSON]) -> PaymentStatus? {
        guard let data = try? JSONEncoder().encode(oldRecord),
              let snapshot = try? Self.realtimeDecoder.decode(PaymentStatusSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.status
    }

    private struct PaymentStatusSnapshot: Decodable {
        let status: PaymentStatus?
    }

    struct RepaymentAttentionRecord: Decodable {
        let loan_id: UUID
        let status: PaymentStatus
        let date: Date
    }

    func notifyLoanStatusTransition(oldStatus: LoanStatus?, newLoan: Loan, currentUserID: UUID) async {
        guard let oldStatus, oldStatus != newLoan.status, let loanID = newLoan.id else { return }
        let isLender = newLoan.lender_id == currentUserID

        switch (oldStatus, newLoan.status) {
        case (.draft, .sent) where !isLender:
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).draft_to_sent",
                title: "New Loan Request",
                body: "A lender sent you an agreement to review and sign.",
                deepLink: loanDeepLink(loanID: loanID)
            )
        case (.sent, .approved) where isLender:
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).sent_to_approved",
                title: "Borrower Signed",
                body: "The borrower signed the agreement. Send funds to continue.",
                deepLink: loanDeepLink(loanID: loanID)
            )
        case (.approved, .funding_sent) where !isLender:
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).approved_to_funding_sent",
                title: "Funds Sent",
                body: "The lender marked funds as sent. Confirm receipt in the app.",
                deepLink: loanDeepLink(loanID: loanID)
            )
        case (.funding_sent, .active) where isLender:
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).funding_sent_to_active",
                title: "Loan Activated",
                body: "The borrower confirmed receipt. The loan is now active.",
                deepLink: loanDeepLink(loanID: loanID)
            )
        case (.active, .completed):
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).active_to_completed",
                title: "Loan Completed",
                body: "A loan has been marked completed.",
                deepLink: loanDeepLink(loanID: loanID)
            )
        default:
            break
        }
    }

    private func loanDeepLink(loanID: UUID, paymentID: UUID? = nil) -> String {
        var components = URLComponents()
        components.scheme = "loandry"
        components.host = "loan"
        components.path = "/\(loanID.uuidString)"
        if let paymentID {
            components.queryItems = [URLQueryItem(name: "payment_id", value: paymentID.uuidString)]
        }
        return components.string ?? "loandry://loan/\(loanID.uuidString)"
    }
}
