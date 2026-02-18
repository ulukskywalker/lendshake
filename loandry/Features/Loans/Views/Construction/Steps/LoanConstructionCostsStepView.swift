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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Loan Costs")
                        .font(.title2)
                        .bold()
                    Text("Define interest and fees.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)
                
                // 1. Interest
                termSection(
                    icon: "percent",
                    title: "Annual Interest",
                    subtitle: "Set a fair rate for the loan."
                ) {
                    VStack(spacing: 12) {
                        HStack {
                            Text(interestSliderValue == 0 ? "Interest-Free" : "\(interestRate)%")
                                .font(.headline)
                                .foregroundStyle(interestSliderValue == 0 ? .green : .primary)
                            
                            Spacer()
                            
                            if interestSliderValue == 0 {
                                Text("Family & Friends")
                                    .font(.caption)
                                    .bold()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundStyle(.green)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Slider(value: $interestSliderValue, in: 0...15, step: 0.5)
                            .tint(interestSliderValue == 0 ? .green : .blue)
                            .onChange(of: interestSliderValue) { _, newValue in
                                onInterestSliderChange(newValue)
                            }
                    }
                }
                
                // 2. Late Fee
                termSection(
                    icon: "clock.badge.exclamationmark",
                    title: "Late Fee",
                    subtitle: "Protection against missed dates"
                ) {
                    VStack(spacing: 20) {
                        Toggle("Add Late Fee", isOn: $hasLateFee.animation())
                            .font(.headline)
                            .onChange(of: hasLateFee) { _, enabled in
                                if !enabled {
                                    lateFeePolicy = "0"
                                    lateFeeSliderValue = 0
                                }
                            }
                        
                        if hasLateFee {
                            Divider()
                            
                            VStack(spacing: 12) {
                                HStack {
                                    Text(lateFeeSliderValue.formatted(.currency(code: "USD")))
                                        .font(.headline)
                                        .bold()
                                        .foregroundStyle(.red)
                                    
                                    Spacer()
                                    
                                    Text("Fee per installment")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Slider(value: $lateFeeSliderValue, in: 0...50, step: 5)
                                    .tint(.red)
                                    .onChange(of: lateFeeSliderValue) { _, newValue in
                                        onLateFeeSliderChange(newValue)
                                    }
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                    Text("Applies after a 5-day grace period.")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .background(Color.appBackground)
        .onAppear {
            if let fee = Double(lateFeePolicy), fee > 0 {
                hasLateFee = true
            }
        }
    }
    
    @ViewBuilder
    private func termSection<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            
            content()
                .padding()
                .background(Color.cardBackground)
                .cornerRadius(16)
                .lsCardContainer()
        }
        .padding(.horizontal)
    }
}
