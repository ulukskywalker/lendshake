//
//  LoanDetailView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct LoanDetailView: View {
    let loan: Loan
    @Environment(LoanManager.self) var loanManager
    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) var dismiss
    
    @State private var errorMsg: String?
    @State private var showError: Bool = false
    
    // Alert States
    @State private var showForgiveAlert: Bool = false

    @State private var showDeleteDraftAlert: Bool = false
    @State private var showCancelAlert: Bool = false
    
    @State private var showAgreementSheet: Bool = false
    @State private var showProofSheet: Bool = false
    @State private var showTermsSheet: Bool = false
    @State private var showReleaseSheet: Bool = false
    @State private var showFundingSheet: Bool = false
    @State private var lenderName: String = "Loading..."
    
    // Ledger States
    @State private var payments: [Payment] = []
    @State private var showPaymentSheet: Bool = false
    @State private var selectedPayment: Payment? // For detailed view


    
    // Find the latest version of this loan from the manager to ensure UI updates
    var liveLoan: Loan {
        loanManager.loans.first(where: { $0.id == loan.id }) ?? loan
    }
    
    var isLender: Bool {
        loanManager.isLender(of: liveLoan)
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
            do {
                try await loanManager.fetchLoans()
                self.payments = try await loanManager.fetchPayments(for: liveLoan)
            } catch {
                print("Refresh Error: \(error)")
            }
        }
        .background(Color.lsBackground)
        .navigationTitle(liveLoan.borrower_name ?? "Loan Ledger")
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
                    
                    if isLender {
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
                                liveLoan.status == .active ? "Forgive Loan" : "",
                                systemImage: "trash"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            Task {
                if let fetchedPayments = try? await loanManager.fetchPayments(for: liveLoan) {
                    self.payments = fetchedPayments
                }
            }
        }
        .sheet(isPresented: $showPaymentSheet) {
            PaymentSheet(loan: liveLoan, isPresented: $showPaymentSheet)
                .onDisappear {
                    Task {
                        try? await loanManager.fetchLoans()
                        self.payments = try await loanManager.fetchPayments(for: liveLoan)
                    }
                }
        }
        .sheet(item: $selectedPayment) { payment in
            TransactionDetailView(payment: payment, loan: liveLoan, isLender: isLender)
                .onDisappear {
                    Task {
                        self.payments = try await loanManager.fetchPayments(for: liveLoan)
                        try? await loanManager.fetchLoans() // Refresh balance
                    }
                }
        }
        .sheet(isPresented: $showAgreementSheet) {
            NavigationStack {
                ScrollView {
                    Text(liveLoan.agreement_text ?? AgreementGenerator.generate(for: liveLoan))
                        .padding()
                }
                .navigationTitle("Agreement")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showAgreementSheet = false }
                    }
                    
                    // Show "Sign" button if the current user needs to sign
                    if (isLender && liveLoan.status == .draft && liveLoan.lender_signed_at == nil) ||
                       (!isLender && liveLoan.status == .sent && liveLoan.borrower_signed_at == nil) {
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
                        LabeledContent("Lender", value: lenderName)
                        LabeledContent("Borrower", value: liveLoan.borrower_name ?? "Unknown")
                    }
                }
                .navigationTitle("Loan Terms")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showTermsSheet = false }
                    }
                }
                .task {
                    if isLender {
                        lenderName = authManager.currentUserProfile?.fullName ?? "Me"
                    } else {
                        if let name = await authManager.fetchProfileName(for: liveLoan.lender_id) {
                            lenderName = name
                        } else {
                            lenderName = "Unknown"
                        }
                    }
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
        // Alerts...
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMsg ?? "Unknown error") }

            .alert("Forgive Loan?", isPresented: $showForgiveAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Forgive", role: .destructive) {
                    Task {
                        try? await loanManager.updateLoanStatus(liveLoan, status: .forgiven)
                    }
                }
            } message: { Text("This action cannot be undone.") }
            .alert("Delete Draft?", isPresented: $showDeleteDraftAlert) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await loanManager.deleteLoan(liveLoan)
                        dismiss()
                    }
                }
            } message: { Text("Permanently delete this draft?") }
            .alert("Cancel Request?", isPresented: $showCancelAlert) {
                Button("Keep Loan", role: .cancel) { }
                Button("Cancel Loan", role: .destructive) {
                    Task {
                        try? await loanManager.updateLoanStatus(liveLoan, status: .cancelled)
                    }
                }
            } message: { Text("This will cancel the loan and stop the signature process.") }

            // Verify Payment alert removed (moved to TransactionDetailView)
    }
    
    // MARK: - Components
    

    
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
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.lsPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        } else {
            Text("Waiting for signatures...")
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    var sentActions: some View {
        if !isLender && liveLoan.borrower_signed_at == nil {
            Button {
                showAgreementSheet = true
            } label: {
                Text("Review & Accept Loan")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.lsPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
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
                .bold()
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
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
                    try? await loanManager.confirmReceipt(loan: liveLoan)
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Confirm I Received Money")
                }
                .bold()
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
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
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.lsPrimary)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
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
            .bold()
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.1))
            .foregroundColor(.primary)
            .cornerRadius(12)
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
                ForEach(payments) { payment in
                    PaymentRow(payment: payment)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                        )
                        .onTapGesture {
                            selectedPayment = payment
                        }
                }
            }
        }
    }
}
