//
//  LoanManager.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import Observation
import Supabase

@MainActor
@Observable
class LoanManager {
    static let shared = LoanManager()
    
    private let logger = AppLogger(.loans)
    private let service = LoanService.shared

    var loans: [Loan] = []
    var isLoading: Bool = false
    var pendingApprovalCount: Int = 0
    var requiredActionCount: Int = 0
    var pendingRepaymentApprovalsByLoanID: [UUID: Int] = [:]
    var rejectedRepaymentsByLoanID: [UUID: Int] = [:]

    private let realtimeManager: RealtimeManager

    init() {
        self.realtimeManager = RealtimeManager(supabase: supabase)
        self.realtimeManager.delegate = self
    }
    
    // MARK: - API
    
    func fetchLoans() async throws {
        guard let user = supabase.auth.currentUser else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            self.loans = try await service.fetchLoans(userId: user.id, email: user.email ?? "")
            recomputeRequiredActionCount()
            realtimeManager.subscribe(for: user)
            await refreshPendingApprovalCount()
        } catch {
            await AlertReporter.shared.capture(error: error, category: .loans, summary: "Failed to fetch loans", severity: .critical)
            throw error
        }
    }
    
    func refreshPendingApprovalCount() async {
        guard let user = supabase.auth.currentUser else { resetActionCounts(); return }
        let lenderIDs = loans.filter { $0.lender_id == user.id }.compactMap(\.id)
        let borrowerIDs = loans.filter { $0.borrower_id == user.id }.compactMap(\.id)
        guard !lenderIDs.isEmpty || !borrowerIDs.isEmpty else { resetActionCounts(); return }

        do {
            let attentionPayments: [RealtimeManager.RepaymentAttentionRecord] = try await supabase
                .from("payments").select("loan_id,status,date")
                .or("status.eq.\(PaymentStatus.pending.rawValue),status.eq.\(PaymentStatus.rejected.rawValue),status.eq.\(PaymentStatus.approved.rawValue)")
                .eq("type", value: PaymentType.repayment.rawValue).execute().value
            processAttentionPayments(attentionPayments, lenderIDs: lenderIDs, borrowerIDs: borrowerIDs)
        } catch { 
            await AlertReporter.shared.capture(error: error, category: .loans, summary: "Failed to refresh action counts", severity: .critical)
            resetActionCounts() 
        }
    }
    
    private func resetActionCounts() {
        pendingRepaymentApprovalsByLoanID = [:]; rejectedRepaymentsByLoanID = [:]; pendingApprovalCount = 0; recomputeRequiredActionCount()
    }
    
    private func processAttentionPayments(_ payments: [RealtimeManager.RepaymentAttentionRecord], lenderIDs: [UUID], borrowerIDs: [UUID]) {
        let lenderSet = Set(lenderIDs); let borrowerSet = Set(borrowerIDs)
        let pending = payments.reduce(into: [UUID: Int]()) { counts, p in
            if p.status == .pending, lenderSet.contains(p.loan_id) { counts[p.loan_id, default: 0] += 1 }
        }
        let latestBorrower = payments.reduce(into: [UUID: RealtimeManager.RepaymentAttentionRecord]()) { latest, p in
            guard borrowerSet.contains(p.loan_id) else { return }
            if let existing = latest[p.loan_id] { if p.date > existing.date { latest[p.loan_id] = p } } else { latest[p.loan_id] = p }
        }
        let rejected = latestBorrower.reduce(into: [UUID: Int]()) { counts, entry in
            if entry.value.status == .rejected { counts[entry.key] = 1 }
        }
        pendingRepaymentApprovalsByLoanID = pending; rejectedRepaymentsByLoanID = rejected
        pendingApprovalCount = pending.values.reduce(0, +); recomputeRequiredActionCount()
    }

    private func recomputeRequiredActionCount() {
        guard let user = supabase.auth.currentUser else { requiredActionCount = 0; return }
        requiredActionCount = countLoanWorkflowActions(for: user) + pendingApprovalCount + rejectedRepaymentsByLoanID.count
    }

    private func countLoanWorkflowActions(for user: Supabase.User) -> Int {
        loans.reduce(into: 0) { count, loan in
            let isLender = loan.lender_id == user.id
            switch loan.status {
            case .draft where isLender && loan.lender_signed_at == nil: count += 1
            case .sent where !isLender && loan.borrower_signed_at == nil: count += 1
            case .approved where isLender: count += 1
            case .funding_sent where !isLender: count += 1
            default: break
            }
        }
    }

    func requiredActionLabel(for loan: Loan) -> String? {
        guard let user = supabase.auth.currentUser, let loanId = loan.id else { return nil }
        let isLender = loan.lender_id == user.id
        if isLender, let count = pendingRepaymentApprovalsByLoanID[loanId], count > 0 { return count == 1 ? "Approve 1 payment" : "Approve \(count) payments" }
        if !isLender, let count = rejectedRepaymentsByLoanID[loanId], count > 0 { return count == 1 ? "Payment rejected" : "\(count) payments rejected" }
        switch loan.status {
        case .draft where isLender && loan.lender_signed_at == nil: return "Sign agreement"
        case .sent where !isLender && loan.borrower_signed_at == nil: return "Complete info and sign agreement"
        case .approved where isLender: return "Send funds confirmation"
        case .funding_sent where !isLender: return "Confirm receipt"
        default: return nil
        }
    }
    
    func createDraftLoan(principal: Double, interest: Double, schedule: String, lateFee: String, maturity: Date, firstPaymentDate: Date, borrowerName: String?, borrowerEmail: String?, borrowerPhone: String?) async throws -> Loan {
        guard let user = supabase.auth.currentUser else { throw AuthError.notAuthenticated }
        do {
            let loan = Loan(lenderId: user.id, principal: principal, interest: interest, schedule: schedule, lateFee: lateFee, maturity: maturity, firstPaymentDate: firstPaymentDate, borrowerName: borrowerName, borrowerEmail: borrowerEmail, borrowerPhone: borrowerPhone)
            let created = try await service.createLoan(loan)
            try await fetchLoans(); return created
        } catch {
            await AlertReporter.shared.capture(error: error, category: .loans, summary: "Failed to create draft loan", severity: .critical)
            throw error
        }
    }
    
    func signLoan(loan: Loan) async throws {
        // Legacy internal signing logic kept if needed, but for PandaDoc flow:
        guard let user = supabase.auth.currentUser, let loanId = loan.id else { throw AuthError.notAuthenticated }
        do {
            let ip = await fetchPublicIP(); let isLender = (loan.lender_id == user.id)
            if isLender {
                let text = AgreementUtility.generate(for: loan)
                try await supabase.rpc("lender_sign_loan", params: ["p_loan_id": loanId.uuidString, "p_agreement_text": text, "p_lender_ip": ip ?? ""]).execute()
            } else {
                try await supabase.rpc("borrower_sign_loan", params: ["p_loan_id": loanId.uuidString, "p_borrower_ip": ip ?? ""]).execute()
            }
            try await fetchLoans()
        } catch {
            await AlertReporter.shared.capture(error: error, category: .loans, summary: "Failed to sign loan", severity: .critical)
            throw error
        }
    }
    
    func sendForSignature(loan: Loan) async throws {
         guard let loanId = loan.id else { return }
         
         struct SendPayload: Encodable {
             let loan_id: UUID
             let borrower_email: String
             let borrower_name: String
             let lender_name: String
             let loan_amount: String
             let interest_rate: String
             let repayment_schedule: String
             let borrower_state: String?
             let lender_state: String?
         }
         
         // Try to resolve borrower state
         var borrowerState: String? = nil
         if let borrowerID = loan.borrower_id {
             let profile: AuthManager.UserProfile? = try? await supabase.from("profiles").select().eq("id", value: borrowerID).single().execute().value
             borrowerState = profile?.residence_state
         }
         
         // Resolve lender state (current user)
         var lenderState: String? = nil
         if let lenderID = supabase.auth.currentUser?.id {
             let profile: AuthManager.UserProfile? = try? await supabase.from("profiles").select().eq("id", value: lenderID).single().execute().value
             lenderState = profile?.residence_state
         }
         
         let payload = SendPayload(
             loan_id: loanId,
             borrower_email: loan.borrower_email ?? "",
             borrower_name: loan.borrower_name ?? "Borrower",
             lender_name: loan.lender_name_snapshot ?? "Lender",
             loan_amount: String(format: "%.2f", loan.principal_amount),
             interest_rate: String(format: "%.2f", loan.interest_rate),
             repayment_schedule: loan.repayment_schedule,
             borrower_state: borrowerState,
             lender_state: lenderState
         )
         
         do {
             _ = try await supabase.functions.invoke("pandadoc-sign/send", options: FunctionInvokeOptions(body: payload))
             
             // Optimistic update or fetch
             try await fetchLoans()
         } catch {
             await AlertReporter.shared.capture(error: error, category: .loans, summary: "Failed to send for signature (PandaDoc)", severity: .critical)
             throw error
         }
    }
    
    func generatePandaDocSigningURL(loan: Loan) async throws -> URL {
        guard let docId = loan.t_pandadoc_id, let borrowerEmail = loan.borrower_email else {
            throw NSError(domain: "LoanManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Loan not processed for PandaDoc signing yet."])
        }

        struct SessionPayload: Encodable {
            let doc_id: String
            let recipient_email: String
        }
        
        struct SessionResponse: Decodable {
            let success: Bool
            let signing_url: String
        }

        let payload = SessionPayload(doc_id: docId, recipient_email: borrowerEmail)
        let response: SessionResponse = try await supabase.functions.invoke("pandadoc-sign/session", options: FunctionInvokeOptions(body: payload))
        
        guard let url = URL(string: response.signing_url) else {
            throw NSError(domain: "LoanManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid signing URL returned from server."])
        }
        
        return url
    }
    
    func signLoanAsBorrower(loan: Loan, firstName: String, lastName: String, addressLine1: String, addressLine2: String, state: String, country: String, postalCode: String, phoneNumber: String) async throws {
        guard let user = supabase.auth.currentUser, let loanId = loan.id else { throw AuthError.notAuthenticated }
        guard loan.lender_id != user.id else { throw NSError(domain: "LoanManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Lender cannot sign as borrower."]) }

        do {
            let ip = await fetchPublicIP()
            let params = ["p_loan_id": loanId.uuidString, "p_borrower_ip": ip ?? "", "p_borrower_first_name": firstName, "p_borrower_last_name": lastName, "p_borrower_address_line_1": addressLine1, "p_borrower_address_line_2": addressLine2, "p_borrower_state": state, "p_borrower_country": country, "p_borrower_postal_code": postalCode, "p_borrower_phone": phoneNumber]
            try await supabase.rpc("borrower_sign_loan_with_identity", params: params).execute()
            try await fetchLoans()
        } catch {
            await AlertReporter.shared.capture(error: error, category: .loans, summary: "Failed to sign as borrower", severity: .critical)
            throw error
        }
    }
    
    func deleteLoan(_ loan: Loan) async throws {
        guard (loan.status == .draft || loan.status == .cancelled), let id = loan.id else { return }
        
        // Use Edge Function for atomic deletion of DB + Storage files
        // This ensures no orphaned files remain.
        struct DeletePayload: Encodable {
            let loan_id: UUID
        }
        
        do {
            let payload = DeletePayload(loan_id: id)
            _ = try await supabase.functions.invoke("delete-loan", options: FunctionInvokeOptions(body: payload))
            
            try await fetchLoans()
        } catch {
            await AlertReporter.shared.capture(error: error, category: .loans, summary: "Failed to delete loan", severity: .critical)
            throw error
        }
    }
    
    func transitionLoanStatus(_ loan: Loan, status: LoanStatus, reason: String? = nil) async throws {
        guard let id = loan.id else { return }
        try await service.transitionStatus(loanId: id, status: status, reason: reason); try await fetchLoans()
    }
    
    func confirmFunding(loan: Loan, proofURL: String?) async throws {
        guard loan.status == .approved, let loanId = loan.id else { return }
        var p = Payment(loanId: loanId, amount: loan.principal_amount, date: Date(), type: .funding, proofURL: proofURL); p.status = .approved
        try await service.submitPayment(p); try await transitionLoanStatus(loan, status: .funding_sent)
    }
    
    func confirmReceipt(loan: Loan) async throws {
        guard loan.status == .funding_sent else { return }
        try await transitionLoanStatus(loan, status: .active)
    }

    func friendlyTransitionErrorMessage(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.contains("Invalid transition") { return "Action no longer valid for current status." }
        if raw.contains("Not authorized") { return "Unauthorized action." }
        return raw
    }
    
    private func fetchPublicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org"), let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func isLender(of loan: Loan) -> Bool { loan.lender_id == supabase.auth.currentUser?.id }
    func fetchPayments(for loan: Loan) async throws -> [Payment] { guard let id = loan.id else { return [] }; return try await service.fetchPayments(loanId: id) }
    func submitPayment(for loan: Loan, amount: Double, date: Date, proofURL: String?) async throws {
        guard let id = loan.id else { return }
        try await service.submitPayment(Payment(loanId: id, amount: amount, date: date, proofURL: proofURL))
    }
    
    func updatePaymentStatus(payment: Payment, newStatus: PaymentStatus, loan: Loan) async throws {
        guard let id = payment.id else { return }
        if newStatus == .approved { try await service.approvePayment(paymentId: id) }
        else if newStatus == .rejected {
            let reason = payment.rejection_reason?.trimmingCharacters(in: .whitespaces) ?? ""
            if reason.isEmpty { throw NSError(domain: "LoanManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Reason required."]) }
            try await service.rejectPayment(paymentId: id, reason: reason)
        } else { try await service.updatePaymentStatus(paymentId: id, status: newStatus) }
        try await fetchLoans()
    }

    func fetchAgreementURL(path: String) async throws -> URL {
        let response = try await supabase.storage.from("loan-documents").createSignedURL(path: path, expiresIn: 3600)
        return response
    }
}

// MARK: - Realtime Delegate

extension LoanManager: RealtimeManagerDelegate {
    func getLoans() -> [Loan] { loans }

    func handleLoanInsert(_ loan: Loan) {
        withAnimation { upsertLoan(loan) }
        recomputeRequiredActionCount()
        Task { await refreshPendingApprovalCount() }
    }

    func handleLoanUpdate(_ loan: Loan, oldStatus: LoanStatus?) {
        if let idx = loans.firstIndex(where: { $0.id == loan.id }) { withAnimation { loans[idx] = loan } }
        else { withAnimation { insertLoanInCreatedOrder(loan) } }
        guard let currentUser = supabase.auth.currentUser else { return }
        Task { [currentUser] in
            await notifyTransition(old: oldStatus, new: loan, userID: currentUser.id)
            recomputeRequiredActionCount(); await refreshPendingApprovalCount()
        }
    }

    func handleLoanDelete(_ deleted: RealtimeManager.DeletedRecord) {
        withAnimation { loans.removeAll(where: { $0.id == deleted.id }) }
        recomputeRequiredActionCount(); Task { await refreshPendingApprovalCount() }
    }

    func handlePaymentInsert(payment: Payment) {
        guard let currentUser = supabase.auth.currentUser, let loan = loans.first(where: { $0.id == payment.loan_id }), loan.lender_id == currentUser.id, let pid = payment.id else { return }
        Task {
            await NotificationManager.shared.postEventNotification(eventID: "p.\(pid.uuidString).pending", title: "Payment Needs Approval", body: "A repayment was submitted for review.", deepLink: loanDeepLink(loanID: payment.loan_id, paymentID: pid))
            await refreshPendingApprovalCount()
        }
    }

    func handlePaymentUpdate(payment: Payment, oldStatus: PaymentStatus?) {
        guard let currentUser = supabase.auth.currentUser, let loan = loans.first(where: { $0.id == payment.loan_id }), let pid = payment.id else { return }
        if loan.lender_id != currentUser.id, oldStatus == .pending {
            if payment.status == .approved { notifyPayment(pid: pid, lid: payment.loan_id, title: "Payment Approved", body: "Approved by lender.") }
            else if payment.status == .rejected { notifyPayment(pid: pid, lid: payment.loan_id, title: "Payment Rejected", body: "Rejected. Review details.") }
        }
        Task { 
            await refreshPendingApprovalCount() 
        }
    }
    
    private func notifyPayment(pid: UUID, lid: UUID, title: String, body: String) {
        Task { await NotificationManager.shared.postEventNotification(eventID: "p.\(pid.uuidString).action", title: title, body: body, deepLink: loanDeepLink(loanID: lid, paymentID: pid)) }
    }

    private func notifyTransition(old: LoanStatus?, new: Loan, userID: UUID) async {
        guard let old, old != new.status, let lid = new.id else { return }
        let isLender = new.lender_id == userID
        var title = ""; var body = ""
        switch (old, new.status) {
        case (.draft, .sent) where !isLender: title = "New Loan Request"; body = "Review and sign the agreement."
        case (.sent, .approved) where isLender: title = "Borrower Signed"; body = "Borrower signed. Send funds to continue."
        case (.approved, .funding_sent) where !isLender: title = "Funds Sent"; body = "Lender sent funds. Confirm receipt."
        case (.funding_sent, .active) where isLender: title = "Loan Activated"; body = "Borrower confirmed receipt."
        case (.active, .completed): title = "Loan Completed"; body = "Loan marked completed."
        default: return
        }
        await NotificationManager.shared.postEventNotification(eventID: "l.\(lid.uuidString).\(new.status.rawValue)", title: title, body: body, deepLink: loanDeepLink(loanID: lid))
    }

    private func upsertLoan(_ loan: Loan) {
        if let idx = loans.firstIndex(where: { $0.id == loan.id }) { loans[idx] = loan } else { insertLoanInCreatedOrder(loan) }
    }

    private func insertLoanInCreatedOrder(_ loan: Loan) {
        let date = loan.created_at ?? .distantPast
        let idx = loans.firstIndex { ($0.created_at ?? .distantPast) < date } ?? loans.endIndex
        loans.insert(loan, at: idx)
    }

    private func loanDeepLink(loanID: UUID, paymentID: UUID? = nil) -> String {
        var c = URLComponents(); c.scheme = "loandry"; c.host = "loan"; c.path = "/\(loanID.uuidString)"
        if let pid = paymentID { c.queryItems = [URLQueryItem(name: "payment_id", value: pid.uuidString)] }
        return c.string ?? "loandry://loan/\(loanID.uuidString)"
    }
}
