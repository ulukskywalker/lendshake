//
//  LoanJourneyView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct LoanJourneyView: View {
    let status: LoanStatus
    let isLender: Bool
    
    // 1: Agreement, 2: Funding, 3: Repayment, 4: Done
    var currentStep: Int {
        switch status {
        case .draft, .sent: return 1
        case .approved, .funding_sent: return 2
        case .active: return 3
        case .completed, .forgiven, .cancelled: return 4
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
                journeyPoint(step: 1, label: "Agreement")
                journeyLine(step: 1)
                journeyPoint(step: 2, label: "Funding")
                journeyLine(step: 2)
                journeyPoint(step: 3, label: "Repayment")
                journeyLine(step: 3)
                journeyPoint(step: 4, label: "Done")
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    @ViewBuilder
    func journeyPoint(step: Int, label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(getPointColor(step))
                    .frame(width: 20, height: 20)
                
                if (step < currentStep) || (status == .completed || status == .forgiven) && step == 4 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if step == currentStep {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                }
            }
            
            Text(label)
                .font(.system(size: 9))
                .fontWeight(.bold)
                .foregroundStyle(step == currentStep ? .primary : .secondary)
                .fixedSize()
        }
    }
    
    @ViewBuilder
    func journeyLine(step: Int) -> some View {
        Rectangle()
            .fill(getLineColor(step))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .offset(y: -9) // Align with circle center (roughly)
    }
    
    func getPointColor(_ step: Int) -> Color {
        if step < currentStep {
            return themeColor
        } else if step == currentStep {
            return themeColor
        } else if (status == .completed || status == .forgiven) && step == 4 {
            return themeColor
        } else {
            return Color.gray.opacity(0.2)
        }
    }
    
    func getLineColor(_ step: Int) -> Color {
        if step < currentStep {
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
