//
//  LoanManager+AutoEvents.swift
//  lendshake
//
//  Created by Assistant on 2/7/26.
//

import Foundation
import Supabase

extension LoanManager {
    // MARK: - Auto-Events (Catch-Up Logic)

    func checkAutoEvents(for loan: Loan) async throws {
        guard loan.status == .active else { return }
        guard let loanId = loan.id else { return }
        guard let feeAmount = loan.lateFeeAmount, feeAmount > 0 else { return }
        let now = Date()

        let existingPayments = try await fetchPayments(for: loan)
        let missingFeesCount = LoanMath.calculateMissingLateFees(for: loan, existingPayments: existingPayments)

        var feesToAdd: [Payment] = []
        var balanceIncrease: Double = 0

        if missingFeesCount > 0 {
            print("DEBUG: Catch-Up found \(missingFeesCount) missing late fees.")

            for _ in 0..<missingFeesCount {
                let newFee = Payment(
                    loanId: loanId,
                    amount: feeAmount,
                    date: now,
                    type: .lateFee
                )
                feesToAdd.append(newFee)
                balanceIncrease += feeAmount
            }
        }

        if !feesToAdd.isEmpty {
            for var fee in feesToAdd {
                fee.status = .approved
                try await supabase.from("payments").insert(fee).execute()
            }

            let currentBalance = loan.remaining_balance ?? loan.principal_amount
            let newBalance = currentBalance + balanceIncrease

            try await supabase
                .from("loans")
                .update(BalanceOnlyUpdate(remaining_balance: newBalance))
                .eq("id", value: loanId)
                .execute()

            try await fetchLoans()
        }

        try await checkInterest(for: loan)
    }

    private func checkInterest(for loan: Loan) async throws {
        guard loan.status == .active else { return }
        guard let loanId = loan.id else { return }

        if loan.interest_type == .fixed {
            guard loan.interest_rate > 0 else { return }

            let existingPayments = try await fetchPayments(for: loan)
            let hasInterest = existingPayments.contains { $0.type == .interest }

            if !hasInterest {
                let feePayment = Payment(
                    loanId: loanId,
                    amount: loan.interest_rate,
                    date: loan.created_at ?? Date(),
                    type: .interest
                )

                var payment = feePayment
                payment.status = .approved
                try await supabase.from("payments").insert(payment).execute()

                let currentBalance = loan.remaining_balance ?? loan.principal_amount
                let newBalance = currentBalance + loan.interest_rate

                try await supabase
                    .from("loans")
                    .update(BalanceOnlyUpdate(remaining_balance: newBalance))
                    .eq("id", value: loanId)
                    .execute()

                try await fetchLoans()
            }

        } else {
            guard loan.interest_rate > 0 else { return }
            let now = Date()
            let existingPayments = try await fetchPayments(for: loan)
            let (missingCount, monthlyAmount) = LoanMath.calculateMissingInterest(for: loan, existingPayments: existingPayments)

            var interestToAdd: [Payment] = []
            var balanceIncrease: Double = 0

            if missingCount > 0 {
                print("DEBUG: Catch-Up found \(missingCount) missing interest payments.")

                for _ in 0..<missingCount {
                    let newInterest = Payment(
                        loanId: loanId,
                        amount: monthlyAmount,
                        date: now,
                        type: .interest
                    )
                    interestToAdd.append(newInterest)
                    balanceIncrease += monthlyAmount
                }
            }

            if !interestToAdd.isEmpty {
                for var payment in interestToAdd {
                    payment.status = .approved
                    try await supabase.from("payments").insert(payment).execute()
                }

                let currentBalance = loan.remaining_balance ?? loan.principal_amount
                let newBalance = currentBalance + balanceIncrease

                try await supabase
                    .from("loans")
                    .update(BalanceOnlyUpdate(remaining_balance: newBalance))
                    .eq("id", value: loanId)
                    .execute()

                try await fetchLoans()
            }
        }
    }
}
