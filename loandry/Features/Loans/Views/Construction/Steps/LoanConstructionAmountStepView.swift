import SwiftUI

struct LoanConstructionAmountStepView: View {
    @Binding var principalAmountValue: Double
    @State private var isManualInput: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // 1. Centered Content
            // 1. Centered Content
            if isManualInput {
                manualInputView
            } else {
                dialInputView
            }
            
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
        // Dismiss keyboard when tapping outside manual input area
        .onTapGesture {
            if isManualInput {
                isFocused = false
            }
        }
    }

    private var manualInputView: some View {
        VStack(spacing: 20) {
            TextField("Amount", value: $principalAmountValue, format: .currency(code: "USD"))
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                // Use iOS 17 style; fallback logic if needed handled by compiler/SDK check
                .onChange(of: principalAmountValue) { _, newValue in
                    if newValue > 10000 {
                        principalAmountValue = 10000
                    }
                }
            
            Text("Maximum limit: $10,000")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button {
                isManualInput = false
                isFocused = false
            } label: {
                Label("Use Dial", systemImage: "gauge.medium")
                    .font(.headline)
            }
            .padding(.top, 20)
        }
        .onAppear { isFocused = true }
    }
    
    private var dialInputView: some View {
        VStack(spacing: 40) {
            CircularAmountDialView(
                value: $principalAmountValue,
                maxValue: 10000,
                tintColor: .blue
            )
            
            Button {
                isManualInput = true
            } label: {
                Label("Enter Manually", systemImage: "keyboard")
                    .font(.headline)
                    .foregroundStyle(.blue)
            }
        }
    }
}
