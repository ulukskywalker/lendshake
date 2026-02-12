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
    @State private var addressLine1: String = ""
    @State private var addressLine2: String = ""
    @State private var phoneNumber: String = ""
    @State private var selectedState: String = "IL"
    @State private var country: String = ProfileReferenceData.defaultCountry
    @State private var postalCode: String = ""
    @State private var isLoading: Bool = false
    @State private var firstNameError: String?
    @State private var lastNameError: String?
    @State private var addressLine1Error: String?
    @State private var countryError: String?
    @State private var postalCodeError: String?
    @State private var phoneError: String?
    @State private var successToast: String?
    @State private var errorToast: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Legal Identity")) {
                    Text("Formal contracts require your legal name and full mailing address.")
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

                    TextField("Address Line 1", text: $addressLine1)
                        .textInputAutocapitalization(.words)
                        .onChange(of: addressLine1) { _, _ in
                            addressLine1Error = nil
                        }
                    if let addressLine1Error {
                        Text(addressLine1Error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    TextField("Apt / Suite (Optional)", text: $addressLine2)
                        .textInputAutocapitalization(.words)
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
                        ForEach(ProfileReferenceData.usStates, id: \.self) { state in
                            Text(state).tag(state)
                        }
                    }
                    TextField("Country", text: $country)
                        .textInputAutocapitalization(.words)
                        .onChange(of: country) { _, _ in
                            countryError = nil
                        }
                    if let countryError {
                        Text(countryError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    TextField("Postal Code / Index", text: $postalCode)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: postalCode) { _, _ in
                            postalCodeError = nil
                        }
                    if let postalCodeError {
                        Text(postalCodeError)
                            .font(.caption)
                            .foregroundStyle(.red)
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
        addressLine1Error = nil
        countryError = nil
        postalCodeError = nil
        phoneError = nil
    }

    private func saveProfile() async {
        clearFieldErrors()
        isLoading = true

        let normalizedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddressLine1 = addressLine1.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddressLine2 = addressLine2.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPostalCode = postalCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        var hasFieldError = false
        firstNameError = ProfileValidation.validateFirstName(normalizedFirst)
        lastNameError = ProfileValidation.validateLastName(normalizedLast)
        addressLine1Error = ProfileValidation.validateAddressLine1(normalizedAddressLine1)
        countryError = ProfileValidation.validateCountry(normalizedCountry)
        postalCodeError = ProfileValidation.validatePostalCode(normalizedPostalCode)
        phoneError = ProfileValidation.validatePhone(normalizedPhone, required: true)

        hasFieldError = [firstNameError, lastNameError, addressLine1Error, countryError, postalCodeError, phoneError]
            .contains(where: { $0 != nil })

        if hasFieldError {
            errorToast = "Please fix highlighted fields."
            isLoading = false
            return
        }
        
        do {
            try await authManager.createProfile(
                firstName: normalizedFirst,
                lastName: normalizedLast,
                addressLine1: normalizedAddressLine1,
                addressLine2: normalizedAddressLine2.isEmpty ? nil : normalizedAddressLine2,
                state: selectedState,
                country: normalizedCountry,
                postalCode: normalizedPostalCode,
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
