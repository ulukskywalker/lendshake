//
//  LoanManager.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import Observation
import Supabase

@MainActor
@Observable
class LoanManager {
    var loans: [Loan] = []
    var isLoading: Bool = false
    var pendingApprovalCount: Int = 0
    var requiredActionCount: Int = 0
    var pendingRepaymentApprovalsByLoanID: [UUID: Int] = [:]
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
            recomputeRequiredActionCount()
            
            // Subscribe to real-time updates
            await subscribeToLoans(for: user)
            await subscribeToPayments(for: user)
            await refreshPendingApprovalCount()
        } catch {
            print("DEBUG: Fetch Loans Error: \(error)")
            // If table doesn't exist, this will print.
            throw error
        }
    }
    
    private func subscribeToLoans(for user: User) async {
        if realtimeSubscriptionUserID == user.id,
           realtimeChannel != nil,
           realtimeChangesTask != nil {
            return
        }
        
        // Remove existing channel if any
        realtimeChangesTask?.cancel()
        realtimeChangesTask = nil
        if let existing = realtimeChannel {
            await existing.unsubscribe()
            realtimeChannel = nil
        }
        
        // Create new channel
        let channel = supabase.realtimeV2.channel("public:loans")
        
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "loans"
        )
        
        // Listen in a separate task so we don't block
        realtimeChangesTask = Task {
            for await change in changes {
                if Task.isCancelled { break }
                await handleRealtimeChange(change, userId: user.id, userEmail: user.email ?? "")
            }
        }
        
        do {
            try await channel.subscribeWithError()
            self.realtimeChannel = channel
            self.realtimeSubscriptionUserID = user.id
        } catch {
            print("ERROR: Exception during subscription: \(error)")
            realtimeChangesTask?.cancel()
            realtimeChangesTask = nil
        }
    }
    
    private func handleRealtimeChange(_ change: AnyAction, userId: UUID, userEmail: String) async {
        let decoder = Self.realtimeDecoder
        
        switch change {
        case .insert(let action):
            guard let loan = try? action.decodeRecord(as: Loan.self, decoder: decoder) else { return }
            if shouldInclude(loan, userId: userId, userEmail: userEmail) {
                withAnimation {
                    upsertLoan(loan)
                }
            }
        case .update(let action):
            guard let loan = try? action.decodeRecord(as: Loan.self, decoder: decoder) else { return }
            let previousStatus = decodeLoanStatus(from: action.oldRecord)
            if let index = self.loans.firstIndex(where: { $0.id == loan.id }) {
                withAnimation {
                    self.loans[index] = loan
                }
            } else if shouldInclude(loan, userId: userId, userEmail: userEmail) {
                withAnimation {
                    insertLoanInCreatedOrder(loan)
                }
            }
            await notifyLoanStatusTransition(oldStatus: previousStatus, newLoan: loan, currentUserID: userId)
        case .delete(let action):
            let oldRecord = action.oldRecord
            guard let data = try? JSONEncoder().encode(oldRecord),
                  let deleted = try? decoder.decode(DeletedRecord.self, from: data) else { return }
            
             withAnimation {
                 self.loans.removeAll(where: { $0.id == deleted.id })
             }
        }
        
        recomputeRequiredActionCount()
        await refreshPendingApprovalCount()
    }
    
    struct DeletedRecord: Decodable {
        let id: UUID
    }
    
    private func shouldInclude(_ loan: Loan, userId: UUID, userEmail: String) -> Bool {
        return loan.lender_id == userId ||
               loan.borrower_id == userId ||
               loan.borrower_email == userEmail
    }

    private func upsertLoan(_ loan: Loan) {
        if let index = loans.firstIndex(where: { $0.id == loan.id }) {
            loans[index] = loan
            return
        }
        insertLoanInCreatedOrder(loan)
    }

    private func insertLoanInCreatedOrder(_ loan: Loan) {
        let insertedDate = loan.created_at ?? .distantPast
        let targetIndex = loans.firstIndex {
            ($0.created_at ?? .distantPast) < insertedDate
        } ?? loans.endIndex
        loans.insert(loan, at: targetIndex)
    }

    private struct PendingPaymentRecord: Decodable {
        let loan_id: UUID
    }

    private func subscribeToPayments(for user: User) async {
        if paymentsRealtimeSubscriptionUserID == user.id,
           paymentsRealtimeChannel != nil,
           paymentsRealtimeChangesTask != nil {
            return
        }

        paymentsRealtimeChangesTask?.cancel()
        paymentsRealtimeChangesTask = nil
        if let existing = paymentsRealtimeChannel {
            await existing.unsubscribe()
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
                await refreshPendingApprovalCount()
            }
        }

        do {
            try await channel.subscribeWithError()
            paymentsRealtimeChannel = channel
            paymentsRealtimeSubscriptionUserID = user.id
        } catch {
            print("ERROR: Payments realtime subscription failed: \(error)")
            paymentsRealtimeChangesTask?.cancel()
            paymentsRealtimeChangesTask = nil
        }
    }

    private func handlePaymentRealtimeChange(_ change: AnyAction, currentUserID: UUID) async {
        let decoder = Self.realtimeDecoder

        switch change {
        case .insert(let action):
            guard let payment = try? action.decodeRecord(as: Payment.self, decoder: decoder),
                  payment.type == .repayment,
                  payment.status == .pending,
                  let loan = loans.first(where: { $0.id == payment.loan_id }),
                  loan.lender_id == currentUserID,
                  let paymentID = payment.id else {
                return
            }

            await NotificationManager.shared.postEventNotification(
                eventID: "payment.\(paymentID.uuidString).pending",
                title: "Payment Needs Approval",
                body: "A borrower submitted a repayment for your review."
            )

        case .update(let action):
            guard let payment = try? action.decodeRecord(as: Payment.self, decoder: decoder),
                  let loan = loans.first(where: { $0.id == payment.loan_id }),
                  let paymentID = payment.id else {
                return
            }

            let oldStatus = decodePaymentStatus(from: action.oldRecord)
            guard oldStatus != payment.status else { return }

            let isLender = loan.lender_id == currentUserID
            if !isLender, oldStatus == .pending, payment.status == .approved {
                await NotificationManager.shared.postEventNotification(
                    eventID: "payment.\(paymentID.uuidString).approved",
                    title: "Payment Approved",
                    body: "Your repayment was approved by the lender."
                )
            } else if !isLender, oldStatus == .pending, payment.status == .rejected {
                await NotificationManager.shared.postEventNotification(
                    eventID: "payment.\(paymentID.uuidString).rejected",
                    title: "Payment Rejected",
                    body: "Your repayment was rejected. Please review details."
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

    func refreshPendingApprovalCount() async {
        guard let user = supabase.auth.currentUser else {
            pendingRepaymentApprovalsByLoanID = [:]
            pendingApprovalCount = 0
            recomputeRequiredActionCount()
            return
        }

        let lenderLoanIDs = loans
            .filter { $0.lender_id == user.id }
            .compactMap(\.id)

        guard !lenderLoanIDs.isEmpty else {
            pendingRepaymentApprovalsByLoanID = [:]
            pendingApprovalCount = 0
            recomputeRequiredActionCount()
            return
        }

        do {
            let pendingPayments: [PendingPaymentRecord] = try await supabase
                .from("payments")
                .select("loan_id")
                .eq("status", value: PaymentStatus.pending.rawValue)
                .eq("type", value: PaymentType.repayment.rawValue)
                .execute()
                .value

            let lenderLoanIDSet = Set(lenderLoanIDs)
            let byLoan = pendingPayments.reduce(into: [UUID: Int]()) { counts, payment in
                if lenderLoanIDSet.contains(payment.loan_id) {
                    counts[payment.loan_id, default: 0] += 1
                }
            }
            pendingRepaymentApprovalsByLoanID = byLoan
            pendingApprovalCount = byLoan.values.reduce(0, +)
            recomputeRequiredActionCount()
        } catch {
            pendingRepaymentApprovalsByLoanID = [:]
            pendingApprovalCount = 0
            recomputeRequiredActionCount()
            print("Pending approval count refresh error: \(error)")
        }
    }

    private func recomputeRequiredActionCount() {
        guard let user = supabase.auth.currentUser else {
            requiredActionCount = 0
            return
        }

        requiredActionCount = countLoanWorkflowActions(for: user) + pendingApprovalCount
    }

    private func countLoanWorkflowActions(for user: User) -> Int {
        loans.reduce(into: 0) { count, loan in
            let isLender = loan.lender_id == user.id

            switch loan.status {
            case .draft where isLender && loan.lender_signed_at == nil:
                count += 1
            case .sent where !isLender && loan.borrower_signed_at == nil:
                count += 1
            case .approved where isLender:
                count += 1
            case .funding_sent where !isLender:
                count += 1
            default:
                break
            }
        }
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

    private func notifyLoanStatusTransition(oldStatus: LoanStatus?, newLoan: Loan, currentUserID: UUID) async {
        guard let oldStatus, oldStatus != newLoan.status, let loanID = newLoan.id else { return }
        let isLender = newLoan.lender_id == currentUserID

        switch (oldStatus, newLoan.status) {
        case (.draft, .sent) where !isLender:
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).draft_to_sent",
                title: "New Loan Request",
                body: "A lender sent you an agreement to review and sign."
            )
        case (.sent, .approved) where isLender:
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).sent_to_approved",
                title: "Borrower Signed",
                body: "The borrower signed the agreement. Send funds to continue."
            )
        case (.approved, .funding_sent) where !isLender:
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).approved_to_funding_sent",
                title: "Funds Sent",
                body: "The lender marked funds as sent. Confirm receipt in the app."
            )
        case (.funding_sent, .active) where isLender:
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).funding_sent_to_active",
                title: "Loan Activated",
                body: "The borrower confirmed receipt. The loan is now active."
            )
        case (.active, .completed):
            await NotificationManager.shared.postEventNotification(
                eventID: "loan.\(loanID.uuidString).active_to_completed",
                title: "Loan Completed",
                body: "A loan has been marked completed."
            )
        default:
            break
        }
    }

    func requiredActionLabel(for loan: Loan) -> String? {
        guard let user = supabase.auth.currentUser else { return nil }
        let isLender = loan.lender_id == user.id

        if isLender, let loanId = loan.id, let pendingCount = pendingRepaymentApprovalsByLoanID[loanId], pendingCount > 0 {
            return pendingCount == 1 ? "Approve 1 payment" : "Approve \(pendingCount) payments"
        }

        switch loan.status {
        case .draft:
            return (isLender && loan.lender_signed_at == nil) ? "Sign agreement" : nil
        case .sent:
            return (!isLender && loan.borrower_signed_at == nil) ? "Review and sign agreement" : nil
        case .approved:
            return isLender ? "Send funds confirmation" : nil
        case .funding_sent:
            return !isLender ? "Confirm receipt" : nil
        default:
            return nil
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
        guard let user = supabase.auth.currentUser else { return }
        let isLender = (loan.lender_id == user.id)
        
        guard let loanId = loan.id else { return }
        
        if isLender {
            // LENDER SIGNING
            var updatedLoan = loan
            updatedLoan.lender_signed_at = Date()
            
            // Regenerate agreement at signing time to ensure names/terms are current.
            let lenderName = await resolveLenderDisplayName(for: user)
            updatedLoan.agreement_text = AgreementGenerator.generate(for: loan, lenderName: lenderName)
            
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

    private func fetchUserFullName(userId: UUID) async -> String? {
        struct ProfileName: Decodable {
            let first_name: String?
            let last_name: String?
        }

        do {
            let profile: ProfileName = try await supabase
                .from("profiles")
                .select("first_name, last_name")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            let fullName = [profile.first_name, profile.last_name]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            return fullName.isEmpty ? nil : fullName
        } catch {
            return nil
        }
    }

    private func resolveLenderDisplayName(for user: User) async -> String {
        if let profileName = await fetchUserFullName(userId: user.id),
           !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return profileName
        }

        if let email = user.email, let firstSegment = email.split(separator: "@").first, !firstSegment.isEmpty {
            return String(firstSegment)
        }

        return "Lender"
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
        
        if newStatus == .approved {
            let params: [String: String] = ["p_payment_id": paymentId.uuidString]
            _ = try await supabase
                .rpc("approve_payment_and_recompute_balance", params: params)
                .execute()

            try await fetchLoans()
            return
        }

        // Non-approval states keep simple payment-status update path.
        struct PaymentUpdate: Encodable {
            let status: PaymentStatus
        }
        
        try await supabase
            .from("payments")
            .update(PaymentUpdate(status: newStatus))
            .eq("id", value: paymentId)
            .execute()
            
        // Keep loan list consistent if status is rejected.
        try await fetchLoans()
    }
}
