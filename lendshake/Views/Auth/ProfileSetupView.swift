//
//  ProfileSetupView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct ProfileSetupView: View {
    @Environment(AuthManager.self) var authManager
    
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var phoneNumber: String = ""
    @State private var selectedState: String = "IL"
    @State private var isLoading: Bool = false
    @State private var firstNameError: String?
    @State private var lastNameError: String?
    @State private var phoneError: String?
    @State private var successToast: String?
    @State private var errorToast: String?
    
    let usStates = ["AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Legal Identity")) {
                    Text("Formal contracts require your full legal name and residence state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Legal First Name", text: $firstName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: firstName) { _, _ in
                            firstNameError = nil
                        }
                    if let firstNameError {
                        Text(firstNameError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    TextField("Legal Last Name", text: $lastName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: lastName) { _, _ in
                            lastNameError = nil
                        }
                    if let lastNameError {
                        Text(lastNameError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                Section(header: Text("Contact Info")) {
                    TextField("Mobile Phone", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .onChange(of: phoneNumber) { _, _ in
                            phoneError = nil
                        }
                    if let phoneError {
                        Text(phoneError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    Picker("State of Residence", selection: $selectedState) {
                        ForEach(usStates, id: \.self) { state in
                            Text(state).tag(state)
                        }
                    }
                }

                Section {
                    Button {
                        Task {
                            await saveProfile()
                        }
                    } label: {
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                            }
                            .lsPrimaryButton()
                        } else {
                            Text("Complete Setup")
                                .lsPrimaryButton()
                        }
                    }
                    .disabled(isLoading)
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Your Profile")
            .interactiveDismissDisabled()
            .lsToast(message: $successToast, style: .success)
            .lsToast(message: $errorToast, style: .error)
        }
    }
    
    private func clearFieldErrors() {
        firstNameError = nil
        lastNameError = nil
        phoneError = nil
    }

    private func saveProfile() async {
        clearFieldErrors()
        isLoading = true

        let normalizedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        var hasFieldError = false
        if normalizedFirst.isEmpty {
            firstNameError = "First name is required."
            hasFieldError = true
        } else if normalizedFirst.count < 2 {
            firstNameError = "First name must be at least 2 characters."
            hasFieldError = true
        }

        if normalizedLast.isEmpty {
            lastNameError = "Last name is required."
            hasFieldError = true
        } else if normalizedLast.count < 2 {
            lastNameError = "Last name must be at least 2 characters."
            hasFieldError = true
        }

        let phoneDigits = normalizedPhone.filter(\.isNumber).count
        if normalizedPhone.isEmpty {
            phoneError = "Phone number is required."
            hasFieldError = true
        } else if phoneDigits < 10 || phoneDigits > 15 {
            phoneError = "Phone must include 10-15 digits."
            hasFieldError = true
        }

        if hasFieldError {
            errorToast = "Please fix highlighted fields."
            isLoading = false
            return
        }
        
        do {
            try await authManager.createProfile(
                firstName: normalizedFirst,
                lastName: normalizedLast,
                state: selectedState,
                phoneNumber: normalizedPhone
            )
            successToast = "Profile saved."
        } catch {
            errorToast = "Failed to save profile: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

#Preview {
    ProfileSetupView()
        .environment(AuthManager())
}
