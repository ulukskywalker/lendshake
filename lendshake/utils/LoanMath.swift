//
//  LoanMath.swift
//  lendshake
//
//  Created by Assistant on 2/4/26.
//

import Foundation

struct LoanMath {
    
    // MARK: - Late Fees
    
    /// Calculates how many late fees should be added based on the loan terms and existing payments.
    /// - Parameters:
    ///   - loan: The loan to check.
    ///   - existingPayments: All payments currently associated with the loan.
    ///   - referenceDate: The current date (defaults to Date()).
    /// - Returns: An integer representing the number of new fees to add.
    static func calculateMissingLateFees(for loan: Loan, existingPayments: [Payment], referenceDate: Date = Date()) -> Int {
        // Only active loans accrue fees
        guard loan.status == .active else { return 0 }
        
        // Check if Late Fee Policy exists
        guard let _ = loan.lateFeeAmount else { return 0 }
        
        let graceDays = loan.gracePeriodDays
        var deadlines: [Date] = []
        let schedule = loan.repayment_schedule.lowercased()
        let calendar = Calendar.current
        
        // 1. Determine Deadlines
        if schedule.contains("month") {
            let startDate = loan.created_at ?? loan.maturity_date 
            var checkDate = startDate
            
            // Advance to first month anniversary
            if let firstDue = calendar.date(byAdding: .month, value: 1, to: startDate) {
                checkDate = firstDue
            }
            
            // Loop until now
            while checkDate <= referenceDate {
                deadlines.append(checkDate)
                guard let next = calendar.date(byAdding: .month, value: 1, to: checkDate) else { break }
                checkDate = next
            }
        } else if schedule.contains("bi") {
            let startDate = loan.created_at ?? loan.maturity_date
            var checkDate = startDate
            
            if let firstDue = calendar.date(byAdding: .day, value: 14, to: startDate) {
                checkDate = firstDue
            }
            
            while checkDate <= referenceDate {
                deadlines.append(checkDate)
                guard let next = calendar.date(byAdding: .day, value: 14, to: checkDate) else { break }
                checkDate = next
            }
        } else {
            // Lump Sum -> Single Deadline
            deadlines.append(loan.maturity_date)
        }
        
        // 2. Count "Overdue" Deadlines
        let overdueCount = deadlines.filter { deadline in
            if let cutoff = calendar.date(byAdding: .day, value: graceDays, to: deadline) {
                return referenceDate > cutoff
            }
            return false
        }.count
        
        // 3. Count Existing Fees
        let existingFeesCount = existingPayments.filter { $0.type == .lateFee }.count
        
        // 4. Return Difference
        return max(0, overdueCount - existingFeesCount)
    }
    
    // MARK: - Interest
    
    /// Calculates the missing monthly interest payments.
    /// - Parameters:
    ///   - loan: The loan to check.
    ///   - existingPayments: All payments associated with the loan.
    ///   - referenceDate: The current date (defaults to Date()).
    /// - Returns: A tuple containing (NumberOfPaymentsToAdd, AmountPerPayment).
    static func calculateMissingInterest(for loan: Loan, existingPayments: [Payment], referenceDate: Date = Date()) -> (count: Int, amount: Double) {
        guard loan.status == .active else { return (0, 0) }
        guard loan.interest_rate > 0 else { return (0, 0) }
        
        let calendar = Calendar.current
        let start = loan.created_at ?? loan.maturity_date
        
        // Calculate Monthly Interest: (Principal * (Rate/100)) / 12
        let monthlyInterest = (loan.principal_amount * (loan.interest_rate / 100.0)) / 12.0
        
        // Determine Anniversaries
        var interestDates: [Date] = []
        var checkDate = start
        
        if let first = calendar.date(byAdding: .month, value: 1, to: start) {
            checkDate = first
        } else {
            return (0, 0)
        }
        
        while checkDate <= referenceDate {
            interestDates.append(checkDate)
            guard let next = calendar.date(byAdding: .month, value: 1, to: checkDate) else { break }
            checkDate = next
        }
        
        let existingInterestCount = existingPayments.filter { $0.type == .interest }.count
        let expectedCount = interestDates.count
        
        let missing = max(0, expectedCount - existingInterestCount)
        
        return (missing, monthlyInterest)
    }
}
