//
//  LoanUpdatePayloads.swift
//  lendshake
//
//  Created by Assistant on 2/7/26.
//

import Foundation

struct BalanceOnlyUpdate: Encodable {
    let remaining_balance: Double
}

struct BalanceUpdate: Encodable {
    let remaining_balance: Double
    let status: LoanStatus?
    let release_document_text: String?
}

enum AuthError: Error {
    case notAuthenticated
}
