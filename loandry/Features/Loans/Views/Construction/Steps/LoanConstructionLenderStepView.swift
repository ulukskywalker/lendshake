import SwiftUI

struct LoanConstructionLenderStepView: View {
    @Binding var lenderFirstName: String
    @Binding var lenderLastName: String
    @Binding var lenderAddressLine1: String
    @Binding var lenderAddressLine2: String
    @Binding var lenderPhone: String
    @Binding var lenderState: String
    @Binding var lenderCountry: String
    @Binding var lenderPostalCode: String
    @Binding var saveLenderInfoForFuture: Bool

    let usStates: [String]

    var body: some View {
        VStack(spacing: 24) {
            Text("Confirm your legal info")
                .font(.title2)
                .bold()
                .padding(.top)

            Form {
                Section {
                    TextField("Legal First Name", text: $lenderFirstName)
                        .textInputAutocapitalization(.words)
                    TextField("Legal Last Name", text: $lenderLastName)
                        .textInputAutocapitalization(.words)
                    TextField("Mobile Phone", text: $lenderPhone)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Personal Info")
                }

                Section {
                    TextField("Address Line 1", text: $lenderAddressLine1)
                        .textInputAutocapitalization(.words)
                    TextField("Apt / Suite (Optional)", text: $lenderAddressLine2)
                        .textInputAutocapitalization(.words)
                    Picker("State of Residence", selection: $lenderState) {
                        ForEach(usStates, id: \.self) { state in
                            Text(state).tag(state)
                        }
                    }
                    TextField("Country", text: $lenderCountry)
                        .textInputAutocapitalization(.words)
                    TextField("Postal Code / Index", text: $lenderPostalCode)
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Address")
                } footer: {
                    Text("These details are used for your lender signature snapshot.")
                }

                Section {
                    Toggle("Save this info for future loans", isOn: $saveLenderInfoForFuture)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}
