import SwiftUI

struct LoanConstructionCostsStepView: View {
    @Binding var interestRate: String
    @Binding var interestSliderValue: Double
    @Binding var lateFeePolicy: String
    @Binding var lateFeeSliderValue: Double
    
    @State private var hasLateFee: Bool = false
    
    let onInterestTextChange: (String) -> Void
    let onInterestSliderChange: (Double) -> Void
    let onLateFeeSliderChange: (Double) -> Void
    
    private var usuryResult: LoanValidationResult {
        LoanValidation.validateUsury(rate: interestSliderValue)
    }
    
    private var afrResult: LoanValidationResult {
        LoanValidation.validateAFR(rate: interestSliderValue)
    }
    
    private var rateColor: Color {
        if interestSliderValue == 0 {
            return .green
        } else if case .invalid = usuryResult {
            return .red
        } else if case .warning = afrResult {
            return .orange
        } else {
            return .blue
        }
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Rate")
                        Spacer()
                        Text(interestSliderValue == 0 ? "0% (Family)" : "\(interestSliderValue, specifier: "%.1f")%")
                            .foregroundStyle(rateColor)
                            .bold()
                    }
                    
                    Slider(value: $interestSliderValue, in: 0...15, step: 0.5)
                        .tint(rateColor)
                        .onChange(of: interestSliderValue) { _, newValue in
                            onInterestSliderChange(newValue)
                        }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Interest")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if interestSliderValue == 0 {
                        Text("0% interest avoids tax complications for loans under $10k between friends/family.")
                    } else if case .invalid(let msg) = usuryResult {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else if case .warning(let msg) = afrResult {
                        Label(msg, systemImage: "info.circle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Maximum rate is capped to comply with most state usury laws.")
                    }
                }
            }
            
            Section {
                Toggle("Add Late Fee", isOn: $hasLateFee.animation())
                    .onChange(of: hasLateFee) { _, enabled in
                        if !enabled {
                            lateFeePolicy = "0"
                            lateFeeSliderValue = 0
                        }
                    }
                
                if hasLateFee {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Fee Amount")
                            Spacer()
                            Text(lateFeeSliderValue.formatted(.currency(code: "USD")))
                                .bold()
                        }
                        
                        Slider(value: $lateFeeSliderValue, in: 0...50, step: 5)
                            .tint(.red)
                            .onChange(of: lateFeeSliderValue) { _, newValue in
                                onLateFeeSliderChange(newValue)
                            }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Late Fees")
            } footer: {
                if hasLateFee {
                    Text("Applies after a 5-day grace period.")
                }
            }
        }
        .onAppear {
            if let fee = Double(lateFeePolicy), fee > 0 {
                hasLateFee = true
            }
        }
    }
}
