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
    @State private var errorMessage: String?
    @State private var firstNameError: String?
    @State private var lastNameError: String?
    @State private var phoneError: String?
    @State private var showSaved = false

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
                if let firstNameError {
                    Text(firstNameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextField("Last Name", text: $lastName)
                    .textInputAutocapitalization(.words)
                    .disabled(!isEditing || isSaving)
                    .opacity(isEditing ? 1 : 0.65)
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
                if let phoneError {
                    Text(phoneError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let email = authManager.currentUserEmail {
                    LabeledContent("Email", value: email)
                }
            }

            if let updated = authManager.currentUserProfile?.updated_at {
                Section("Profile") {
                    LabeledContent("Last Updated", value: updated.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if isEditing {
                Section {
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSaving)
                }
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
                        errorMessage = nil
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
        .alert("Saved", isPresented: $showSaved) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your profile was updated.")
        }
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

    private func saveProfile() async {
        errorMessage = nil
        firstNameError = nil
        lastNameError = nil
        phoneError = nil

        let normalizedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        var hasFieldError = false
        if normalizedFirst.isEmpty {
            firstNameError = "First name is required."
            hasFieldError = true
        }
        if normalizedLast.isEmpty {
            lastNameError = "Last name is required."
            hasFieldError = true
        }
        if hasFieldError {
            errorMessage = "Please fix highlighted fields."
            return
        }

        if !normalizedPhone.isEmpty {
            let digits = normalizedPhone.filter(\.isNumber).count
            guard digits >= 10 else {
                phoneError = "Phone must have at least 10 digits."
                errorMessage = "Please fix highlighted fields."
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
            showSaved = true
        } catch {
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environment(AuthManager())
    }
}
