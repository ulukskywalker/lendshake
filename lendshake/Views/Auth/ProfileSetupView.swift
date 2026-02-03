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
    @State private var selectedState: String = "CA"
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
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
                    
                    TextField("Legal Last Name", text: $lastName)
                        .textInputAutocapitalization(.words)
                    
                    Picker("State of Residence", selection: $selectedState) {
                        ForEach(usStates, id: \.self) { state in
                            Text(state).tag(state)
                        }
                    }

                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
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
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Complete Setup")
                                .frame(maxWidth: .infinity)
                                .bold()
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(firstName.isEmpty || lastName.isEmpty || isLoading)
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle("Your Profile")
            .interactiveDismissDisabled()
        }
    }
    
    private func saveProfile() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await authManager.createProfile(
                firstName: firstName,
                lastName: lastName,
                state: selectedState,
            )
        } catch {
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

#Preview {
    ProfileSetupView()
        .environment(AuthManager())
}
