//
//  LoanConstructionTypes.swift
//  lendshake
//
//  Created by Assistant on 2/8/26.
//

import SwiftUI

enum LoanConstructionWizardStep: Int, CaseIterable {
    case amount = 1
    case terms = 2
    case borrower = 3
    case review = 4

    var title: String {
        switch self {
        case .amount: return "The Money"
        case .terms: return "The Terms"
        case .borrower: return "The Contact"
        case .review: return "Review"
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
