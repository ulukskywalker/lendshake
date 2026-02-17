//
//  LoanDetailView.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import Supabase

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
    
    @State private var showAgreementSheet: Bool = false
    @State private var showBorrowerSignSheet: Bool = false
    @State private var showTermsSheet: Bool = false
    @State private var showReleaseSheet: Bool = false
    @State private var showFundingSheet: Bool = false
    @State private var showPaymentSheet: Bool = false
    
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
            VStack(spacing: 24) {
                LoanJourneyView(status: liveLoan.status, isLender: isLender)
                LoanHeaderCardView(loan: liveLoan, isLender: isLender)
                actionSection
                historySection
            }
            .padding()
        }
        .refreshable { await refreshData() }
        .background(Color.appBackground)
        .navigationTitle(liveLoan.borrower_name_snapshot ?? liveLoan.borrower_name ?? liveLoan.borrower_email ?? "Loan Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { menuToolbar }
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
        .sheet(isPresented: $showAgreementSheet) {
            AgreementReviewSheetView(isPresented: $showAgreementSheet, loan: liveLoan, isLender: isLender)
        }
        .sheet(isPresented: $showTermsSheet) { termsSheet }
        .sheet(isPresented: $showReleaseSheet) { releaseSheet }
        .sheet(isPresented: $showFundingSheet) { FundingSheetView(loan: liveLoan, isPresented: $showFundingSheet) }
        .sheet(isPresented: $showAgreementRejectionReasonSheet) { rejectionReasonSheet }
        .alert("Error", isPresented: $showError) { Button("OK", role: .cancel) { } } message: { Text(errorMsg ?? "Unknown error") }
        .alert("Forgive Loan?", isPresented: $showForgiveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Forgive", role: .destructive) { performTransition(to: .forgiven) }
        } message: { Text("This action cannot be undone.") }
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
    
    // MARK: - Sections

    @ViewBuilder
    private var actionSection: some View {
        VStack(spacing: 12) {
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
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History").font(.headline)
            if payments.isEmpty {
                Text("No payments recorded yet.").foregroundStyle(.secondary).italic().padding(.vertical)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(payments) { payment in
                        PaymentRowView(payment: payment, isLender: isLender)
                            .padding().lsCardContainer()
                            .onTapGesture { selectedPayment = payment }
                    }
                }
            }
        }
    }

    // MARK: - Sub-Actions

    @ViewBuilder
    private var draftActions: some View {
        if isLender && liveLoan.lender_signed_at == nil {
            Button { showAgreementSheet = true } label: { Text("Review & Sign Agreement").lsPrimaryButton() }
        } else {
            Text("Waiting for signatures...").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sentActions: some View {
        if !isLender && liveLoan.borrower_signed_at == nil {
            VStack(spacing: 10) {
                Button { showBorrowerSignSheet = true } label: { Text("Complete Info & Sign").lsPrimaryButton() }
                Button { showRejectAlert = true } label: { Text("Reject Agreement").lsDestructiveButton() }
            }
        } else if isLender {
            VStack(spacing: 10) {
                Text("Waiting for borrower to sign...").foregroundStyle(.secondary)
                Button { showCancelAlert = true } label: { Text("Cancel Request").lsDestructiveButton() }
            }
        } else {
            Text("Waiting for borrower to sign...").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var approvedActions: some View {
        if isLender {
            Button { showFundingSheet = true } label: {
                HStack { Image(systemName: "paperplane.fill"); Text("I Have Sent the Money") }
                .lsPrimaryButton(background: .green)
            }
        } else {
            statusPlaceholder(systemName: "hourglass", text: "Waiting for Lender to Release Funds")
        }
    }

    @ViewBuilder
    private var fundingSentActions: some View {
        if isLender {
            statusPlaceholder(systemName: "clock", text: "Waiting for borrower to confirm receipt...")
        } else {
            Button { Task { await confirmReceipt() } } label: {
                HStack { Image(systemName: "checkmark.seal.fill"); Text("Confirm I Received Money") }
                .lsPrimaryButton(background: .green)
            }
        }
    }

    @ViewBuilder
    private var activeActions: some View {
        if !isLender {
            Button { showPaymentSheet = true } label: { Text("Record Payment").lsPrimaryButton() }
        }
    }

    @ViewBuilder
    private var completedActions: some View {
        Button { showReleaseSheet = true } label: {
            HStack { Image(systemName: "checkmark.seal"); Text("View Release Document") }
            .lsSecondaryButton()
        }
    }

    private func statusPlaceholder(systemName: String, text: String) -> some View {
        HStack { Image(systemName: systemName); Text(text) }
            .font(.headline).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1)).cornerRadius(12)
    }

    // MARK: - Toolbars

    private var menuToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { showAgreementSheet = true } label: { Label("View Contract", systemImage: "doc.text") }
                Button { showTermsSheet = true } label: { Label("View Terms", systemImage: "list.clipboard") }
                if isLender && [.draft, .sent, .active].contains(liveLoan.status) {
                    Button(role: .destructive) {
                        switch liveLoan.status {
                        case .draft: showDeleteDraftAlert = true
                        case .sent: showCancelAlert = true
                        case .active: showForgiveAlert = true
                        default: break
                        }
                    } label: {
                        Label(liveLoan.status == .draft ? "Delete Draft" : liveLoan.status == .sent ? "Cancel Request" : "Forgive Loan", systemImage: "trash")
                    }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    // MARK: - Sheets

    private var termsSheet: some View {
        NavigationStack {
            List {
                Section("Financial Terms") {
                    LabeledContent("Principal", value: liveLoan.principal_amount.formatted(.currency(code: "USD")))
                    LabeledContent("Interest Rate", value: "\(liveLoan.interest_rate.formatted())%")
                    LabeledContent("Repayment", value: liveLoan.repayment_schedule)
                    LabeledContent("Late Fee Policy", value: liveLoan.late_fee_policy)
                }
                Section("Dates") {
                    if let created = liveLoan.created_at { LabeledContent("Created On", value: created.formatted(date: .abbreviated, time: .omitted)) }
                    LabeledContent("Maturity Date", value: liveLoan.maturity_date.formatted(date: .abbreviated, time: .omitted))
                }
                Section("Parties") {
                    LabeledContent("Lender", value: liveLoan.lender_name_snapshot ?? lenderName)
                    LabeledContent("Borrower", value: liveLoan.borrower_name_snapshot ?? liveLoan.borrower_name ?? liveLoan.borrower_email ?? "Unknown")
                }
                if liveLoan.status == .cancelled, let reason = liveLoan.agreement_rejection_reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                    Section("Rejection") { Text(reason).font(.body) }
                }
            }
            .navigationTitle("Loan Terms")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showTermsSheet = false } } }
        }
        .presentationDetents([.medium, .large])
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
