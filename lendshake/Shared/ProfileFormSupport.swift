//
//  ProfileFormSupport.swift
//  lendshake
//
//  Created by Assistant on 2/11/26.
//

import Foundation

enum ProfileReferenceData {
    static let defaultCountry = "United States"
    static let usStates = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]
}

enum ProfileValidation {
    static func validateFirstName(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "First name is required." }
        if normalized.count < 2 { return "First name must be at least 2 characters." }
        return nil
    }

    static func validateLastName(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "Last name is required." }
        if normalized.count < 2 { return "Last name must be at least 2 characters." }
        return nil
    }

    static func validateAddressLine1(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "Address line 1 is required." }
        if normalized.count < 6 { return "Enter a valid address line 1." }
        return nil
    }

    static func validateCountry(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Country is required." : nil
    }

    static func validatePostalCode(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 ? nil : "Enter a valid postal code."
    }

    static func validateState(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ProfileReferenceData.usStates.contains(normalized) ? nil : "Select a valid state of residence."
    }

    static func validatePhone(_ value: String, required: Bool) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return required ? "Phone number is required." : nil
        }
        let digits = normalized.filter(\.isNumber).count
        return (digits >= 10 && digits <= 15) ? nil : "Phone must include 10-15 digits."
    }
}
