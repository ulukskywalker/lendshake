//
//  LoanConstructionView.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

struct LoanConstructionView: View {
    @Environment(LoanManager.self) var loanManager
    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) var dismiss

    var onLoanCreated: ((Loan) -> Void)?

    @State private var createdLoan: Loan?
    @State private var showDatePickerPopover: Bool = false
    @State private var didPrefillLenderProfile = false
    
    // Step State
    @State private var currentStep: LoanConstructionWizardStep = .amount
    
    // Form Data
    @State private var principalAmountValue: Double = 0.0
    @State private var principalAmount: String = ""
    @State private var interestSliderValue: Double = 0.0
    @State private var repaymentSchedule: RepaymentSchedule = .monthly
    @State private var maturityDate: Date = Date().addingTimeInterval(86400 * 30 * 6)
    @State private var firstPaymentDate: Date = Date().addingTimeInterval(86400 * 30) // Default to 1 month from now
    @State private var lenderFirstName: String = ""
    @State private var lenderLastName: String = ""
    @State private var lenderAddressLine1: String = ""
    @State private var lenderAddressLine2: String = ""
    @State private var lenderPhone: String = ""
    @State private var lenderState: String = "IL"
    @State private var lenderCountry: String = ProfileReferenceData.defaultCountry
    @State private var lenderPostalCode: String = ""
    @State private var saveLenderInfoForFuture: Bool = true
    @State private var borrowerEmail: String = ""
    @State private var lateFeeSliderValue: Double = 0

    @State private var amountShakeTrigger: CGFloat = 0
    @State private var errorMessage: String?

    // Local transient string state for text field inputs to prevent jumpy sliders
    @State private var interestRateInput: String = "0.0"
    @State private var lateFeeInput: String = "0"

    private let maxPrincipalAmount: Double = 10_000
    private let maxPrincipalMessage: String = "Only $10,000 is allowed."
    private let maxInterestRate: Double = 15

    var body: some View {
        VStack(spacing: 0) {
            stepHeader()

            ZStack {
                switch currentStep {
                case .amount:
                    LoanConstructionAmountStepView(
                        principalAmountValue: $principalAmountValue
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .terms:
                    LoanConstructionTermsStepView(
                        repaymentSchedule: $repaymentSchedule,
                        interestRate: $interestRateInput,
                        interestSliderValue: $interestSliderValue,
                        maturityDate: $maturityDate,
                        firstPaymentDate: $firstPaymentDate,
                        showDatePickerPopover: $showDatePickerPopover,
                        lateFeePolicy: $lateFeeInput,
                        lateFeeSliderValue: $lateFeeSliderValue,
                        onScheduleChange: handleRepaymentScheduleChange,
                        onInterestTextChange: sanitizeInterestValue,
                        onInterestSliderChange: handleInterestSliderChange,
                        onLateFeeSliderChange: handleLateFeeSliderChange
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .lender:
                    LoanConstructionLenderStepView(
                        lenderFirstName: $lenderFirstName,
                        lenderLastName: $lenderLastName,
                        lenderAddressLine1: $lenderAddressLine1,
                        lenderAddressLine2: $lenderAddressLine2,
                        lenderPhone: $lenderPhone,
                        lenderState: $lenderState,
                        lenderCountry: $lenderCountry,
                        lenderPostalCode: $lenderPostalCode,
                        saveLenderInfoForFuture: $saveLenderInfoForFuture,
                        usStates: ProfileReferenceData.usStates
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .borrower:
                    LoanConstructionBorrowerStepView(
                        borrowerEmail: $borrowerEmail
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .review:
                    LoanConstructionReviewStepView(
                        principalAmount: principalAmount,
                        interestRate: String(format: "%.1f", interestSliderValue),
                        repaymentSchedule: repaymentSchedule,
                        maturityDate: maturityDate,
                        firstPaymentDate: firstPaymentDate,
                        lateFeePolicy: String(format: "%.0f", lateFeeSliderValue),
                        lenderName: "\(lenderFirstName) \(lenderLastName)".trimmingCharacters(in: .whitespaces),
                        borrowerEmail: borrowerEmail
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomNav()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(currentStep.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
        .onAppear {
            prefillLenderFromProfileIfNeeded()
        }
        .onChange(of: authManager.currentUserProfile?.updated_at) { _, _ in
            prefillLenderFromProfileIfNeeded()
        }
        .onChange(of: principalAmountValue) { _, newValue in
            principalAmount = String(format: "%.2f", newValue)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .overlay(alignment: .top) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.cornerRadius(8))
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { errorMessage = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func stepHeader() -> some View {
        HStack(spacing: 4) {
            ForEach(LoanConstructionWizardStep.allCases, id: \.self) { step in
                Rectangle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.blue : Color.gray.opacity(0.2))
                    .frame(height: 4)
                    .cornerRadius(2)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func bottomNav() -> some View {
        HStack {
            if currentStep != .amount {
                Button {
                    withAnimation {
                        let prev = currentStep.rawValue - 1
                        if let s = LoanConstructionWizardStep(rawValue: prev) { currentStep = s }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
            } else {
                Spacer().frame(width: 50)
            }

            Spacer()

            Button {
                handleNext()
            } label: {
                Text(currentStep == .review ? (createdLoan != nil ? "View Loan" : "Create & Send") : "Next")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
                    .frame(width: 160, height: 50)
                    .background(Color.blue)
                    .cornerRadius(25)
                    .shadow(color: Color.blue.opacity(0.3), radius: 5, x: 0, y: 3)
            }
            .disabled(loanManager.isLoading)

            Spacer()
            Spacer().frame(width: 50)
        }
        .padding()
        .background(Color.cardBackground.ignoresSafeArea(edges: .bottom))
    }

    private func handleNext() {
        switch currentStep {
        case .amount:
            guard validateAmountStep() else { return }
            withAnimation { currentStep = .terms }

        case .terms:
            guard validateTermsStep() else { return }
            withAnimation { currentStep = .lender }

        case .lender:
            guard validateLenderStep() else { return }
            Task {
                await persistLenderProfileAndAdvance()
            }

        case .borrower:
            guard validateBorrowerStep() else { return }
            #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
            withAnimation { currentStep = .review }

        case .review:
            Task {
                await createLoan()
            }
        }
    }

    private func persistLenderProfileAndAdvance() async {
        guard saveLenderInfoForFuture else {
            withAnimation { currentStep = .borrower }
            return
        }

        do {
            try await authManager.createProfile(
                firstName: lenderFirstName,
                lastName: lenderLastName,
                addressLine1: lenderAddressLine1,
                addressLine2: lenderAddressLine2.isEmpty ? nil : lenderAddressLine2,
                state: lenderState,
                country: lenderCountry,
                postalCode: lenderPostalCode,
                phoneNumber: lenderPhone
            )
            withAnimation { currentStep = .borrower }
        } catch {
            errorMessage = "Failed to save your profile info: \(error.localizedDescription)"
        }
    }

    private func createLoan() async {
        if createdLoan != nil {
            dismiss()
            return
        }

        guard validateAmountStep(),
              validateTermsStep(),
              validateLenderStep(),
              validateBorrowerStep() else { return }
        guard let principal = Double(principalAmount) else { return }
        let interest = interestSliderValue
        do {
            // 1. Create the loan with .draft status
            let newLoan = try await loanManager.createDraftLoan(
                principal: principal,
                interest: interest,
                schedule: repaymentSchedule.rawValue,
                lateFee: String(format: "%.0f", lateFeeSliderValue),
                maturity: maturityDate,
                firstPaymentDate: firstPaymentDate,
                borrowerName: nil,
                borrowerEmail: borrowerEmail,
                borrowerPhone: nil
            )
            
            // 2. Lender immediately signs it, transitioning status to .sent
            try await loanManager.signLoan(loan: newLoan)

            createdLoan = newLoan
            onLoanCreated?(newLoan)
            dismiss()

        } catch {
            errorMessage = "Failed to create & send: \(error.localizedDescription)"
        }
    }

    private func prefillLenderFromProfileIfNeeded() {
        guard !didPrefillLenderProfile else { return }
        guard let profile = authManager.currentUserProfile else { return }

        if let first = profile.first_name?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            lenderFirstName = first
        }
        if let last = profile.last_name?.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty {
            lenderLastName = last
        }
        if let addressLine1 = profile.address_line_1?.trimmingCharacters(in: .whitespacesAndNewlines), !addressLine1.isEmpty {
            lenderAddressLine1 = addressLine1
        }
        if let addressLine2 = profile.address_line_2?.trimmingCharacters(in: .whitespacesAndNewlines) {
            lenderAddressLine2 = addressLine2
        }
        if let phone = profile.phone_number?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            lenderPhone = phone
        }
        if let state = profile.residence_state?.trimmingCharacters(in: .whitespacesAndNewlines), state.count == 2 {
            lenderState = state.uppercased()
        }
        if let country = profile.country?.trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
            lenderCountry = country
        }
        if let postalCode = profile.postal_code?.trimmingCharacters(in: .whitespacesAndNewlines), !postalCode.isEmpty {
            lenderPostalCode = postalCode
        }
        didPrefillLenderProfile = true
    }
    
    // MARK: - Validation
    
    private func validateAmountStep() -> Bool {
        let cleaned = principalAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Double(cleaned), amount > 0 else {
            errorMessage = "Enter a principal amount greater than 0."
            return false
        }
        guard amount <= maxPrincipalAmount else {
            errorMessage = "Principal cannot be more than $10,000."
            return false
        }
        return true
    }

    private func validateTermsStep() -> Bool {
        guard interestSliderValue >= 0 else {
            errorMessage = "Interest rate must be 0 or higher."
            return false
        }
        guard interestSliderValue <= maxInterestRate else {
            errorMessage = "Interest rate cannot exceed 15%."
            return false
        }

        guard lateFeeSliderValue >= 0 else {
            errorMessage = "Late fee must be 0 or higher."
            return false
        }

        guard maturityDate >= Calendar.current.startOfDay(for: Date()) else {
            errorMessage = "Final due date cannot be in the past."
            return false
        }

        return true
    }

    private func validateBorrowerStep() -> Bool {
        let email = borrowerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let emailPattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailIsValid = NSPredicate(format: "SELF MATCHES %@", emailPattern).evaluate(with: email)
        guard emailIsValid else {
            errorMessage = "Enter a valid borrower email."
            return false
        }
        borrowerEmail = email
        return true
    }

    private func validateLenderStep() -> Bool {
        let first = lenderFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lenderLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressLine1 = lenderAddressLine1.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressLine2 = lenderAddressLine2.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = lenderPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = lenderState.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = lenderCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        let postalCode = lenderPostalCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if ProfileValidation.validateFirstName(first) != nil || ProfileValidation.validateLastName(last) != nil {
            errorMessage = "Your first and last name are required."
            return false
        }
        if ProfileValidation.validateAddressLine1(addressLine1) != nil {
            errorMessage = "Enter Address Line 1."
            return false
        }
        if let phoneError = ProfileValidation.validatePhone(phone, required: true) {
            errorMessage = phoneError
            return false
        }
        if let stateError = ProfileValidation.validateState(state) {
            errorMessage = stateError
            return false
        }
        if let countryError = ProfileValidation.validateCountry(country) {
            errorMessage = countryError
            return false
        }
        if let postalError = ProfileValidation.validatePostalCode(postalCode) {
            errorMessage = postalError
            return false
        }

        lenderFirstName = first
        lenderLastName = last
        lenderAddressLine1 = addressLine1
        lenderAddressLine2 = addressLine2
        lenderPhone = phone
        lenderState = state.uppercased()
        lenderCountry = country
        lenderPostalCode = postalCode
        return true
    }
    
    // MARK: - Handlers
    
    private func sanitizeInterestValue(_ newValue: String) {
        let result = sanitizeInterestInput(newValue)
        interestRateInput = result.value
        interestSliderValue = result.sliderValue
        if result.didRejectForLimit {
            errorMessage = "Interest rate cannot exceed 15%."
        }
    }

    private func handleInterestSliderChange(_ newValue: Double) {
        interestRateInput = String(format: "%.1f", newValue)
        HapticUtility.selection()
    }

    private func handleLateFeeSliderChange(_ newValue: Double) {
        lateFeeInput = String(format: "%.0f", newValue)
        HapticUtility.selection()
    }

    private func handleRepaymentScheduleChange() {
        withAnimation {
            interestSliderValue = 0
            interestRateInput = "0.0"
        }
    }
    
    private func sanitizeInterestInput(_ value: String) -> (value: String, sliderValue: Double, didRejectForLimit: Bool) {
        let filtered = value.filter { $0.isNumber || $0 == "." }
        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)

        let normalized: String
        if parts.count <= 1 {
            normalized = filtered
        } else {
            normalized = "\(parts[0]).\(parts[1].prefix(1))"
        }

        guard let parsed = Double(normalized) else {
            return (normalized, 0, false)
        }

        if parsed > maxInterestRate {
            return (String(format: "%.1f", maxInterestRate), maxInterestRate, true)
        }

        return (String(format: "%.1f", parsed), parsed, false)
    }
}

#Preview {
    NavigationStack {
        LoanConstructionView()
            .environment(LoanManager())
            .environment(AuthManager())
    }
}
