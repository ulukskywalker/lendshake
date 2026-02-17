import SwiftUI

struct LoanConstructionTermsStepView: View {
    @Binding var repaymentSchedule: RepaymentSchedule
    @Binding var interestRate: String
    @Binding var interestSliderValue: Double
    @Binding var maturityDate: Date
    @Binding var firstPaymentDate: Date
    @Binding var showDatePickerPopover: Bool
    @Binding var lateFeePolicy: String
    @Binding var lateFeeSliderValue: Double
    
    @State private var hasLateFee: Bool = false
    @State private var showFirstPaymentPicker: Bool = false
    
    let onScheduleChange: () -> Void
    let onInterestTextChange: (String) -> Void
    let onInterestSliderChange: (Double) -> Void
    let onLateFeeSliderChange: (Double) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Agreement Terms")
                        .font(.title2)
                        .bold()
                    Text("Define the schedule and costs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)

                // 1. Frequency
                termSection(
                    icon: "repeat",
                    title: "Repayment Frequency",
                    subtitle: "How often will they pay you back?"
                ) {
                    Picker("Frequency", selection: $repaymentSchedule) {
                        ForEach(RepaymentSchedule.allCases) { schedule in
                            Text(schedule.rawValue).tag(schedule)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: repaymentSchedule) { _, _ in
                        onScheduleChange()
                    }
                }

                // 2. Interest
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

                // 3. First Payment Date
                termSection(
                    icon: "calendar.badge.plus",
                    title: "First Payment Date",
                    subtitle: "When is the first installment due?"
                ) {
                    Button {
                        showFirstPaymentPicker = true
                    } label: {
                        HStack {
                            Text(firstPaymentDate.formatted(date: .long, time: .omitted))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(12)
                    }
                    .popover(isPresented: $showFirstPaymentPicker) {
                        DatePicker("First Payment", selection: $firstPaymentDate, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .onChange(of: firstPaymentDate) { _, _ in
                                showFirstPaymentPicker = false
                            }
                            .padding()
                            .frame(minWidth: 320)
                    }
                }

                // 4. Final Due Date
                termSection(
                    icon: "calendar",
                    title: "Final Due Date",
                    subtitle: "When should the total be paid off?"
                ) {
                    Button {
                        showDatePickerPopover = true
                    } label: {
                        HStack {
                            Text(maturityDate.formatted(date: .long, time: .omitted))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(12)
                    }
                    .popover(isPresented: $showDatePickerPopover) {
                        DatePicker("Final Due Date", selection: $maturityDate, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .onChange(of: maturityDate) { _, _ in
                                showDatePickerPopover = false
                            }
                            .padding()
                            .frame(minWidth: 320)
                    }
                }

                // 5. Late Fee
                VStack(spacing: 16) {
                    Toggle(isOn: $hasLateFee.animation()) {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundStyle(hasLateFee ? .red : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Late Fee")
                                    .font(.headline)
                                Text("Protection against missed dates")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.cardBackground)
                    .cornerRadius(16)
                    .lsCardContainer()
                    .onChange(of: hasLateFee) { _, enabled in
                        if !enabled {
                            lateFeePolicy = "0"
                            lateFeeSliderValue = 0
                        }
                    }
                    
                    if hasLateFee {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Fee per installment")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(lateFeeSliderValue.formatted(.currency(code: "USD")))
                                    .font(.headline)
                                    .bold()
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
                        .padding()
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                
                LoanConstructionTipCardView(
                    title: "Auto-Drafted Agreement",
                    message: "These choices will be embedded into a legally binding promissory note."
                )
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
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
