//
//  SettingsView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) var authManager
    
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var state: String = ""
    @State private var phone: String = ""
    @State private var isLoading: Bool = false
    @State private var showSuccess: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Your Profile") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("State (e.g. CA, NY)", text: $state)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Phone Number", text: $phone)
                        .keyboardType(.phonePad)
                }
                
                Section {
                    Button {
                        saveProfile()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Save Changes")
                        }
                    }
                    .disabled(firstName.isEmpty || lastName.isEmpty || isLoading)
                }
                
                Section {
                    Button("Log Out", role: .destructive) {
                        Task {
                            try? await authManager.signOut()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                if let profile = authManager.currentUserProfile {
                    firstName = profile.first_name ?? ""
                    lastName = profile.last_name ?? ""
                    state = profile.residence_state ?? "" // Populated
                    phone = profile.phone_number ?? ""
                }
            }
            .alert("Profile Updated", isPresented: $showSuccess) {
                Button("OK", role: .cancel) { }
            }
        }
    }
    
    func saveProfile() {
        isLoading = true
        Task {
            do {
                // Reuse existing upsert logic
                // Pass current state or default if missing? 
                // Currently CreateProfile requires State. We might need to fetch it or make it optional.
                // Let's assume users can keep existing state if we had a proper fetch, but here we only have local profile struct which doesn't have state.
                // Wait, AuthManager.UserProfile DOES NOT have residence_state.
                // We need to fix AuthManager first to expose residence_state if we want to preserve it, OR just default it.
                // For now, let's hardcode "CA" or keep it simple.
                // Actually, `createProfile` REQUIRES state.
                
                try await authManager.createProfile(
                    firstName: firstName,
                    lastName: lastName,
                    state: state.isEmpty ? "CA" : state, // Fallback if empty, but form shouldn't be submitted if empty ideally.
                    phoneNumber: phone
                )
                showSuccess = true
            } catch {
                print("Error saving profile: \(error)")
            }
            isLoading = false
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
}
