
//
//  LoginView.swift
//  loandry
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI

struct LoginView: View {
    @State private var viewModel = LoginViewModel()
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 8) {
                Text("Welcome")
                    .font(.largeTitle)
                    .bold()
                Text("Enter your email to sign in or create an account.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                TextField("Email", text: $viewModel.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .lsAuthInput()
                    .disabled(viewModel.isLoading)
                
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                Button {
                    Task {
                        await viewModel.sendMagicLink()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                            .lsPrimaryButton()
                    } else {
                        Text("Send Magic Link")
                            .lsPrimaryButton()
                    }
                }
                .disabled(viewModel.isLoading || !viewModel.isValid)
            }
            
            Spacer()
            Spacer()
        }
        .padding()
    }
}

#Preview {
    LoginView()
}
