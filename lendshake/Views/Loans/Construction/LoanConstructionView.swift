//
//  LoanConstructionView.swift
//  lendshake
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
    @State private var viewModel = LoanConstructionViewModel()
    @State private var focusTask: Task<Void, Never>?
    @State private var didPrefillLenderProfile = false

    @FocusState private var isPrincipalFieldFocused: Bool

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            stepHeader(vm: vm)

            ZStack {
                switch vm.currentStep {
                case .amount:
                    LoanConstructionAmountStep(
                        principalAmount: Binding(
                            get: { vm.principalAmount },
                            set: { vm.sanitizePrincipalInput($0) }
                        ),
                        principalFocus: $isPrincipalFieldFocused,
                        amountInputFontSize: vm.amountInputFontSize,
                        amountShakeTrigger: vm.amountShakeTrigger,
                        onTapAmount: { isPrincipalFieldFocused = true }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .terms:
                    LoanConstructionTermsStep(
                        repaymentSchedule: $vm.repaymentSchedule,
                        interestRate: $vm.interestRate,
                        interestSliderValue: $vm.interestSliderValue,
                        maturityDate: $vm.maturityDate,
                        showDatePickerPopover: $showDatePickerPopover,
                        lateFeePolicy: $vm.lateFeePolicy,
                        lateFeeSliderValue: $vm.lateFeeSliderValue,
                        onScheduleChange: vm.handleRepaymentScheduleChange,
                        onInterestTextChange: vm.sanitizeInterestValue,
                        onInterestSliderChange: vm.handleInterestSliderChange,
                        onLateFeeSliderChange: vm.handleLateFeeSliderChange
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .lender:
                    LoanConstructionLenderStep(
                        lenderFirstName: $vm.lenderFirstName,
                        lenderLastName: $vm.lenderLastName,
                        lenderAddressLine1: $vm.lenderAddressLine1,
                        lenderAddressLine2: $vm.lenderAddressLine2,
                        lenderPhone: $vm.lenderPhone,
                        lenderState: $vm.lenderState,
                        lenderCountry: $vm.lenderCountry,
                        lenderPostalCode: $vm.lenderPostalCode,
                        saveLenderInfoForFuture: $vm.saveLenderInfoForFuture,
                        usStates: ProfileReferenceData.usStates
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .borrower:
                    LoanConstructionBorrowerStep(
                        borrowerEmail: $vm.borrowerEmail
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .review:
                    LoanConstructionReviewStep(
                        principalAmount: vm.principalAmount,
                        interestRate: vm.interestRate,
                        repaymentSchedule: vm.repaymentSchedule,
                        maturityDate: vm.maturityDate,
                        lateFeePolicy: vm.lateFeePolicy,
                        lenderName: "\(vm.lenderFirstName) \(vm.lenderLastName)".trimmingCharacters(in: .whitespaces),
                        borrowerEmail: vm.borrowerEmail
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.currentStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomNav(vm: vm)
        }
        .background(Color.lsBackground.ignoresSafeArea())
        .navigationTitle(vm.currentStep.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
        .onAppear {
            prefillLenderFromProfileIfNeeded(vm: vm)
            schedulePrincipalAutoFocusIfNeeded()
        }
        .onChange(of: authManager.currentUserProfile?.updated_at) { _, _ in
            prefillLenderFromProfileIfNeeded(vm: vm)
        }
        .onChange(of: vm.currentStep) { _, newStep in
            if newStep == .amount {
                schedulePrincipalAutoFocusIfNeeded()
            } else {
                focusTask?.cancel()
                isPrincipalFieldFocused = false
            }
        }
        .onDisappear {
            focusTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .overlay(alignment: .top) {
            if let error = vm.errorMessage {
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
                            withAnimation { vm.errorMessage = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func stepHeader(vm: LoanConstructionViewModel) -> some View {
        HStack(spacing: 4) {
            ForEach(LoanConstructionWizardStep.allCases, id: \.self) { step in
                Rectangle()
                    .fill(step.rawValue <= vm.currentStep.rawValue ? Color.lsPrimary : Color.gray.opacity(0.2))
                    .frame(height: 4)
                    .cornerRadius(2)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func bottomNav(vm: LoanConstructionViewModel) -> some View {
        HStack {
            if vm.currentStep != .amount {
                Button {
                    withAnimation {
                        let prev = vm.currentStep.rawValue - 1
                        if let s = LoanConstructionWizardStep(rawValue: prev) { vm.currentStep = s }
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
                handleNext(vm: vm)
            } label: {
                Text(vm.currentStep == .review ? (createdLoan != nil ? "View Draft" : "Create Draft") : "Next")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
                    .frame(width: 160, height: 50)
                    .background(Color.lsPrimary)
                    .cornerRadius(25)
                    .shadow(color: Color.lsPrimary.opacity(0.3), radius: 5, x: 0, y: 3)
            }
            .disabled(loanManager.isLoading)

            Spacer()
            Spacer().frame(width: 50)
        }
        .padding()
        .background(Color.lsCardBackground.ignoresSafeArea(edges: .bottom))
    }

    private func handleNext(vm: LoanConstructionViewModel) {
        switch vm.currentStep {
        case .amount:
            guard vm.validateAmountStep() else { return }
            withAnimation { vm.currentStep = .terms }

        case .terms:
            guard vm.validateTermsStep() else { return }
            withAnimation { vm.currentStep = .lender }

        case .lender:
            guard vm.validateLenderStep() else { return }
            Task {
                await persistLenderProfileAndAdvance(vm: vm)
            }

        case .borrower:
            guard vm.validateBorrowerStep() else { return }
            #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
            withAnimation { vm.currentStep = .review }

        case .review:
            Task {
                await createLoan(vm: vm)
            }
        }
    }

    private func persistLenderProfileAndAdvance(vm: LoanConstructionViewModel) async {
        guard vm.saveLenderInfoForFuture else {
            withAnimation { vm.currentStep = .borrower }
            return
        }

        do {
            try await authManager.createProfile(
                firstName: vm.lenderFirstName,
                lastName: vm.lenderLastName,
                addressLine1: vm.lenderAddressLine1,
                addressLine2: vm.lenderAddressLine2.isEmpty ? nil : vm.lenderAddressLine2,
                state: vm.lenderState,
                country: vm.lenderCountry,
                postalCode: vm.lenderPostalCode,
                phoneNumber: vm.lenderPhone
            )
            withAnimation { vm.currentStep = .borrower }
        } catch {
            vm.errorMessage = "Failed to save your profile info: \(error.localizedDescription)"
        }
    }

    private func createLoan(vm: LoanConstructionViewModel) async {
        if createdLoan != nil {
            dismiss()
            return
        }

        guard vm.validateAmountStep(),
              vm.validateTermsStep(),
              vm.validateLenderStep(),
              vm.validateBorrowerStep() else { return }
        guard let principal = Double(vm.principalAmount) else { return }
        let interest = Double(vm.interestRate) ?? 0.0
        do {
            let newLoan = try await loanManager.createDraftLoan(
                principal: principal,
                interest: interest,
                schedule: vm.repaymentSchedule.rawValue,
                lateFee: vm.lateFeePolicy,
                maturity: vm.maturityDate,
                borrowerName: nil,
                borrowerEmail: vm.borrowerEmail,
                borrowerPhone: nil
            )

            createdLoan = newLoan
            onLoanCreated?(newLoan)
            dismiss()

        } catch {
            vm.errorMessage = "Failed to create: \(error.localizedDescription)"
        }
    }

    private func schedulePrincipalAutoFocusIfNeeded() {
        focusTask?.cancel()
        guard viewModel.currentStep == .amount else { return }
        focusTask = Task {
            // Let sheet/fullScreen transition finish before opening keyboard.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, viewModel.currentStep == .amount else { return }
            await MainActor.run {
                isPrincipalFieldFocused = true
            }
        }
    }

    private func prefillLenderFromProfileIfNeeded(vm: LoanConstructionViewModel) {
        guard !didPrefillLenderProfile else { return }
        guard let profile = authManager.currentUserProfile else { return }

        if let first = profile.first_name?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            vm.lenderFirstName = first
        }
        if let last = profile.last_name?.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty {
            vm.lenderLastName = last
        }
        if let addressLine1 = profile.address_line_1?.trimmingCharacters(in: .whitespacesAndNewlines), !addressLine1.isEmpty {
            vm.lenderAddressLine1 = addressLine1
        }
        if let addressLine2 = profile.address_line_2?.trimmingCharacters(in: .whitespacesAndNewlines) {
            vm.lenderAddressLine2 = addressLine2
        }
        if let phone = profile.phone_number?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            vm.lenderPhone = phone
        }
        if let state = profile.residence_state?.trimmingCharacters(in: .whitespacesAndNewlines), state.count == 2 {
            vm.lenderState = state.uppercased()
        }
        if let country = profile.country?.trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
            vm.lenderCountry = country
        }
        if let postalCode = profile.postal_code?.trimmingCharacters(in: .whitespacesAndNewlines), !postalCode.isEmpty {
            vm.lenderPostalCode = postalCode
        }
        didPrefillLenderProfile = true
    }
}

#Preview {
    NavigationStack {
        LoanConstructionView()
            .environment(LoanManager())
            .environment(AuthManager())
    }
}
