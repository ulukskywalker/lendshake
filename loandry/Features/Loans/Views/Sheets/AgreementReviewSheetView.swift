//
//  AgreementReviewSheet.swift
//  loandry
//
//  Created by Assistant on 2/16/26.
//

import SwiftUI

struct AgreementReviewSheetView: View {
    @Environment(LoanManager.self) private var loanManager
    @Binding var isPresented: Bool
    let loan: Loan
    let isLender: Bool
    
    @State private var errorMessage: String?
    @State private var isSigning: Bool = false

    private var agreementText: String {
        loan.agreement_text ?? AgreementUtility.generate(for: loan)
    }

    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let pdfURL {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                        Text("Signed Agreement Available")
                            .font(.title2.bold())
                        
                        Link(destination: pdfURL) {
                            Label("Open PDF", systemImage: "arrow.up.right.square")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        
                        ShareLink(item: pdfURL) {
                            Label("Share / Save PDF", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.secondary.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 40)
                } else {
                    Text(agreementText)
                        .padding()
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Legal Agreement")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
                
                if pdfURL == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: agreementText)
                    }
                }
                
                if isLender && loan.status == .draft && loan.lender_signed_at == nil && pdfURL == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await sign() }
                        } label: {
                            if isSigning {
                                ProgressView()
                            } else {
                                Text("Sign & Accept").bold()
                            }
                        }
                        .disabled(isSigning)
                    }
                }
            }
            .task {
                if let path = loan.agreement_url {
                    do {
                        pdfURL = try await loanManager.fetchAgreementURL(path: path)
                    } catch {
                        errorMessage = "Failed to load PDF: \(error.localizedDescription)"
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .padding()
                        .background(.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding()
                }
            }
        }
    }
    
    private func sign() async {
        isSigning = true
        defer { isSigning = false }
        do {
            try await loanManager.signLoan(loan: loan)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
