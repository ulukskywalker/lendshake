//
//  LoanDetailView.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import Supabase


private enum HistoryEventType {
    case created
    case lenderSigned
    case borrowerSigned
    case payment(Payment)
}

private struct HistoryEvent: Identifiable {
    let id = UUID()
    let date: Date
    let type: HistoryEventType
}

struct LoanDetailView: View {
    let loan: Loan
    let initialSelectedPaymentID: UUID?
    
    @Environment(LoanManager.self) private var loanManager
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var errorMsg: String?
    @State private var showError: Bool = false
    
    // UI States
    @State private var showForgiveAlert: Bool = false
    @State private var showDeleteDraftAlert: Bool = false
    @State private var showCancelAlert: Bool = false
    @State private var showRejectAlert: Bool = false
    @State private var showAgreementRejectionReasonSheet: Bool = false
    @State private var agreementRejectionReason: String = ""
    @State private var forgiveConfirmationText: String = ""
    
    @State private var showBorrowerSignSheet: Bool = false
    @State private var showReleaseSheet: Bool = false
    @State private var showFundingSheet: Bool = false
    @State private var showPaymentSheet: Bool = false
    @State private var showPendingActionSheet: Bool = false
    
    @State private var lenderName: String = "Loading..."
    @State private var payments: [Payment] = []
    @State private var selectedPayment: Payment?
    @State private var didApplyInitialSelection = false

    // Realtime
    @State private var realtimeChannel: RealtimeChannelV2?
    @State private var realtimeTask: Task<Void, Never>?

    var liveLoan: Loan {
        loanManager.loans.first(where: { $0.id == loan.id }) ?? loan
    }
    
    var isLender: Bool {
        loanManager.isLender(of: liveLoan)
    }

    init(loan: Loan, initialSelectedPaymentID: UUID? = nil) {
        self.loan = loan
        self.initialSelectedPaymentID = initialSelectedPaymentID
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Status & Action ──
                statusSection
                
                // ── History ──
                thinDivider
                historySection
                
                // ── Menu ──
                thinDivider
                menuSection
            }
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemBackground))
        .task(id: liveLoan.id) {
            await refreshData()
            lenderName = await resolveLenderName()
            await subscribeToPayments()
        }
        .onDisappear { unsubscribe() }
        .sheet(isPresented: $showPaymentSheet) {
            PaymentSheetView(loan: liveLoan, isPresented: $showPaymentSheet, onSubmitted: { Task { await refreshData() } })
        }
        .sheet(item: $selectedPayment) { payment in
            TransactionDetailView(payment: payment, loan: liveLoan, isLender: isLender)
                .onDisappear { Task { await refreshData() } }
        }
        .sheet(isPresented: $showBorrowerSignSheet) {
            BorrowerSignSheetView(isPresented: $showBorrowerSignSheet, loan: liveLoan)
        }
        .sheet(isPresented: $showReleaseSheet) { releaseSheet }
        .sheet(isPresented: $showFundingSheet) { FundingSheetView(loan: liveLoan, isPresented: $showFundingSheet) }
        .sheet(isPresented: $showPendingActionSheet) { pendingActionSheet }
        .sheet(isPresented: $showAgreementRejectionReasonSheet) { rejectionReasonSheet }
        .alert("Error", isPresented: $showError) { Button("OK", role: .cancel) { } } message: { Text(errorMsg ?? "Unknown error") }
        .alert("Forgive Loan?", isPresented: $showForgiveAlert) {
            TextField("Type 'Forgive Loan'", text: $forgiveConfirmationText)
            Button("Cancel", role: .cancel) { }
            Button("Forgive", role: .destructive) {
                if forgiveConfirmationText == "Forgive Loan" {
                   performTransition(to: .forgiven)
                }
            }
            .disabled(forgiveConfirmationText != "Forgive Loan")
        } message: { Text("This action cannot be undone. Type 'Forgive Loan' to confirm.") }
        .onChange(of: showForgiveAlert) { _, isPresented in
            if isPresented { forgiveConfirmationText = "" }
        }
        .alert("Delete Draft?", isPresented: $showDeleteDraftAlert) {
            Button("Delete", role: .destructive) { performDelete() }
        } message: { Text("Permanently delete this draft?") }
        .alert("Cancel Request?", isPresented: $showCancelAlert) {
            Button("Keep Loan", role: .cancel) { }
            Button("Cancel Loan", role: .destructive) { showAgreementRejectionReasonSheet = true }
        } message: { Text("This will cancel the loan and stop the signature process.") }
        .alert("Reject Agreement?", isPresented: $showRejectAlert) {
            Button("Keep Reviewing", role: .cancel) { }
            Button("Reject Loan", role: .destructive) { showAgreementRejectionReasonSheet = true }
        } message: { Text("This will reject the agreement and cancel this loan request.") }
    }
    
    // MARK: - Thin Divider
    
    private var thinDivider: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.2))
            .frame(height: 0.5)
            .padding(.horizontal, 24)
    }
    
    // MARK: - Status Section
    
    @ViewBuilder
    private var statusSection: some View {
        if liveLoan.status == .active {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("next due")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                        if Date() > liveLoan.nextPaymentDate {
                            Text("overdue")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.red)
                        } else {
                            Text(liveLoan.nextPaymentDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("min payment")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text(liveLoan.minimumPaymentAmount.formatted(.currency(code: "USD")))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 24)
            }
        }
    }
    
    
    
    // MARK: - Action Content
    
    @ViewBuilder
    private var actionContent: some View {
        switch liveLoan.status {
        case .draft: draftActions
        case .sent: sentActions
        case .approved: approvedActions
        case .funding_sent: fundingSentActions
        case .active: activeActions
        case .completed, .forgiven: completedActions
        case .cancelled: EmptyView()
        }
    }
    
    private var hasPendingAction: Bool {
        switch liveLoan.status {
        case .draft, .sent, .approved, .funding_sent: return true
        case .active: return !isLender
        case .completed, .forgiven, .cancelled: return false
        }
    }

    private var pendingActionDisplay: (title: String, isYourTurn: Bool) {
        switch liveLoan.status {
        case .draft:
            return isLender ? ("Send Agreement", true) : ("Waiting for Lender", false)
        case .sent:
            return isLender ? ("Waiting for Borrower", false) : ("Sign Agreement", true)
        case .approved:
            return isLender ? ("Send Funds", true) : ("Waiting for Lender", false)
        case .funding_sent:
            return isLender ? ("Waiting for Borrower", false) : ("Confirm Receipt", true)
        case .active:
            return isLender ? ("Waiting for Payment", false) : ("Record a Payment", true)
        default:
            return ("Inactive", false)
        }
    }

    private var counterpartyDisplay: String {
        if isLender {
            return liveLoan.borrower_name_snapshot ?? liveLoan.borrower_name ?? "Borrower"
        } else {
            return lenderName == "Loading..." ? "Lender" : lenderName
        }
    }
    
    // MARK: - History Section
    
    private var combinedHistory: [HistoryEvent] {
        var events: [HistoryEvent] = []
        if let created = liveLoan.created_at {
            events.append(HistoryEvent(date: created, type: .created))
        }
        if let lSigned = liveLoan.lender_signed_at {
            events.append(HistoryEvent(date: lSigned, type: .lenderSigned))
        }
        if let bSigned = liveLoan.borrower_signed_at {
            events.append(HistoryEvent(date: bSigned, type: .borrowerSigned))
        }
        for p in payments {
            events.append(HistoryEvent(date: p.date, type: .payment(p)))
        }
        return events.sorted { $0.date > $1.date }
    }
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("history")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            
            if hasPendingAction {
                VStack(spacing: 0) {
                    Button {
                        showPendingActionSheet = true
                    } label: {
                        let action = pendingActionDisplay
                        HStack(spacing: 12) {
                            Image(systemName: action.isYourTurn ? "exclamationmark.circle.fill" : "hourglass")
                                .font(.system(size: 18))
                                .foregroundStyle(action.isYourTurn ? .orange : .secondary)
                                .frame(width: 24)
                            
                            Text(action.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(action.isYourTurn ? .primary : .secondary)
                            
                            Spacer()
                            
                            if !action.isYourTurn {
                                Text("Wait")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary.opacity(0.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if !combinedHistory.isEmpty {
                        Divider()
                            .padding(.leading, 36)
                            .padding(.vertical, 4)
                    }
                }
            }
            
            if combinedHistory.isEmpty {
                Text("no history yet")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(combinedHistory.enumerated()), id: \.element.id) { index, event in
                    VStack(spacing: 0) {
                        historyRow(for: event)
                            .padding(.vertical, 6)
                        
                        if index < combinedHistory.count - 1 {
                            Divider()
                                .padding(.leading, 36)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private func historyRow(for event: HistoryEvent) -> some View {
        switch event.type {
        case .payment(let p):
            PaymentRowView(payment: p, isLender: isLender)
                .contentShape(Rectangle())
                .onTapGesture { selectedPayment = p }
        case .created:
            eventRow(icon: "doc.badge.plus", color: .gray, title: "Loan drafted", date: event.date)
        case .lenderSigned:
            eventRow(icon: "signature", color: .blue, title: "Lender signed", date: event.date)
        case .borrowerSigned:
            eventRow(icon: "signature", color: .orange, title: "Borrower signed", date: event.date)
        }
    }
    
    private func eventRow(icon: String, color: Color, title: String, date: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text(date.formatted(date: .numeric, time: .omitted))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Menu Section
    
    private var menuSection: some View {
        VStack(spacing: 0) {
            if isLender && [.draft, .sent, .active, .cancelled].contains(liveLoan.status) {
                Text("loan actions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    

                let destructiveLabel: String = {
                    switch liveLoan.status {
                    case .draft, .cancelled: return "delete"
                    case .sent: return "cancel request"
                    case .active: return "forgive loan"
                    default: return ""
                    }
                }()
                
                menuRow(label: destructiveLabel, icon: "trash", isDestructive: true) {
                    switch liveLoan.status {
                    case .draft, .cancelled: showDeleteDraftAlert = true
                    case .sent: showCancelAlert = true
                    case .active: showForgiveAlert = true
                    default: break
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
    }
    
    private func menuRow(label: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isDestructive ? .red.opacity(0.7) : .secondary)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isDestructive ? .red.opacity(0.7) : .primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.quaternary)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sub-Actions (Minimalist)

    @ViewBuilder
    private var draftActions: some View {
        if isLender {
            Button {
                Task {
                    do { try await loanManager.sendForSignature(loan: liveLoan) }
                    catch { errorMsg = loanManager.friendlyTransitionErrorMessage(error); showError = true }
                }
            } label: {
                Text("send for signature")
                    .paperButton()
            }
        } else {
            Text("waiting for lender to send agreement")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var sentActions: some View {
        if isLender {
            Text("waiting for borrower to sign")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
        } else {
            VStack(spacing: 12) {
                Text("signature required")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Button {
                    Task { await openSigningURL() }
                } label: {
                    Text("sign agreement")
                        .paperButton()
                }
            }
        }
    }

    @ViewBuilder
    private var approvedActions: some View {
        if isLender {
            Button { showFundingSheet = true } label: {
                Text("i have sent the money")
                    .paperButton()
            }
        } else {
            Text("waiting for lender to release funds")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var fundingSentActions: some View {
        if isLender {
            Text("waiting for borrower to confirm receipt")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
        } else {
            Button { Task { await confirmReceipt() } } label: {
                Text("confirm i received money")
                    .paperButton()
            }
        }
    }

    @ViewBuilder
    private var activeActions: some View {
        if !isLender {
            Button { showPaymentSheet = true } label: {
                Text("record payment")
                    .paperButton()
            }
        }
    }

    @ViewBuilder
    private var completedActions: some View {
        Button { showReleaseSheet = true } label: {
            Text("view release document")
                .paperButton(filled: false)
        }
    }

    // MARK: - Sheets

    private var pendingActionSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: liveLoan.status == .active ? "dollarsign.circle.fill" : "bell.badge.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                
                Text(liveLoan.status == .active && !isLender ? "Make a Payment" : "Action Required")
                    .font(.title2.bold())
                
                Text(pendingActionDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                actionContent
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            .padding(.top, 40)
            .navigationTitle("Action Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showPendingActionSheet = false }
                }
            }
        }
        .presentationDetents([.fraction(0.5)])
    }

    private var pendingActionDescription: String {
        if isLender {
            switch liveLoan.status {
            case .draft: return "You need to send the loan agreement to the borrower for signature."
            case .sent: return "Waiting for the borrower to review and sign the agreement."
            case .approved: return "The borrower has signed. You must now send the funds to them."
            case .funding_sent: return "Waiting for the borrower to confirm they received the funds."
            case .completed, .forgiven: return "The loan is closed. You can view the release document."
            default: return ""
            }
        } else {
            switch liveLoan.status {
            case .draft: return "Waiting for the lender to prepare and send the agreement."
            case .sent: return "The lender has sent the agreement. Please review and sign it."
            case .approved: return "Waiting for the lender to send the funds."
            case .funding_sent: return "The lender sent the funds. Please confirm you received them."
            case .active: return "You have an active loan. You can record payments here."
            case .completed, .forgiven: return "The loan is closed. You can view the release document."
            default: return ""
            }
        }
    }

    private var releaseSheet: some View {
        NavigationStack {
            ScrollView { Text(AgreementUtility.generateRelease(for: liveLoan)).padding() }
            .navigationTitle("Release Document")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showReleaseSheet = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var rejectionReasonSheet: some View {
        NavigationStack {
            Form {
                Section("Reason") { TextField("Why are you rejecting?", text: $agreementRejectionReason, axis: .vertical).lineLimit(3...6) }
                Section {
                    Button { Task { await submitAgreementRejection() } } label: { Text("Submit Rejection").lsDestructiveButton() }
                    .buttonStyle(.plain).disabled(agreementRejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Rejection Reason")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAgreementRejectionReasonSheet = false; agreementRejectionReason = "" } } }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Logic

    private func refreshData() async {
        do {
            try await loanManager.fetchLoans()
            let fetchedPayments = try await loanManager.fetchPayments(for: liveLoan)
            self.payments = fetchedPayments
            applyInitialSelection(from: fetchedPayments)
        } catch { print("Refresh error: \(error)") }
    }

    private func applyInitialSelection(from fetched: [Payment]) {
        guard !didApplyInitialSelection, let targetID = initialSelectedPaymentID else {
            didApplyInitialSelection = true
            return
        }
        if let p = fetched.first(where: { $0.id == targetID }) { selectedPayment = p }
        didApplyInitialSelection = true
    }

    private func resolveLenderName() async -> String {
        if isLender { return authManager.currentUserProfile?.fullName ?? "Me" }
        return await authManager.fetchProfileName(for: liveLoan.lender_id) ?? "Unknown"
    }

    private func performTransition(to status: LoanStatus) {
        Task {
            do { try await loanManager.transitionLoanStatus(liveLoan, status: status) }
            catch { errorMsg = loanManager.friendlyTransitionErrorMessage(error); showError = true }
        }
    }

    private func performDelete() {
        Task {
            do { try await loanManager.deleteLoan(liveLoan); dismiss() }
            catch { errorMsg = "Delete failed: \(error.localizedDescription)"; showError = true }
        }
    }

    private func confirmReceipt() async {
        do { try await loanManager.confirmReceipt(loan: liveLoan) }
        catch { errorMsg = loanManager.friendlyTransitionErrorMessage(error); showError = true }
    }

    private func submitAgreementRejection() async {
        let reason = agreementRejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        do {
            try await loanManager.transitionLoanStatus(liveLoan, status: .cancelled, reason: reason)
            showAgreementRejectionReasonSheet = false
        } catch { errorMsg = loanManager.friendlyTransitionErrorMessage(error); showError = true }
    }

    private func openSigningURL() async {
        do {
            let url = try await loanManager.generatePandaDocSigningURL(loan: liveLoan)
            await UIApplication.shared.open(url, options: [:])
        } catch {
            errorMsg = "Could not generate signing link: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Realtime

    private func subscribeToPayments() async {
        guard let loanId = liveLoan.id else { return }
        unsubscribe()
        let channel = supabase.realtimeV2.channel("public:payments:\(loanId.uuidString)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "payments")
        realtimeTask = Task {
            for await _ in changes {
                if Task.isCancelled { break }
                await refreshData()
            }
        }
        try? await channel.subscribeWithError()
        realtimeChannel = channel
    }

    private func unsubscribe() {
        realtimeTask?.cancel(); realtimeTask = nil
        if let c = realtimeChannel { Task { await c.unsubscribe() }; realtimeChannel = nil }
    }
}

// MARK: - Paper Button Style

private extension View {
    func paperButton(filled: Bool = true) -> some View {
        self
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .foregroundStyle(filled ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(filled ? Color.primary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(filled ? 0 : 0.3), lineWidth: 1)
            )
    }
}
