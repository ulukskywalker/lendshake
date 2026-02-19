import SwiftUI

struct LoanConstructionAmountStepView: View {
    @Binding var principalAmountValue: Double

    var body: some View {
        ZStack {
            // 1. Centered Content
            CircularAmountDialView(
                value: $principalAmountValue,
                maxValue: 10000,
                tintColor: .blue
            )
            
            // 2. Top-aligned Header
            VStack {
                VStack(spacing: 8) {
                    Text("Loan Amount")
                        .font(.title2)
                        .bold()
                    Text("How much are you lending?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
