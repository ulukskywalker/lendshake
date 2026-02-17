import SwiftUI

struct LoanConstructionAmountStepView: View {
    @Binding var principalAmountValue: Double

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            CircularAmountDialView(
                value: $principalAmountValue,
                maxValue: 10000,
                tintColor: .blue
            )

            LoanConstructionTipCardView(
                title: "Quick tip",
                message: "We keep loans up to $10,000 so agreements stay simple, personal, and easy to manage."
            )
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }
}
