//
//  LoanModels.swift
//  lendshake
//
//  Created by Assistant on 2/4/26.
//

import Foundation
import SwiftUI

enum LoanStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case draft = "draft"
    case sent = "sent"
    case approved = "approved" // Borrower signed, waiting for lender to send funds
    case funding_sent = "funding_sent" // Lender sent funds, waiting for borrower to confirm
    case active = "active"
    case completed = "completed"
    case forgiven = "forgiven"
    case cancelled = "cancelled"
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Pending"
        case .approved: return "Signed"
        case .funding_sent: return "Funding Sent"
        case .active: return "Active"
        case .completed: return "Paid Off"
        case .forgiven: return "Forgiven"
        case .cancelled: return "Cancelled"
        }
    }
}

enum LoanInterestType: String, Codable, CaseIterable, Identifiable {
    case percentage = "percentage"
    case fixed = "fixed" // Legacy support for existing records
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .percentage: return "Percentage (%)"
        case .fixed: return "Legacy Fixed Fee ($)"
        }
    }
}

enum PaymentStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .pending: return "Pending Review"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        }
    }
}

enum PaymentType: String, Codable, CaseIterable, Identifiable {
    case repayment = "repayment"
    case funding = "funding"
    case lateFee = "late_fee"
    case interest = "interest"
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .repayment: return "Repayment"
        case .funding: return "Funding"
        case .lateFee: return "Late Fee"
        case .interest: return "Interest"
        }
    }
}

struct Payment: Codable, Identifiable, Hashable {
    var id: UUID?
    let loan_id: UUID
    let amount: Double
    let date: Date
    var status: PaymentStatus
    var type: PaymentType // 'repayment' or 'funding'
    let created_at: Date?
    let proof_url: String?
    var rejection_reason: String?
    
    init(loanId: UUID, amount: Double, date: Date, type: PaymentType = .repayment, proofURL: String? = nil) {
        self.id = nil
        self.loan_id = loanId
        self.amount = amount
        self.date = date
        self.status = .pending
        self.type = type
        self.proof_url = proofURL
        self.rejection_reason = nil
        self.created_at = nil
    }
}

struct Loan: Codable, Identifiable, Hashable {
    var id: UUID?
    let lender_id: UUID
    var borrower_id: UUID? // Optional: Links to auth.users once known/claimed
    let principal_amount: Double
    let interest_rate: Double
    var interest_type: LoanInterestType? // Optional for backward compatibility, defaults to .percentage if nil
    let repayment_schedule: String
    let late_fee_policy: String
    let maturity_date: Date
    let borrower_name: String?
    let borrower_email: String?
    let borrower_phone: String?
    var lender_name_snapshot: String?
    var borrower_name_snapshot: String?
    var status: LoanStatus
    var remaining_balance: Double?
    let created_at: Date?
    
    // Agreement Fields
    var agreement_text: String?
    var lender_signed_at: Date?
    var borrower_signed_at: Date?
    var lender_ip: String?
    var borrower_ip: String?
    var agreement_rejection_reason: String?
    
    // Phase 5 Closeout
    var release_document_text: String? // "Paid in Full" receipt
    
    // Helper to initialize for creation
    init(
        lenderId: UUID,
        principal: Double,
        interest: Double,
        interestType: LoanInterestType = .percentage,
        schedule: String,
        lateFee: String,
        maturity: Date,
        borrowerName: String?,
        borrowerEmail: String?,
        borrowerPhone: String?,
        createdAt: Date? = nil
    ) {
        self.id = nil // Supabase will generate
        self.lender_id = lenderId
        self.borrower_id = nil // Initially nil
        self.principal_amount = principal
        self.interest_rate = interest
        self.interest_type = interestType
        self.repayment_schedule = schedule
        self.late_fee_policy = lateFee
        self.maturity_date = maturity
        self.borrower_name = borrowerName
        self.borrower_email = borrowerEmail
        self.borrower_phone = borrowerPhone
        self.lender_name_snapshot = nil
        self.borrower_name_snapshot = borrowerName
        self.status = .draft
        self.remaining_balance = principal // Initial balance = principal
        self.created_at = createdAt
        self.agreement_text = nil
        self.release_document_text = nil
        self.lender_signed_at = nil
        self.borrower_signed_at = nil
        self.lender_ip = nil
        self.borrower_ip = nil
        self.agreement_rejection_reason = nil
    }
    
    // MARK: - Payment Helpers
    
    var nextPaymentDate: Date {
        let schedule = repayment_schedule.lowercased()
        if schedule.contains("month") {
            // Find next date matching the 'day' of creation?
            // Or simply next month from today?
            // Let's go with: Next Month Anniversary from Today
            let calendar = Calendar.current
            let start = created_at ?? Date()
            
            // Get the day component of the start date (e.g., 5th)
            let dayComponent = calendar.component(.day, from: start)
            
            // Get today components
            let today = Date()
            let currentMonth = calendar.component(.month, from: today)
            let currentYear = calendar.component(.year, from: today)
            
            // Construct potential date for this month
            var components = DateComponents()
            components.year = currentYear
            components.month = currentMonth
            components.day = dayComponent
            
            if let thisMonthDate = calendar.date(from: components) {
                if thisMonthDate > today {
                    return thisMonthDate
                } else {
                    // It's passed, so next month
                    return calendar.date(byAdding: .month, value: 1, to: thisMonthDate) ?? maturity_date
                }
            }
            return maturity_date
        }
        // Default / Lump Sum / Bi-weekly (fallback) -> Maturity Date
        return maturity_date
    }
    
    var minimumPaymentAmount: Double {
        let balance = remaining_balance ?? principal_amount
        if balance <= 0 { return 0 }
        
        let schedule = repayment_schedule.lowercased()
        
        if schedule.contains("month") {
            // Estimate: Balance / Months Remaining
            let calendar = Calendar.current
            let today = Date()
            
            let components = calendar.dateComponents([.month], from: today, to: maturity_date)
            let monthsRemaining = max(1, components.month ?? 1)
            
            return balance / Double(monthsRemaining)
        }
        
        // Lump Sum -> Full Balance
        return balance
    }
    
    // MARK: - Late Fee Logic
    
    var lateFeeAmount: Double? {
        let policy = late_fee_policy.trimmingCharacters(in: .whitespacesAndNewlines)
        if policy.isEmpty || policy.lowercased() == "none" { return nil }
        
        // Support plain numeric values from the slider ("15", "15.0")
        if let direct = Double(policy), direct > 0 {
            return direct
        }
        
        // Backward compatibility for descriptive strings like "$15 after 5 days"
        if let range = policy.range(of: "\\$\\s*[0-9]+(?:\\.[0-9]+)?", options: .regularExpression) {
            let raw = String(policy[range]).replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
            if let amount = Double(raw), amount > 0 {
                return amount
            }
        }
        
        return nil
    }
    
    var gracePeriodDays: Int {
        // Parse "after 5 days"
        // Look for digit before "day"
        // Default to 5 if not found but policy exists
        if late_fee_policy.isEmpty || late_fee_policy.lowercased() == "none" { return 0 }
        
        // Simple heuristic: extract first number not attached to $?
        // Or strictly look for "X days"
        // Let's default to 5 for MVP if parsing fails but amount exists
        return 5
    }
}
