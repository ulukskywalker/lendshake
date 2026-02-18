//
//  LoanConstructionTypes.swift
//  loandry
//
//  Created by Assistant on 2/8/26.
//

import SwiftUI

enum LoanConstructionWizardStep: Int, CaseIterable {
    case amount = 1
    case dates = 2
    case costs = 3
    case lender = 4
    case borrower = 5
    case review = 6

    var title: String {
        switch self {
        case .amount: return "The Money"
        case .dates: return "The Dates"
        case .costs: return "The Costs"
        case .lender: return "Your Info"
        case .borrower: return "Borrower Invite"
        case .review: return "Review"
        }
    }
    
    var icon: String {
        switch self {
        case .amount: return "dollarsign.circle.fill"
        case .dates: return "calendar"
        case .costs: return "percent"
        case .lender: return "person.fill.viewfinder"
        case .borrower: return "envelope.fill"
        case .review: return "checkmark.seal.fill"
        }
    }
    
    var helpMessage: String {
        switch self {
        case .amount: return "We keep loans up to $10,000 so agreements stay simple, personal, and easy to manage."
        case .dates: return "Ensure dates are realistic for the borrower to avoid early default."
        case .costs: return "Interest rates are capped at 15% and late fees at $50 to ensure compliance."
        case .lender: return "Your details are needed for the legal contract."
        case .borrower: return "We'll send the agreement to this email."
        case .review: return "Double check everything before sending."
        }
    }
}

enum RepaymentSchedule: String, CaseIterable, Identifiable {
    case monthly = "Monthly"
    case biweekly = "Bi-weekly"
    case lumpSum = "Lump Sum"

    var id: String { self.rawValue }
}

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amount * sin(animatableData * .pi * shakesPerUnit),
                y: 0
            )
        )
    }
}
