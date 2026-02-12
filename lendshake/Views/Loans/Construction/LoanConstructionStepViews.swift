//
//  LoanConstructionStepViews.swift
//  lendshake
//
//  Created by Assistant on 2/8/26.
//

import SwiftUI

struct LoanConstructionAmountStep: View {
    @Binding var principalAmount: String
    let principalFocus: FocusState<Bool>.Binding
    let amountInputFontSize: CGFloat
    let amountShakeTrigger: CGFloat
    let onTapAmount: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Text("How much are you lending?")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$")
                    .font(.system(size: amountInputFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                TextField("0", text: $principalAmount)
                    .font(.system(size: amountInputFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .focused(principalFocus)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(minWidth: 80, maxWidth: 220)
            }
            .modifier(ShakeEffect(animatableData: amountShakeTrigger))
            .contentShape(Rectangle())
            .onTapGesture {
                onTapAmount()
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 320)

            LoanConstructionTipCard(
                title: "Quick tip",
                message: "We keep loans up to $10,000 so agreements stay simple, personal, and easy to manage."
            )
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
            Spacer()
        }
    }
}

struct LoanConstructionTermsStep: View {
    @Binding var repaymentSchedule: RepaymentSchedule
    @Binding var interestRate: String
    @Binding var interestSliderValue: Double
    @Binding var maturityDate: Date
    @Binding var showDatePickerPopover: Bool
    @Binding var lateFeePolicy: String
    @Binding var lateFeeSliderValue: Double
    let onScheduleChange: () -> Void
    let onInterestTextChange: (String) -> Void
    let onInterestSliderChange: (Double) -> Void
    let onLateFeeSliderChange: (Double) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Repayment Plan")
                    .font(.title2)
                    .bold()
                    .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    Text("FREQUENCY")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    HStack(spacing: 12) {
                        ForEach(RepaymentSchedule.allCases) { schedule in
                            Button {
                                repaymentSchedule = schedule
                            } label: {
                                Text(schedule.rawValue)
                                    .font(.subheadline)
                                    .bold()
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(repaymentSchedule == schedule ? Color.lsPrimary : Color.lsCardBackground)
                                    .foregroundStyle(repaymentSchedule == schedule ? .white : .primary)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .onChange(of: repaymentSchedule) { _, _ in
                        onScheduleChange()
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Interest Rate")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        ZStack(alignment: .trailing) {
                            Text("Family & Friends Rate")
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.1))
                                .clipShape(Capsule())
                                .opacity(interestSliderValue == 0 ? 1 : 0)
                                .allowsHitTesting(interestSliderValue == 0)

                            HStack(spacing: 4) {
                                TextField("Example: 5.0", text: $interestRate)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .onChange(of: interestRate) { _, newValue in
                                        onInterestTextChange(newValue)
                                    }
                                Text("%")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .opacity(interestSliderValue == 0 ? 0 : 1)
                            .allowsHitTesting(interestSliderValue != 0)
                        }
                        .frame(height: 32)
                    }

                    VStack {
                        Slider(value: $interestSliderValue, in: 0...15, step: 0.5)
                            .tint(Color.lsPrimary)
                            .onChange(of: interestSliderValue) { _, newValue in
                                onInterestSliderChange(newValue)
                            }

                        HStack {
                            Text("0%")
                            Spacer()
                            Text("15%")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    LoanConstructionTipCard(
                        title: "Quick tip",
                        message: "Rate is capped at 15% to keep terms fair and avoid heavy, bank-style lending."
                    )
                }
                .padding()
                .background(Color.lsCardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)

                HStack {
                    Text("Final Due Date")
                        .font(.body)
                    Spacer()
                    Button {
                        showDatePickerPopover = true
                    } label: {
                        Text(maturityDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(Color.lsPrimary)
                            .bold()
                    }
                }
                .padding()
                .background(Color.lsCardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                .popover(isPresented: $showDatePickerPopover, arrowEdge: .top) {
                    DatePicker("Select Date", selection: $maturityDate, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .onChange(of: maturityDate) { _, _ in
                            showDatePickerPopover = false
                        }
                        .padding()
                        .frame(minWidth: 320)
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("Late Fee Policy")
                            .font(.body)
                        Spacer()
                        TextField("0", text: $lateFeePolicy)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("$")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $lateFeeSliderValue, in: 0...50, step: 5)
                        .tint(Color.lsPrimary)
                        .onChange(of: lateFeeSliderValue) { _, newValue in
                            onLateFeeSliderChange(newValue)
                        }

                    LoanConstructionTipCard(
                        title: "Late fee policy",
                        message: "If set, this fee applies to each missed payment installment, not only the final due date."
                    )
                }
                .padding()
                .background(Color.lsCardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            }
        }
    }
}

struct LoanConstructionBorrowerStep: View {
    @Binding var borrowerEmail: String

    var body: some View {
        VStack(spacing: 24) {
            Text("Who should receive this agreement?")
                .font(.title2)
                .bold()
                .padding(.top)

            Form {
                Section {
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

struct LoanConstructionLenderStep: View {
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

struct LoanConstructionReviewStep: View {
    let principalAmount: String
    let interestRate: String
    let repaymentSchedule: RepaymentSchedule
    let maturityDate: Date
    let lateFeePolicy: String
    let lenderName: String
    let borrowerEmail: String

    var body: some View {
        VStack(spacing: 24) {
            Text("Does this look right?")
                .font(.title2)
                .bold()
                .padding(.top)

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text("PROMISSORY NOTE")
                        .font(.caption)
                        .bold()
                        .tracking(3)
                        .foregroundStyle(.secondary)
                        .padding(.top)

                    Text("\(Double(principalAmount)?.formatted(.currency(code: "USD")) ?? "$0")")
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.lsPrimary)
                        .shadow(color: Color.lsPrimary.opacity(0.3), radius: 8, x: 0, y: 4)

                    if (Double(interestRate) ?? 0) == 0 {
                        Text("FAMILY RATE (0%)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .foregroundStyle(.green)
                            .cornerRadius(20)
                    } else {
                        Text("\(interestRate)% ANNUAL INTEREST")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .cornerRadius(20)
                    }
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
                .background(Color.lsCardBackground)

                Divider()

                VStack(spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("REPAYMENT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(repaymentSchedule.rawValue)
                                .font(.body)
                                .fontWeight(.semibold)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("MATURITY DATE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(maturityDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                    }

                    Divider().opacity(0.5)

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LATE FEE POLICY")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            if let fee = Double(lateFeePolicy), fee > 0 {
                                Text("\(fee.formatted(.currency(code: "USD"))) after grace period")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            } else {
                                Text("No Late Fee")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }

                    Divider().opacity(0.5)

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LENDER")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(lenderName)
                                .font(.body)
                                .fontWeight(.bold)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("BORROWER")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(borrowerEmail)
                                .font(.body)
                                .fontWeight(.bold)
                        }
                    }
                }
                .padding(24)
                .background(Color.gray.opacity(0.04))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 5)
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}

struct LoanConstructionTipCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(Color.lsPrimary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.lsPrimary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
