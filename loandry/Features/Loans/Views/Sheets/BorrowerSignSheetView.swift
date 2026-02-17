//
//  BorrowerSignSheet.swift
//  loandry
//
//  Created by Assistant on 2/16/26.
//

import SwiftUI

struct BorrowerSignSheetView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(LoanManager.self) private var loanManager
    @Binding var isPresented: Bool
    let loan: Loan
    
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var addressLine1: String = ""
    @State private var addressLine2: String = ""
    @State private var phone: String = ""
    @State private var state: String = "IL"
    @State private var country: String = ProfileReferenceData.defaultCountry
    @State private var postalCode: String = ""
    @State private var saveInfo: Bool = true
    @State private var isSigning: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Legal Identity") {
                    TextField("Legal First Name", text: $firstName)
                        .textInputAutocapitalization(.words)
                    TextField("Legal Last Name", text: $lastName)
                        .textInputAutocapitalization(.words)
                    TextField("Address Line 1", text: $addressLine1)
                        .textInputAutocapitalization(.words)
                    TextField("Apt / Suite (Optional)", text: $addressLine2)
                        .textInputAutocapitalization(.words)
                }

                Section("Your Contact Info") {
                    TextField("Mobile Phone", text: $phone)
                        .keyboardType(.phonePad)
                    Picker("State of Residence", selection: $state) {
                        ForEach(ProfileReferenceData.usStates, id: \.self) { state in
                            Text(state).tag(state)
                        }
                    }
                    TextField("Country", text: $country)
                        .textInputAutocapitalization(.words)
                    TextField("Postal Code / Index", text: $postalCode)
                        .textInputAutocapitalization(.characters)
                }
                
                Section {
                    Toggle("Save this info for future use", isOn: $saveInfo)
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Complete & Sign")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await sign() }
                    } label: {
                        if isSigning {
                            ProgressView()
                        } else {
                            Text("Sign & Send Back").bold()
                        }
                    }
                    .disabled(isSigning)
                }
            }
            .onAppear(perform: prefill)
        }
    }
    
    private func prefill() {
        let profile = authManager.currentUserProfile
        firstName = profile?.first_name ?? ""
        lastName = profile?.last_name ?? ""
        addressLine1 = profile?.address_line_1 ?? ""
        addressLine2 = profile?.address_line_2 ?? ""
        phone = profile?.phone_number ?? ""
        state = profile?.residence_state?.uppercased() ?? "IL"
        country = profile?.country ?? ProfileReferenceData.defaultCountry
        postalCode = profile?.postal_code ?? ""
    }
    
    private func sign() async {
        isSigning = true
        defer { isSigning = false }
        
        do {
            if saveInfo {
                try await authManager.createProfile(
                    firstName: firstName,
                    lastName: lastName,
                    addressLine1: addressLine1,
                    addressLine2: addressLine2.isEmpty ? nil : addressLine2,
                    state: state,
                    country: country,
                    postalCode: postalCode,
                    phoneNumber: phone
                )
            }

            try await loanManager.signLoanAsBorrower(
                loan: loan,
                firstName: firstName,
                lastName: lastName,
                addressLine1: addressLine1,
                addressLine2: addressLine2,
                state: state,
                country: country,
                postalCode: postalCode,
                phoneNumber: phone
            )
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
