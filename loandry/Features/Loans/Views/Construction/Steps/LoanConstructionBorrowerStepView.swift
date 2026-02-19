import SwiftUI

struct LoanConstructionBorrowerStepView: View {
    @Binding var borrowerName: String
    @Binding var borrowerEmail: String

    var body: some View {
        VStack(spacing: 24) {
            Text("Who should receive this agreement?")
                .font(.title2)
                .bold()
                .padding(.top)

            Form {
                Section {
                    TextField("Legal Name", text: $borrowerName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Email (Required)", text: $borrowerEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Borrower will complete their own legal info before signing.")
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}
