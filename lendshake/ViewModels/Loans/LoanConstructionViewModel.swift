//
//  LoanConstructionViewModel.swift
//  lendshake
//
//  Created by Assistant on 2/8/26.
//

import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class LoanConstructionViewModel {
    var currentStep: LoanConstructionWizardStep = .amount

    var principalAmount: String = ""
    var interestRate: String = "0.0"
    var interestSliderValue: Double = 0.0
    var repaymentSchedule: RepaymentSchedule = .monthly
    var maturityDate: Date = Date().addingTimeInterval(86400 * 30 * 6)
    var borrowerFirstName: String = ""
    var borrowerLastName: String = ""
    var borrowerEmail: String = ""
    var borrowerPhone: String = ""
    var lateFeePolicy: String = "0"
    var lateFeeSliderValue: Double = 0

    var amountShakeTrigger: CGFloat = 0
    var errorMessage: String?

    let maxPrincipalAmount: Double = 10_000
    let maxPrincipalMessage: String = "Only $10,000 is allowed."
    let maxInterestRate: Double = 15

    var amountInputFontSize: CGFloat {
        let digitCount = principalAmount.filter(\.isNumber).count
        switch digitCount {
        case 0...4:
            return 72
        case 5...6:
            return 62
        case 7...8:
            return 54
        default:
            return 46
        }
    }

    func validateAmountStep() -> Bool {
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

    func validateTermsStep() -> Bool {
        let cleanedInterest = interestRate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rate = Double(cleanedInterest), rate >= 0 else {
            errorMessage = "Interest rate must be 0 or higher."
            return false
        }
        guard rate <= maxInterestRate else {
            errorMessage = "Interest rate cannot exceed 15%."
            return false
        }

        let cleanedLateFee = lateFeePolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lateFee = Double(cleanedLateFee), lateFee >= 0 else {
            errorMessage = "Late fee must be 0 or higher."
            return false
        }

        guard maturityDate >= Calendar.current.startOfDay(for: Date()) else {
            errorMessage = "Final due date cannot be in the past."
            return false
        }

        return true
    }

    func validateBorrowerStep() -> Bool {
        let first = borrowerFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = borrowerLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = borrowerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !first.isEmpty, !last.isEmpty else {
            errorMessage = "Borrower first and last name are required."
            return false
        }

        let emailPattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailIsValid = NSPredicate(format: "SELF MATCHES %@", emailPattern).evaluate(with: email)
        guard emailIsValid else {
            errorMessage = "Enter a valid borrower email."
            return false
        }

        if !borrowerPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let digitCount = borrowerPhone.filter(\.isNumber).count
            guard digitCount >= 10 else {
                errorMessage = "Borrower phone must have at least 10 digits."
                return false
            }
        }

        borrowerFirstName = first
        borrowerLastName = last
        borrowerEmail = email
        return true
    }

    func sanitizePrincipalInput(_ newValue: String) {
        let result = sanitizeCurrencyInput(newValue)
        principalAmount = result.value
        if result.didRejectForLimit {
            triggerAmountLimitFeedback()
        }
    }

    func sanitizeInterestValue(_ newValue: String) {
        let result = sanitizeInterestInput(newValue)
        interestRate = result.value
        interestSliderValue = result.sliderValue
        if result.didRejectForLimit {
            errorMessage = "Interest rate cannot exceed 15%."
        }
    }

    func handleInterestSliderChange(_ newValue: Double) {
        interestRate = String(format: "%.1f", newValue)
        triggerSelectionHaptic()
    }

    func handleLateFeeSliderChange(_ newValue: Double) {
        lateFeePolicy = String(format: "%.0f", newValue)
        triggerSelectionHaptic()
    }

    func handleRepaymentScheduleChange() {
        withAnimation {
            interestRate = "0.0"
            interestSliderValue = 0
        }
    }

    private func triggerSelectionHaptic() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    private func triggerAmountLimitFeedback() {
        withAnimation(.linear(duration: 0.35)) {
            amountShakeTrigger += 1
        }
        errorMessage = nil
        DispatchQueue.main.async {
            withAnimation {
                self.errorMessage = self.maxPrincipalMessage
            }
        }
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }

    private func sanitizeCurrencyInput(_ value: String) -> (value: String, didRejectForLimit: Bool) {
        let filtered = value.filter { $0.isNumber || $0 == "." }
        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
        let normalized: String

        if parts.count <= 1 {
            normalized = filtered
        } else {
            let integerPart = String(parts[0])
            let decimalPart = String(parts[1].prefix(2))
            normalized = "\(integerPart).\(decimalPart)"
        }

        guard let amount = Double(normalized), amount > maxPrincipalAmount else {
            return (normalized, false)
        }

        return ("10000", true)
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
