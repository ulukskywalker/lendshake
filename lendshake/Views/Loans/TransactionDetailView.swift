//
//  TransactionDetailView.swift
//  lendshake
//
//  Created by Assistant on 2/4/26.
//

import SwiftUI

struct TransactionDetailView: View {
    let payment: Payment
    let loan: Loan // Needed for context (borrower/lender names)
    let isLender: Bool
    @Environment(LoanManager.self) var loanManager
    @Environment(\.dismiss) var dismiss
    
    // Actions are moved here from the alert
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    @State private var signedImageURL: URL?
    @State private var showRejectReasonSheet: Bool = false
    @State private var rejectionReason: String = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Amount Header
                    VStack(spacing: 8) {
                        Text(payment.type.rawValue.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(1)
                        
                        Text(payment.amount.formatted(.currency(code: "USD")))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                        
                        statusBadge
                    }
                    .padding(.top, 32)
                    
                    Divider()
                    
                    // 2. Details List
                    VStack(spacing: 16) {
                        detailRow(label: "Date", value: payment.date.formatted(date: .long, time: .omitted))
                        detailRow(label: "Transaction ID", value: payment.id?.uuidString.prefix(8).uppercased() ?? "PENDING")
                        
                        if let created = payment.created_at {
                            detailRow(label: "Recorded On", value: created.formatted(date: .numeric, time: .shortened))
                        }
                        if payment.status == .rejected,
                           let reason = payment.rejection_reason?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !reason.isEmpty {
                            detailRow(label: "Rejection Reason", value: reason)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                    
                    // 3. Proof / Attachment
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ATTACHMENT")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.secondary)
                        
                        // Check if we have a path, then check if we have the signed URL
                        if let proofPath = payment.proof_url, !proofPath.isEmpty {
                            if let url = signedImageURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: 200)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .cornerRadius(12)
                                            .frame(maxHeight: 400)
                                    case .failure:
                                        VStack {
                                            Image(systemName: "exclamationmark.triangle")
                                                .font(.largeTitle)
                                                .foregroundStyle(.red)
                                            Text("Failed to load image")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 200)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(12)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            } else {
                                // Loading state while fetching URL
                                ProgressView("Loading proof...")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(12)
                                    .task {
                                        // Fetch the signed URL
                                        do {
                                            if let signed = try await StorageManager.shared.getSignedURL(path: proofPath) {
                                                self.signedImageURL = signed
                                            }
                                        } catch {
                                            print("Failed to sign URL: \(error)")
                                        }
                                    }
                            }
                        } else {
                            HStack {
                                Image(systemName: "photo.badge.plus")
                                Text("No proof attached")
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(12)
                        }
                    }
                    
                    // 4. Lender Actions (Verify/Reject)
                    if isLender && payment.status == .pending {
                        VStack(spacing: 12) {
                            Text("This payment is waiting for your verification.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 16) {
                                Button(role: .destructive) {
                                    showRejectReasonSheet = true
                                } label: {
                                    Text("Reject")
                                        .lsDestructiveButton()
                                }
                                
                                Button {
                                    handleApprove()
                                } label: {
                                    Text("Confirm Received")
                                        .lsPrimaryButton(background: .green)
                                }
                            }
                            .disabled(isProcessing)
                        }
                        .padding(.top)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Transaction Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showRejectReasonSheet) {
                NavigationStack {
                    Form {
                        Section("Reason") {
                            TextField("Why are you rejecting this payment?", text: $rejectionReason, axis: .vertical)
                                .lineLimit(3...6)
                        }
                        Section {
                            Button {
                                submitReject()
                            } label: {
                                Text("Reject Payment")
                                    .lsDestructiveButton()
                            }
                            .buttonStyle(.plain)
                            .disabled(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .navigationTitle("Reject Payment")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showRejectReasonSheet = false
                                rejectionReason = ""
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
    
    var statusBadge: some View {
        Text(payment.status.title)
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(payment.status == .approved ? Color.green.opacity(0.1) :
                        payment.status == .rejected ? Color.red.opacity(0.1) :
                        Color.orange.opacity(0.1))
            .foregroundStyle(payment.status == .approved ? .green :
                             payment.status == .rejected ? .red :
                             .orange)
            .clipShape(Capsule())
    }
    
    func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
    
    func handleApprove() {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            do {
                try await loanManager.updatePaymentStatus(
                    payment: payment,
                    newStatus: .approved,
                    loan: loan
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }

    func submitReject() {
        guard !isProcessing else { return }
        let trimmedReason = rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            errorMessage = "Please provide a rejection reason."
            return
        }

        isProcessing = true
        Task {
            do {
                var paymentWithReason = payment
                paymentWithReason.rejection_reason = trimmedReason
                try await loanManager.updatePaymentStatus(
                    payment: paymentWithReason,
                    newStatus: .rejected,
                    loan: loan
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }
}
