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
        VStack(spacing: 20) {
            Text("Sign In")
                .font(.largeTitle)
                .bold()
            
            TextField("Email", text: $viewModel.email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .lsAuthInput()
                .disabled(viewModel.isLoading)
            
            SecureField("Password", text: $viewModel.password)
                .lsAuthInput()
                .disabled(viewModel.isLoading)
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .transition(.opacity)
            }
            
            Button {
                Task {
                    await viewModel.signIn()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                    .tint(.white)
                    .lsPrimaryButton()
                } else {
                    Text("Sign In")
                        .lsPrimaryButton()
                }
            }
            .disabled(viewModel.isLoading || !viewModel.isValid)
            .animation(.easeInOut, value: viewModel.isLoading)
            
            Spacer()
        }
        .padding()
        .sensoryFeedback(.error, trigger: viewModel.errorMessage) { _, newValue in newValue != nil }
    }
}

#Preview {
    LoginView()
}
