//
//  CurrencyUtility.swift
//  loandry
//
//  Created by Assistant on 2/16/26.
//

import Foundation

enum CurrencyUtility {
    static func formatUSD(_ value: Double, fractionalDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = fractionalDigits
        formatter.minimumFractionDigits = fractionalDigits
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
    
    static func sanitizeCurrencyInput(_ value: String, maxLimit: Double) -> (value: String, didRejectForLimit: Bool) {
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

        guard let amount = Double(normalized), amount > maxLimit else {
            return (normalized, false)
        }

        return (String(format: "%.0f", maxLimit), true)
    }
}
