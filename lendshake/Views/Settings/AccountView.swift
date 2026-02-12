//
//  AccountView.swift
//  lendshake
//
//  Created by Assistant on 2/7/26.
//

import SwiftUI

struct AccountView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var addressLine1 = ""
    @State private var addressLine2 = ""
    @State private var selectedState = "IL"
    @State private var country = ProfileReferenceData.defaultCountry
    @State private var postalCode = ""
    @State private var phoneNumber = ""
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var firstNameError: String?
    @State private var lastNameError: String?
    @State private var addressLine1Error: String?
    @State private var countryError: String?
    @State private var postalCodeError: String?
    @State private var phoneError: String?
    @State private var successToast: String?
    @State private var errorToast: String?

    var body: some View {
        Form {
            Section("Identity") {
                TextField("First Name", text: $firstName)
                    .textInputAutocapitalization(.words)
                    .disabled(!isEditing || isSaving)
                    .opacity(isEditing ? 1 : 0.65)
                    .onChange(of: firstName) { _, _ in
                        firstNameError = nil
                    }
                if let firstNameError {
                    Text(firstNameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextField("Last Name", text: $lastName)
                    .textInputAutocapitalization(.words)
                    .disabled(!isEditing || isSaving)
                    .opacity(isEditing ? 1 : 0.65)
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
                    .disabled(!isEditing || isSaving)
                    .opacity(isEditing ? 1 : 0.65)
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
                    .disabled(!isEditing || isSaving)
                    .opacity(isEditing ? 1 : 0.65)

                Picker("State of Residence", selection: $selectedState) {
                    ForEach(ProfileReferenceData.usStates, id: \.self) { state in
                        Text(state).tag(state)
                    }
                }
                .disabled(!isEditing || isSaving)
                .opacity(isEditing ? 1 : 0.65)
                
                TextField("Country", text: $country)
                    .textInputAutocapitalization(.words)
                    .disabled(!isEditing || isSaving)
                    .opacity(isEditing ? 1 : 0.65)
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
                    .disabled(!isEditing || isSaving)
                    .opacity(isEditing ? 1 : 0.65)
                    .onChange(of: postalCode) { _, _ in
                        postalCodeError = nil
                    }
                if let postalCodeError {
                    Text(postalCodeError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Contact") {
                TextField("Phone Number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .disabled(!isEditing || isSaving)
                    .opacity(isEditing ? 1 : 0.65)
                    .onChange(of: phoneNumber) { _, _ in
                        phoneError = nil
                    }
                if let phoneError {
                    Text(phoneError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let email = authManager.currentUserEmail {
                    LabeledContent("Email", value: email)
                }
            }

            Section("Profile") {
                LabeledContent("Updated At", value: updatedAtLabel)
            }

            if isEditing {
                Section {
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        if isSaving {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                            }
                            .lsPrimaryButton()
                        } else {
                            Text("Save")
                                .lsPrimaryButton()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.lsBackground)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Cancel" : "Edit") {
                    if isEditing {
                        loadProfile()
                        clearFieldErrors()
                    }
                    isEditing.toggle()
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            loadProfile()
        }
        .safeAreaInset(edge: .bottom) {
            if !isEditing {
                Text("Tap Edit to update your profile details.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .lsToast(message: $successToast, style: .success)
        .lsToast(message: $errorToast, style: .error)
    }

    private func loadProfile() {
        guard let profile = authManager.currentUserProfile else { return }
        firstName = profile.first_name ?? ""
        lastName = profile.last_name ?? ""
        selectedState = profile.residence_state?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (profile.residence_state ?? "IL")
            : "IL"
        addressLine1 = profile.address_line_1 ?? ""
        addressLine2 = profile.address_line_2 ?? ""
        country = profile.country ?? ProfileReferenceData.defaultCountry
        postalCode = profile.postal_code ?? ""
        phoneNumber = profile.phone_number ?? ""
    }

    private var updatedAtLabel: String {
        guard let updated = authManager.currentUserProfile?.updated_at else { return "Not available" }
        return updated.formatted(date: .abbreviated, time: .shortened)
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
        hasFieldError = [firstNameError, lastNameError, addressLine1Error, countryError, postalCodeError]
            .contains(where: { $0 != nil })
        if hasFieldError {
            errorToast = "Please fix highlighted fields."
            return
        }

        if let phoneValidation = ProfileValidation.validatePhone(normalizedPhone, required: false) {
            phoneError = phoneValidation
            errorToast = "Please fix highlighted fields."
            return
        }

        isSaving = true
        defer { isSaving = false }

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
            firstName = normalizedFirst
            lastName = normalizedLast
            addressLine1 = normalizedAddressLine1
            addressLine2 = normalizedAddressLine2
            country = normalizedCountry
            postalCode = normalizedPostalCode
            phoneNumber = normalizedPhone
            isEditing = false
            successToast = "Profile updated."
        } catch {
            errorToast = "Failed to save profile: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environment(AuthManager())
    }
}
