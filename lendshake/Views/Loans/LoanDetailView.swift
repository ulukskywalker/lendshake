//
//  LoanDetailView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import Supabase

struct LoanDetailView: View {
    let loan: Loan
    let initialSelectedPaymentID: UUID?
    @Environment(LoanManager.self) var loanManager
    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) var dismiss
    
    @State private var errorMsg: String?
    @State private var showError: Bool = false
    
    // Alert States
    @State private var showForgiveAlert: Bool = false

    @State private var showDeleteDraftAlert: Bool = false
    @State private var showCancelAlert: Bool = false
    @State private var showRejectAlert: Bool = false
    @State private var showAgreementRejectionReasonSheet: Bool = false
    @State private var agreementRejectionReason: String = ""
    
    @State private var showAgreementSheet: Bool = false
    @State private var showBorrowerSignSheet: Bool = false
    @State private var showProofSheet: Bool = false
    @State private var showTermsSheet: Bool = false
    @State private var showReleaseSheet: Bool = false
    @State private var showFundingSheet: Bool = false
    @State private var lenderName: String = "Loading..."
    
    // Ledger States
    @State private var payments: [Payment] = []
    @State private var showPaymentSheet: Bool = false
    @State private var selectedPayment: Payment? // For detailed view
    @State private var paymentsRealtimeChannel: RealtimeChannelV2?
    @State private var paymentsRealtimeTask: Task<Void, Never>?
    @State private var didSubmitPaymentSheet: Bool = false
    @State private var didApplyInitialPaymentSelection: Bool = false
    @State private var borrowerFirstNameInput: String = ""
    @State private var borrowerLastNameInput: String = ""
    @State private var borrowerAddressLine1Input: String = ""
    @State private var borrowerAddressLine2Input: String = ""
    @State private var borrowerPhoneInput: String = ""
    @State private var borrowerStateInput: String = "IL"
    @State private var borrowerCountryInput: String = ProfileReferenceData.defaultCountry
    @State private var borrowerPostalCodeInput: String = ""
    @State private var saveBorrowerInfoForFuture: Bool = true
    @State private var borrowerSignInFlight: Bool = false


    
    // Find the latest version of this loan from the manager to ensure UI updates
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
                // 0. Journey Tracker
                LoanJourneyView(status: liveLoan.status, isLender: isLender)
                
                // 1. Header Card
                LoanHeaderCard(loan: liveLoan, isLender: isLender)
                
                // 2. Action Buttons
                actionSection
                
                // 3. Payment History
                historySection
            }
            .padding()
        }
        .refreshable {
            await refreshLoanDetailData()
        }
        .background(Color.lsBackground)
        .navigationTitle(liveLoan.borrower_name_snapshot ?? liveLoan.borrower_name ?? liveLoan.borrower_email ?? "Loan Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAgreementSheet = true
                    } label: {
                        Label("View Contract", systemImage: "doc.text")
                    }
                    
                    Button {
                        showTermsSheet = true
                    } label: {
                        Label("View Terms", systemImage: "list.clipboard")
                    }
                    
                    if isLender && (liveLoan.status == .draft || liveLoan.status == .sent || liveLoan.status == .active) {
                        Button(role: .destructive) {
                            if liveLoan.status == .draft {
                                showDeleteDraftAlert = true
                            } else if liveLoan.status == .sent {
                                showCancelAlert = true
                            } else if liveLoan.status == .active {
                                showForgiveAlert = true
                            }
                        } label: {
                            Label(
                                liveLoan.status == .draft ? "Delete Draft" :
                                liveLoan.status == .sent ? "Cancel Request" :
                                "Forgive Loan",
                                systemImage: "trash"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: liveLoan.id) {
            async let fetchedPayments = loanManager.fetchPayments(for: liveLoan)
            async let fetchedLenderName = resolveLenderName()

            do {
                let refreshedPayments = try await fetchedPayments
                payments = refreshedPayments
                applyInitialPaymentSelectionIfNeeded(from: refreshedPayments)
            } catch {
                print("Failed to load payments: \(error)")
            }
            lenderName = await fetchedLenderName
            await subscribeToPaymentsRealtime()
        }
        .onDisappear {
            Task { await unsubscribeFromPaymentsRealtime() }
        }
        .sheet(isPresented: $showPaymentSheet) {
            PaymentSheet(
                loan: liveLoan,
                isPresented: $showPaymentSheet,
                onSubmitted: {
                    didSubmitPaymentSheet = true
                    Task { await refreshLoanDetailData() }
                }
            )
                .onDisappear {
                    if !didSubmitPaymentSheet {
                        Task { await refreshLoanDetailData() }
                    }
                    didSubmitPaymentSheet = false
                }
        }
        .sheet(item: $selectedPayment) { payment in
            TransactionDetailView(payment: payment, loan: liveLoan, isLender: isLender)
                .onDisappear {
                    Task { await refreshLoanDetailData() }
                }
        }
        .sheet(isPresented: $showBorrowerSignSheet) {
            NavigationStack {
                Form {
                    Section("Your Legal Identity") {
                        TextField("Legal First Name", text: $borrowerFirstNameInput)
                            .textInputAutocapitalization(.words)
                        TextField("Legal Last Name", text: $borrowerLastNameInput)
                            .textInputAutocapitalization(.words)
                        TextField("Address Line 1", text: $borrowerAddressLine1Input)
                            .textInputAutocapitalization(.words)
                        TextField("Apt / Suite (Optional)", text: $borrowerAddressLine2Input)
                            .textInputAutocapitalization(.words)
                    }

                    Section("Your Contact Info") {
                        TextField("Mobile Phone", text: $borrowerPhoneInput)
                            .keyboardType(.phonePad)
                        Picker("State of Residence", selection: $borrowerStateInput) {
                            ForEach(ProfileReferenceData.usStates, id: \.self) { state in
                                Text(state).tag(state)
                            }
                        }
                        TextField("Country", text: $borrowerCountryInput)
                            .textInputAutocapitalization(.words)
                        TextField("Postal Code / Index", text: $borrowerPostalCodeInput)
                            .textInputAutocapitalization(.characters)
                    }
                    
                    Section {
                        Toggle("Save this info for future use", isOn: $saveBorrowerInfoForFuture)
                    }
                }
                .navigationTitle("Complete Before Signing")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showBorrowerSignSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                await signBorrowerWithProfile()
                            }
                        } label: {
                            if borrowerSignInFlight {
                                ProgressView()
                            } else {
                                Text("Sign & Send Back")
                                    .bold()
                            }
                        }
                        .disabled(borrowerSignInFlight)
                    }
                }
            }
        }
        .sheet(isPresented: $showAgreementSheet) {
            NavigationStack {
                ScrollView {
                    Text(liveLoan.agreement_text ?? AgreementGenerator.generate(for: liveLoan))
                        .padding()
                        .font(.system(.body, design: .monospaced))
                }
                .navigationTitle("Legal Agreement")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showAgreementSheet = false }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: liveLoan.agreement_text ?? AgreementGenerator.generate(for: liveLoan))
                    }
                    
                    // Show "Sign" button if the current user needs to sign
                    if isLender && liveLoan.status == .draft && liveLoan.lender_signed_at == nil {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                Task {
                                    do {
                                        try await loanManager.signLoan(loan: liveLoan)
                                        showAgreementSheet = false
                                    } catch {
                                        errorMsg = "Signing failed: \(error.localizedDescription)"
                                        showError = true
                                    }
                                }
                            } label: {
                                Text("Sign & Accept")
                                    .bold()
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTermsSheet) {
            NavigationStack {
                List {
                    Section("Financial Terms") {
                        LabeledContent("Principal", value: liveLoan.principal_amount.formatted(.currency(code: "USD")))
                        LabeledContent("Interest Rate", value: "\(liveLoan.interest_rate.formatted())%")
                        LabeledContent("Repayment", value: liveLoan.repayment_schedule)
                        LabeledContent("Late Fee Policy", value: liveLoan.late_fee_policy)
                    }
                    Section("Dates") {
                        if let created = liveLoan.created_at {
                            LabeledContent("Created On", value: created.formatted(date: .abbreviated, time: .omitted))
                        }
                        LabeledContent("Maturity Date", value: liveLoan.maturity_date.formatted(date: .abbreviated, time: .omitted))
                    }
                    Section("Parties") {
                        LabeledContent("Lender", value: liveLoan.lender_name_snapshot ?? lenderName)
                        LabeledContent("Borrower", value: liveLoan.borrower_name_snapshot ?? liveLoan.borrower_name ?? liveLoan.borrower_email ?? "Unknown")
                    }
                    if liveLoan.status == .cancelled,
                       let reason = liveLoan.agreement_rejection_reason?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !reason.isEmpty {
                        Section("Rejection") {
                            Text(reason)
                                .font(.body)
                        }
                    }
                }
                .navigationTitle("Loan Terms")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showTermsSheet = false }
                    }
                }
                .task {
                    lenderName = await resolveLenderName()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showReleaseSheet) {
            NavigationStack {
                ScrollView {
                    Text(AgreementGenerator.generateRelease(for: liveLoan))
                        .padding()
                }
                .navigationTitle("Release Document")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showReleaseSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFundingSheet) {
            FundingSheet(loan: liveLoan, isPresented: $showFundingSheet)
        }
        .sheet(isPresented: $showAgreementRejectionReasonSheet) {
            NavigationStack {
                Form {
                    Section("Reason") {
                        TextField("Why are you rejecting?", text: $agreementRejectionReason, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    Section {
                        Button {
                            Task { await submitAgreementRejection() }
                        } label: {
                            Text("Submit Rejection")
                                .lsDestructiveButton()
                        }
                        .buttonStyle(.plain)
                        .disabled(agreementRejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .listRowBackground(Color.clear)
                }
                .navigationTitle("Rejection Reason")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showAgreementRejectionReasonSheet = false
                            agreementRejectionReason = ""
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        // Alerts...
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMsg ?? "Unknown error") }

            .alert("Forgive Loan?", isPresented: $showForgiveAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Forgive", role: .destructive) {
                    Task {
                        do {
                            try await loanManager.transitionLoanStatus(liveLoan, status: .forgiven)
                        } catch {
                            errorMsg = loanManager.friendlyTransitionErrorMessage(error)
                            showError = true
                        }
                    }
                }
            } message: { Text("This action cannot be undone.") }
            .alert("Delete Draft?", isPresented: $showDeleteDraftAlert) {
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await loanManager.deleteLoan(liveLoan)
                            dismiss()
                        } catch {
                            errorMsg = "Delete failed: \(error.localizedDescription)"
                            showError = true
                        }
                    }
                }
            } message: { Text("Permanently delete this draft?") }
            .alert("Cancel Request?", isPresented: $showCancelAlert) {
                Button("Keep Loan", role: .cancel) { }
                Button("Cancel Loan", role: .destructive) {
                    showAgreementRejectionReasonSheet = true
                }
            } message: { Text("This will cancel the loan and stop the signature process.") }
            .alert("Reject Agreement?", isPresented: $showRejectAlert) {
                Button("Keep Reviewing", role: .cancel) { }
                Button("Reject Loan", role: .destructive) {
                    showAgreementRejectionReasonSheet = true
                }
            } message: { Text("This will reject the agreement and cancel this loan request.") }

            // Verify Payment alert removed (moved to TransactionDetailView)
    }
    
    // MARK: - Components

    @MainActor
    private func refreshLoanDetailData() async {
        do {
            try await loanManager.fetchLoans()
            let refreshed = try await loanManager.fetchPayments(for: liveLoan)
            self.payments = refreshed
            applyInitialPaymentSelectionIfNeeded(from: refreshed)
        } catch {
            print("Loan detail refresh error: \(error)")
        }
    }

    @MainActor
    private func refreshPaymentsOnly() async {
        do {
            let refreshed = try await loanManager.fetchPayments(for: liveLoan)
            self.payments = refreshed
            applyInitialPaymentSelectionIfNeeded(from: refreshed)
        } catch {
            print("Payments refresh error: \(error)")
        }
    }

    private func applyInitialPaymentSelectionIfNeeded(from currentPayments: [Payment]) {
        guard !didApplyInitialPaymentSelection else { return }
        guard let targetPaymentID = initialSelectedPaymentID else {
            didApplyInitialPaymentSelection = true
            return
        }
        guard let targetPayment = currentPayments.first(where: { $0.id == targetPaymentID }) else { return }
        selectedPayment = targetPayment
        didApplyInitialPaymentSelection = true
    }

    @MainActor
    private func subscribeToPaymentsRealtime() async {
        guard let loanId = liveLoan.id else { return }
        await unsubscribeFromPaymentsRealtime()

        let channel = supabase.realtimeV2.channel("public:payments:\(loanId.uuidString)")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "payments"
        )

        paymentsRealtimeTask = Task {
            for await change in changes {
                if Task.isCancelled { break }
                if Self.isPaymentChange(change, for: loanId) {
                    await refreshPaymentsOnly()
                }
            }
        }

        do {
            try await channel.subscribeWithError()
            paymentsRealtimeChannel = channel
        } catch {
            print("Payments realtime subscribe error: \(error)")
            paymentsRealtimeTask?.cancel()
            paymentsRealtimeTask = nil
        }
    }

    @MainActor
    private func unsubscribeFromPaymentsRealtime() async {
        paymentsRealtimeTask?.cancel()
        paymentsRealtimeTask = nil
        if let channel = paymentsRealtimeChannel {
            await channel.unsubscribe()
            paymentsRealtimeChannel = nil
        }
    }

    private static func isPaymentChange(_ change: AnyAction, for loanId: UUID) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch change {
        case .insert(let action):
            guard let payment = try? action.decodeRecord(as: Payment.self, decoder: decoder) else { return false }
            return payment.loan_id == loanId
        case .update(let action):
            guard let payment = try? action.decodeRecord(as: Payment.self, decoder: decoder) else { return false }
            return payment.loan_id == loanId
        case .delete(let action):
            let oldRecord = action.oldRecord
            guard let data = try? JSONEncoder().encode(oldRecord),
                  let deleted = try? decoder.decode(DeletedPaymentRecord.self, from: data) else {
                return true
            }
            return deleted.loan_id == nil || deleted.loan_id == loanId
        }
    }

    private struct DeletedPaymentRecord: Decodable {
        let loan_id: UUID?
    }

    
    
    @ViewBuilder
    var actionSection: some View {
        VStack(spacing: 12) {
            switch liveLoan.status {
            case .draft:
                draftActions
            case .sent:
                sentActions
            case .approved:
                approvedActions
            case .funding_sent:
                fundingSentActions
            case .active:
                activeActions
            case .completed, .forgiven:
                completedActions
            case .cancelled:
                EmptyView()
            }
        }
    }
    
    // MARK: - Sub-Action Views
    
    @ViewBuilder
    var draftActions: some View {
        if isLender && liveLoan.lender_signed_at == nil {
            Button {
                showAgreementSheet = true
            } label: {
                Text("Review & Sign Agreement")
                    .lsPrimaryButton()
            }
        } else {
            Text("Waiting for signatures...")
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    var sentActions: some View {
        if !isLender && liveLoan.borrower_signed_at == nil {
            VStack(spacing: 10) {
                Button {
                    prepareBorrowerProfileInputs()
                    showBorrowerSignSheet = true
                } label: {
                    Text("Complete Info & Sign")
                        .lsPrimaryButton()
                }

                Button {
                    showRejectAlert = true
                } label: {
                    Text("Reject Agreement")
                        .lsDestructiveButton()
                }
            }
        } else if isLender {
            VStack(spacing: 10) {
                Text("Waiting for borrower to sign...")
                    .foregroundStyle(.secondary)

                Button {
                    showCancelAlert = true
                } label: {
                    Text("Cancel Request")
                        .lsDestructiveButton()
                }
            }
        } else {
            Text("Waiting for borrower to sign...")
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    var approvedActions: some View {
        if isLender {
            Button {
                showFundingSheet = true
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text("I Have Sent the Money")
                }
                .lsPrimaryButton(background: .green)
            }
        } else {
            HStack {
                Image(systemName: "hourglass")
                Text("Waiting for Lender to Release Funds")
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    var fundingSentActions: some View {
        if isLender {
            HStack {
                Image(systemName: "clock")
                Text("Waiting for borrower to confirm receipt...")
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        } else {
            Button {
                Task {
                    do {
                        try await loanManager.confirmReceipt(loan: liveLoan)
                    } catch {
                        errorMsg = loanManager.friendlyTransitionErrorMessage(error)
                        showError = true
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Confirm I Received Money")
                }
                .lsPrimaryButton(background: .green)
            }
        }
    }
    
    @ViewBuilder
    var activeActions: some View {
        if !isLender {
            Button {
                showPaymentSheet = true
            } label: {
                Text("Record Payment")
                    .lsPrimaryButton()
            }
        }
    }
    
    @ViewBuilder
    var completedActions: some View {
        Button {
            showReleaseSheet = true
        } label: {
            HStack {
                Image(systemName: "checkmark.seal")
                Text("View Release Document")
            }
            .lsSecondaryButton()
        }
    }

    @ViewBuilder
    var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History")
                .font(.headline)
            
            if payments.isEmpty {
                Text("No payments recorded yet.")
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.vertical)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(payments) { payment in
                        PaymentRow(payment: payment, isLender: isLender)
                            .padding()
                            .lsCardContainer()
                            .onTapGesture {
                                selectedPayment = payment
                            }
                    }
                }
            }
        }
    }
    private func resolveLenderName() async -> String {
        if isLender {
            return authManager.currentUserProfile?.fullName ?? "Me"
        }
        return await authManager.fetchProfileName(for: liveLoan.lender_id) ?? "Unknown"
    }
    
    private func prepareBorrowerProfileInputs() {
        let profile = authManager.currentUserProfile
        borrowerFirstNameInput = profile?.first_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        borrowerLastNameInput = profile?.last_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        borrowerAddressLine1Input = profile?.address_line_1?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        borrowerAddressLine2Input = profile?.address_line_2?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        borrowerPhoneInput = profile?.phone_number?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        borrowerStateInput = (profile?.residence_state?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "IL")
        borrowerCountryInput = profile?.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ProfileReferenceData.defaultCountry
        borrowerPostalCodeInput = profile?.postal_code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        saveBorrowerInfoForFuture = true
    }

    @MainActor
    private func signBorrowerWithProfile() async {
        let normalizedFirst = borrowerFirstNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLast = borrowerLastNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddressLine1 = borrowerAddressLine1Input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddressLine2 = borrowerAddressLine2Input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = borrowerPhoneInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedState = borrowerStateInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedCountry = borrowerCountryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPostalCode = borrowerPostalCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFirst.isEmpty, !normalizedLast.isEmpty else {
            errorMsg = "Your legal first and last name are required."
            showError = true
            return
        }
        if ProfileValidation.validateAddressLine1(normalizedAddressLine1) != nil {
            errorMsg = "Address Line 1 is required."
            showError = true
            return
        }
        if let phoneError = ProfileValidation.validatePhone(normalizedPhone, required: true) {
            errorMsg = phoneError
            showError = true
            return
        }
        if let stateError = ProfileValidation.validateState(normalizedState) {
            errorMsg = stateError
            showError = true
            return
        }
        if let countryError = ProfileValidation.validateCountry(normalizedCountry) {
            errorMsg = countryError
            showError = true
            return
        }
        if let postalCodeError = ProfileValidation.validatePostalCode(normalizedPostalCode) {
            errorMsg = postalCodeError
            showError = true
            return
        }

        borrowerSignInFlight = true
        defer { borrowerSignInFlight = false }

        do {
            if saveBorrowerInfoForFuture {
                try await authManager.createProfile(
                    firstName: normalizedFirst,
                    lastName: normalizedLast,
                    addressLine1: normalizedAddressLine1,
                    addressLine2: normalizedAddressLine2.isEmpty ? nil : normalizedAddressLine2,
                    state: normalizedState,
                    country: normalizedCountry,
                    postalCode: normalizedPostalCode,
                    phoneNumber: normalizedPhone
                )
            }

            try await loanManager.signLoanAsBorrower(
                loan: liveLoan,
                firstName: normalizedFirst,
                lastName: normalizedLast,
                addressLine1: normalizedAddressLine1,
                addressLine2: normalizedAddressLine2,
                state: normalizedState,
                country: normalizedCountry,
                postalCode: normalizedPostalCode,
                phoneNumber: normalizedPhone
            )
            showBorrowerSignSheet = false
        } catch {
            errorMsg = "Signing failed: \(error.localizedDescription)"
            showError = true
        }
    }

    @MainActor
    private func submitAgreementRejection() async {
        let trimmedReason = agreementRejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            errorMsg = "Please provide a rejection reason."
            showError = true
            return
        }

        do {
            try await loanManager.transitionLoanStatus(
                liveLoan,
                status: .cancelled,
                reason: trimmedReason
            )
            showAgreementRejectionReasonSheet = false
            agreementRejectionReason = ""
        } catch {
            errorMsg = loanManager.friendlyTransitionErrorMessage(error)
            showError = true
        }
    }
}
