//
//  LoanStatusBadge.swift
//  lendshake
//
//  Created by Assistant on 2/3/26.
//

import SwiftUI

enum LoanStatus: String, Codable, CaseIterable, Hashable {
    case draft = "draft"
    case sent = "sent"
    case active = "active"
    case completed = "completed"
    case forgiven = "forgiven"
    case cancelled = "cancelled"
    
    var title: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Pending"
        case .active: return "Active"
        case .completed: return "Paid Off"
        case .forgiven: return "Forgiven"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: Color {
        switch self {
        case .draft: return .gray
        case .sent: return .orange
        case .active: return .green
        case .completed: return .blue
        case .forgiven: return .purple
        case .cancelled: return .red
        }
    }
}

struct LoanStatusBadge: View {
    let status: LoanStatus
    
    var body: some View {
        Text(status.title)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }
}

#Preview {
    VStack {
        LoanStatusBadge(status: .draft)
        LoanStatusBadge(status: .sent)
        LoanStatusBadge(status: .active)
        LoanStatusBadge(status: .completed)
        LoanStatusBadge(status: .cancelled)
    }
}
