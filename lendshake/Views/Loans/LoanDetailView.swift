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
    
    // Find the latest version of this loan from the manager to ensure UI updates
    var liveLoan: Loan {
        loanManager.loans.first(where: { $0.id == loan.id }) ?? loan
    }
    
    var body: some View {
        ScrollView {
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
                
                // Agreement Text
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
        .navigationTitle("Loan Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMsg ?? "Unknown error")
        }
    }
    

}
