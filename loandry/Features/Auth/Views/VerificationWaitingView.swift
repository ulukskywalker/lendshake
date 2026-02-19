//
//  VerificationWaitingView.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct VerificationWaitingView: View {
    @State private var viewModel = VerificationWaitingViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("📩")
                .font(.system(size: 80))
            
            Text("Check your email")
                .font(.largeTitle)
                .bold()
            
            Text("We've sent a confirmation link to your inbox. Please verify your email to continue.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button {
                Task { await viewModel.resendVerification() }
            } label: {
                if viewModel.isResending {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Resend Link")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .disabled(viewModel.isResending)
            
            Button("Cancel / Back to Sign In") {
                viewModel.cancel()
            }
            .padding(.top, 10)
            
            Spacer().frame(height: 20)
        }
        .padding()
        .sensoryFeedback(.warning, trigger: viewModel.statusMessage) { _, newValue in newValue != nil }

    }
}

#Preview {
    VerificationWaitingView()
}
