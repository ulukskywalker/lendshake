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
    @State private var selectedState = "IL"
    @State private var phoneNumber = ""
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var firstNameError: String?
    @State private var lastNameError: String?
    @State private var phoneError: String?
    @State private var successToast: String?
    @State private var errorToast: String?

    private let usStates = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]

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

                Picker("State of Residence", selection: $selectedState) {
                    ForEach(usStates, id: \.self) { state in
                        Text(state).tag(state)
                    }
                }
                .disabled(!isEditing || isSaving)
                .opacity(isEditing ? 1 : 0.65)
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
        phoneNumber = profile.phone_number ?? ""
    }

    private var updatedAtLabel: String {
        guard let updated = authManager.currentUserProfile?.updated_at else { return "Not available" }
        return updated.formatted(date: .abbreviated, time: .shortened)
    }

    private func clearFieldErrors() {
        firstNameError = nil
        lastNameError = nil
        phoneError = nil
    }

    private func saveProfile() async {
        clearFieldErrors()

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
        if hasFieldError {
            errorToast = "Please fix highlighted fields."
            return
        }

        if !normalizedPhone.isEmpty {
            let digits = normalizedPhone.filter(\.isNumber).count
            guard digits >= 10 && digits <= 15 else {
                phoneError = "Phone must include 10-15 digits."
                errorToast = "Please fix highlighted fields."
                return
            }
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await authManager.createProfile(
                firstName: normalizedFirst,
                lastName: normalizedLast,
                state: selectedState,
                phoneNumber: normalizedPhone
            )
            firstName = normalizedFirst
            lastName = normalizedLast
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
