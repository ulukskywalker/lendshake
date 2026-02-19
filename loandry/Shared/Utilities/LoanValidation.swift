
//
//  LoanValidation.swift
//  loandry
//
//  Created by Assistant on 2/18/26.
//

import Foundation

enum LoanReferenceData {
    // The app enforces a global 15% cap to comply with most usury laws.
    static let maxInterestRate: Double = 15.0
    
    // As of early 2026, rates are around 4-5%.
    static let minimumAFR: Double = 4.5
}

enum LoanValidationResult {
    case valid
    case invalid(String) // Blocking error
    case warning(String) // Non-blocking warning
}

enum LoanValidation {
    static func validateUsury(rate: Double) -> LoanValidationResult {
        if rate > LoanReferenceData.maxInterestRate {
             return .invalid("Interest rate cannot exceed \(Int(LoanReferenceData.maxInterestRate))%.")
        }
        return .valid
    }
    
    static func validateAFR(rate: Double) -> LoanValidationResult {
        if rate == 0 {
             return .warning("0% interest avoids tax complications for family loans.")
        }
        
        if rate < LoanReferenceData.minimumAFR {
            return .warning("Rates below \(LoanReferenceData.minimumAFR)% (current AFR) may have Gift Tax implications.")
        }
        
        return .valid
    }
}
