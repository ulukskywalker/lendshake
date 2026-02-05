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
                                    handleAction(approve: false)
                                } label: {
                                    Text("Reject")
                                        .bold()
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red.opacity(0.1))
                                        .foregroundStyle(.red)
                                        .cornerRadius(12)
                                }
                                
                                Button {
                                    handleAction(approve: true)
                                } label: {
                                    Text("Confirm Received")
                                        .bold()
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.green)
                                        .foregroundStyle(.white)
                                        .cornerRadius(12)
                                }
                            }
                            .disabled(isProcessing)
                        }
                        .padding(.top)
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
    
    func handleAction(approve: Bool) {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            do {
                try await loanManager.updatePaymentStatus(
                    payment: payment,
                    newStatus: approve ? .approved : .rejected,
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
