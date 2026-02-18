import SwiftUI

struct LoanConstructionAmountStepView: View {
    @Binding var principalAmountValue: Double

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Text("Loan Amount")
                    .font(.title2)
                    .bold()
                Text("How much are you lending?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)
            
            Spacer()

            CircularAmountDialView(
                value: $principalAmountValue,
                maxValue: 10000,
                tintColor: .blue
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}
