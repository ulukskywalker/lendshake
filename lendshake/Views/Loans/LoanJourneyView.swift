//
//  LoanJourneyView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct LoanJourneyView: View {
    @Environment(\.colorScheme) private var colorScheme

    let status: LoanStatus
    let isLender: Bool

    var journeySteps: [String] {
        switch status {
        case .cancelled:
            return ["Agreement", "Funding", "Cancelled"]
        case .forgiven:
            return ["Agreement", "Funding", "Repayment", "Forgiven"]
        default:
            return ["Agreement", "Funding", "Repayment", "Done"]
        }
    }

    // 0-based index into journeySteps.
    var currentStepIndex: Int {
        switch status {
        case .draft, .sent:
            return 0
        case .approved, .funding_sent:
            return min(1, journeySteps.count - 1)
        case .active:
            return min(2, journeySteps.count - 1)
        case .completed, .forgiven, .cancelled:
            return max(journeySteps.count - 1, 0)
        }
    }

    var themeColor: Color {
        isLender ? Color.lsPrimary : Color.orange
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("LOAN JOURNEY")
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal)
            
            // Steps
            HStack(spacing: 0) {
                ForEach(Array(journeySteps.enumerated()), id: \.offset) { index, label in
                    journeyPoint(index: index, label: label)
                    if index < journeySteps.count - 1 {
                        journeyLine(index: index)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .background(Color.lsCardBackground)
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    @ViewBuilder
    func journeyPoint(index: Int, label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(getPointColor(index))
                    .frame(width: 20, height: 20)
                
                if status == .cancelled && index == currentStepIndex {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if index < currentStepIndex || ((status == .completed || status == .forgiven) && index == currentStepIndex) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if index == currentStepIndex {
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                        .frame(width: 6, height: 6)
                }
            }
            
            Text(label)
                .font(.system(size: 9))
                .fontWeight(.bold)
                .foregroundStyle(index == currentStepIndex ? .primary : .secondary)
                .fixedSize()
        }
    }
    
    @ViewBuilder
    func journeyLine(index: Int) -> some View {
        Rectangle()
            .fill(getLineColor(index))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .offset(y: -9) // Align with circle center (roughly)
    }
    
    func getPointColor(_ index: Int) -> Color {
        if index < currentStepIndex {
            return themeColor
        } else if status == .cancelled && index == currentStepIndex {
            return .red
        } else if index == currentStepIndex {
            return themeColor
        } else if (status == .completed || status == .forgiven) && index == currentStepIndex {
            return themeColor
        } else {
            return Color.gray.opacity(0.2)
        }
    }
    
    func getLineColor(_ index: Int) -> Color {
        if index < currentStepIndex {
            return themeColor
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

#Preview {
    VStack {
        LoanJourneyView(status: .draft, isLender: true)
        LoanJourneyView(status: .approved, isLender: true) // Step 2
        LoanJourneyView(status: .active, isLender: true) // Step 3
        LoanJourneyView(status: .completed, isLender: false) // Step 4
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
