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

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(agreementText)
                    .padding()
                    .font(.system(.body, design: .monospaced))
            }
            .navigationTitle("Legal Agreement")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: agreementText)
                }
                
                if isLender && loan.status == .draft && loan.lender_signed_at == nil {
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
