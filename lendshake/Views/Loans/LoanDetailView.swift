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
    @Environment(\.dismiss) var dismiss
    
    @State private var errorMsg: String?
    @State private var showError: Bool = false
    
    // Alert States
    @State private var showForgiveAlert: Bool = false
    @State private var showPaidOffAlert: Bool = false
    
    @State private var showAgreementSheet: Bool = false
    
    // Find the latest version of this loan from the manager to ensure UI updates
    var liveLoan: Loan {
        loanManager.loans.first(where: { $0.id == loan.id }) ?? loan
    }
    
    var body: some View {
        ScrollView {
            // Show Active View for Active, Paid Off, and Forgiven loans
            if [.active, .completed, .forgiven].contains(liveLoan.status) {
                activeLoanView
            } else {
                draftLoanView
            }
        }
        .navigationTitle("Loan Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if [.active, .completed, .forgiven].contains(liveLoan.status) {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAgreementSheet = true
                    } label: {
                        Image(systemName: "doc.text")
                    }
                }
            }
        }
        .sheet(isPresented: $showAgreementSheet) {
            NavigationStack {
                ScrollView {
                    Text(liveLoan.agreement_text ?? "No agreement text found.")
                        .padding()
                }
                .navigationTitle("Agreement")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showAgreementSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        // Error Alert
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMsg ?? "Unknown error")
        }
        // Paid Off Confirmation Alert
        .alert("Mark as Paid Off?", isPresented: $showPaidOffAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Confirm Paid", role: .none) {
                Task {
                    do {
                        try await loanManager.updateLoanStatus(liveLoan, status: .completed)
                    } catch {
                        errorMsg = error.localizedDescription
                        showError = true
                    }
                }
            }
        } message: {
            Text("This will mark the loan as fully repaid and move it to history. This action cannot be undone.")
        }
        // Forgive Confirmation Alert
        .alert("Forgive this Loan?", isPresented: $showForgiveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Forgive Debt", role: .destructive) {
                Task {
                    do {
                        try await loanManager.updateLoanStatus(liveLoan, status: .forgiven)
                    } catch {
                        errorMsg = error.localizedDescription
                        showError = true
                    }
                }
            }
        } message: {
            Text("WARNING: Forgiving a loan means the borrower no longer owes you this money. \n\nIMPORTANT: Amounts over $18,000 (2024 limit) may be subject to Gift Tax reporting. Consult a tax professional.")
        }
    }
    
    // MARK: - Active/Closed View
    var activeLoanView: some View {
        VStack(spacing: 24) {
            // Balance Card
            VStack(spacing: 8) {
                Text(liveLoan.status == .completed ? "Amount Paid" : (liveLoan.status == .forgiven ? "Amount Forgiven" : "Remaining Balance"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(liveLoan.principal_amount, format: .currency(code: "USD"))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(liveLoan.status == .forgiven ? .gray : Color.lsPrimary)
                    .strikethrough(liveLoan.status == .forgiven)
                    .opacity(liveLoan.status == .forgiven ? 0.6 : 1.0)
                
                LoanStatusBadge(status: liveLoan.status)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            
            // Stats Grid
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Interest Rate")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(liveLoan.interest_rate, format: .percent)
                        .font(.headline)
                }
                Divider()
                VStack(alignment: .leading) {
                    Text("Due Date")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(liveLoan.maturity_date.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                }
                Spacer()
            }
            .padding()
            .background(Color.lsBackground)
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Transactions Section
            VStack(alignment: .leading, spacing: 16) {
                
                if liveLoan.status == .active {
                    // Manual Payment Tip
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "banknote")
                            .foregroundStyle(.blue)
                        Text("Payments are made outside the app (Venmo, Zelle, Cash). Record them here to update the balance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                } else if liveLoan.status == .completed {
                     HStack(alignment: .top, spacing: 12) {
                         Image(systemName: "checkmark.circle.fill")
                             .foregroundStyle(.green)
                         Text("This loan has been fully paid off.")
                             .font(.subheadline)
                             .foregroundStyle(.primary)
                     }
                     .frame(maxWidth: .infinity, alignment: .center)
                     .padding()
                     .background(Color.green.opacity(0.1))
                     .cornerRadius(12)
                } else if liveLoan.status == .forgiven {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.gray)
                        Text("This loan was forgiven by the lender.")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
               }
                
                HStack {
                    Text("Transactions")
                        .font(.headline)
                    Spacer()
                    if liveLoan.status == .active {
                        Button("See All") { }
                            .font(.subheadline)
                    }
                }
                
                // Placeholder for now
                if liveLoan.status == .active {
                    ContentUnavailableView("No payments recorded", systemImage: "list.bullet.clipboard")
                        .frame(height: 150)
                        .background(Color(.secondarySystemBackground).opacity(0.5))
                        .cornerRadius(12)
                    
                    Button {
                        // TODO: Record Payment Action
                    } label: {
                        Label("Record Payment", systemImage: "plus")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.lsPrimary)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    
                    // Management Menu
                    Menu {
                        Button {
                            showPaidOffAlert = true
                        } label: {
                            Label("Mark as Paid Off", systemImage: "checkmark.circle")
                        }
                        
                        Button(role: .destructive) {
                            showForgiveAlert = true
                        } label: {
                            Label("Forgive Debt", systemImage: "hand.raised.slash.fill")
                        }
                    } label: {
                        Text("Manage Loan Status")
                            .font(.subheadline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Color.lsTextSecondary)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top)
    }
    
    // MARK: - Draft/Pending View (Original)
    var draftLoanView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(liveLoan.borrower_name ?? "Unknown Borrower")
                        .font(.title)
                        .bold()
                    LoanStatusBadge(status: liveLoan.status)
                }
                Spacer()
                Text(liveLoan.principal_amount, format: .currency(code: "USD"))
                    .font(.title)
                    .bold()
                    .foregroundStyle(Color.lsPrimary)
            }
            .padding()
                        Divider()
                
                // Safety Tip
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Safety Tip: When to Transfer Money")
                            .font(.subheadline)
                            .bold()
                        
                        Text("For your protection, do not transfer any funds until BOTH you and the borrower have fully signed this agreement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Agreement")
                    .font(.headline)
                
                ScrollView {
                    Text(liveLoan.agreement_text ?? AgreementGenerator.generate(for: liveLoan))
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }
                .frame(height: 300) // Fixed height for agreement scroll
            }
            .padding()
            
            // Signing Section
            if liveLoan.lender_signed_at == nil {
                VStack(spacing: 12) {
                    Text("By clicking below, you agree to the terms above and certify that this information is correct.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        Task {
                            do {
                                try await loanManager.signLoan(loan: liveLoan)
                            } catch {
                                print("Signing Error: \(error)")
                                errorMsg = "Signing failed: \(error.localizedDescription)"
                                showError = true
                            }
                        }
                    } label: {
                        if loanManager.isLoading {
                            ProgressView()
                        } else {
                            Text("I Agree & Sign")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.lsPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(loanManager.isLoading)
                }
                .padding()
            } else {
                // Already Signed
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    Text("Signed by Lender on \(liveLoan.lender_signed_at!.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .padding()
            }
        }
    }
}
