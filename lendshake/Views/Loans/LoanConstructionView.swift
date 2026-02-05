//
//  LoanConstructionView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct LoanConstructionView: View {
    @Environment(LoanManager.self) var loanManager
    @Environment(AuthManager.self) var authManager
    @Environment(\.dismiss) var dismiss
    
    var onLoanCreated: ((Loan) -> Void)?
    
    // MARK: - Integration State
    @State private var createdLoan: Loan?
    @State private var errorMessage: String?
    @State private var showContactPicker: Bool = false

    
    // MARK: - Wizard State
    enum WizardStep: Int, CaseIterable {
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
    
    @State private var currentStep: WizardStep = .amount
    
    // MARK: - Data State
    @State private var principalAmount: String = ""
    @State private var isFamilyRate: Bool = true
    @State private var interestRate: String = ""
    @State private var interestType: LoanInterestType = .percentage
    @State private var repaymentSchedule: RepaymentSchedule = .monthly
    @State private var maturityDate: Date = Date().addingTimeInterval(86400 * 30 * 6) // Default 6 months
    @State private var borrowerFirstName: String = ""
    @State private var borrowerLastName: String = ""
    @State private var borrowerEmail: String = ""
    @State private var borrowerPhone: String = ""
    
    // Default Late Fee
    @State private var lateFeePolicy: String = "0"

    enum RepaymentSchedule: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case biweekly = "Bi-weekly"
        case lumpSum = "Lump Sum"
        var id: String { self.rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Step Indicator
            stepHeader
            
            // Main Content Area
            ZStack {
                switch currentStep {
                case .amount:
                    stepAmountView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .terms:
                    stepTermsView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .borrower:
                    stepBorrowerView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case .review:
                    stepReviewView
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Navigation Bar
            bottomNav
        }
        .background(Color.lsBackground.ignoresSafeArea())
        .navigationTitle(currentStep.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Custom nav
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPicker(
                firstName: $borrowerFirstName,
                lastName: $borrowerLastName,
                selectedEmail: $borrowerEmail,
                selectedPhone: $borrowerPhone
            )
        }
        // Error Toast Overlay
        // Error Toast Overlay
        .overlay(alignment: .top) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.cornerRadius(8))
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { errorMessage = nil }
                        }
                    }
            }
        }
    }
    
    // MARK: - Components
    
    var stepHeader: some View {
        HStack(spacing: 4) {
            ForEach(WizardStep.allCases, id: \.self) { step in
                Rectangle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.lsPrimary : Color.gray.opacity(0.2))
                    .frame(height: 4)
                    .cornerRadius(2)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    var bottomNav: some View {
        HStack {
            if currentStep != .amount {
                Button {
                    withAnimation {
                        let prev = currentStep.rawValue - 1
                        if let s = WizardStep(rawValue: prev) { currentStep = s }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
            } else {
                Spacer().frame(width: 50) // Balance spacing
            }
            
            Spacer()
            
            Button {
                handleNext()
            } label: {
                Text(currentStep == .review ? (createdLoan != nil ? "View Draft" : "Create Draft") : "Next")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
                    .frame(width: 160, height: 50)
                    .background(Color.lsPrimary)
                    .cornerRadius(25)
                    .shadow(color: Color.lsPrimary.opacity(0.3), radius: 5, x: 0, y: 3)
            }
            .disabled(loanManager.isLoading)
            
            Spacer()
            
            // Right balancing spacer
            Spacer().frame(width: 50)
        }
        .padding()
        .background(Color.white.ignoresSafeArea(edges: .bottom))
    }
    
    // MARK: - Step 1: Amount
    
    var stepAmountView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Text("How much are you lending?")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            // Huge Input
            TextField("0", text: $principalAmount)
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .keyboardType(.decimalPad)
                .overlay(
                    Text("$")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .offset(x: -120, y: -10) // Rough positioning
                        .opacity(principalAmount.isEmpty ? 0 : 1)
                , alignment: .center)
            
            // Rate Toggle
            VStack {
                Toggle("Family & Friends Rate (0%)", isOn: $isFamilyRate)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                
                if !isFamilyRate {
                    HStack {
                        Text("Interest Rate")
                        Spacer()
                        TextField("Example: 5.0", text: $interestRate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("%")
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .animation(.spring, value: isFamilyRate)
            
            Spacer()
        }
    }
    
    // MARK: - Step 2: Terms
    
    var stepTermsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Repayment Plan")
                    .font(.title2)
                    .bold()
                    .padding(.top)
                
                // Interest Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Interest")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    VStack {
                        // Type Selector
                        Picker("Interest Type", selection: $interestType) {
                            ForEach(LoanInterestType.allCases) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)
                        
                        // Input Field
                        HStack {
                            Text(interestType == .percentage ? "%" : "$")
                                .font(.title2)
                                .bold()
                                .foregroundStyle(Color.lsPrimary)
                            
                            TextField("0", text: $interestRate)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                    )
                }
                
                // Frequency Chips
                VStack(alignment: .leading, spacing: 8) {
                    Text("FREQUENCY")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                    
                    HStack(spacing: 12) {
                        ForEach(RepaymentSchedule.allCases) { schedule in
                            Button {
                                repaymentSchedule = schedule
                            } label: {
                                Text(schedule.rawValue)
                                    .font(.subheadline)
                                    .bold()
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(repaymentSchedule == schedule ? Color.lsPrimary : Color.white)
                                    .foregroundStyle(repaymentSchedule == schedule ? .white : .primary)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Date Row
                HStack {
                    Text("Final Due Date")
                        .font(.body)
                    Spacer()
                    DatePicker("Select Date", selection: $maturityDate, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                
                // Late Fee Row
                HStack {
                    Text("Late Fee Policy")
                         .font(.body)
                    Spacer()
                    TextField("0", text: $lateFeePolicy)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("$")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    // MARK: - Step 3: Borrower
    
    var stepBorrowerView: some View {
        VStack(spacing: 24) {
            Text("Who is the borrower?")
                .font(.title2)
                .bold()
                .padding(.top)
            
            Button {
                showContactPicker = true
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                    Text("Import from Contacts")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.lsPrimary)
                .cornerRadius(16)
            }
            .padding(.horizontal)
            
            Form { // Standard form is good here for reliability
                Section {
                    TextField("First Name (Required)", text: $borrowerFirstName)
                    TextField("Last Name (Required)", text: $borrowerLastName)
                }
                
                Section {
                    TextField("Email (Required)", text: $borrowerEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $borrowerPhone)
                        .keyboardType(.phonePad)
                } footer: {
                    Text("We'll verify their identity before anything is signed.")
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
    
    // MARK: - Step 4: Review
    
    var stepReviewView: some View {
        VStack(spacing: 24) {
            Text("Does this look right?")
                .font(.title2)
                .bold()
                .padding(.top)
            
            // The "Ticket" Preview
            VStack(spacing: 0) {
                // PART 1: The Money
                VStack(spacing: 12) {
                    Text("PROMISSORY NOTE")
                        .font(.caption)
                        .bold()
                        .tracking(3)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                    
                    Text("\(Double(principalAmount)?.formatted(.currency(code: "USD")) ?? "$0")")
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.lsPrimary)
                        .shadow(color: Color.lsPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    if isFamilyRate {
                        Text("FAMILY RATE (0%)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .foregroundStyle(.green)
                            .cornerRadius(20)
                    } else {
                        Text("\(interestRate)% ANNUAL INTEREST")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .cornerRadius(20)
                    }
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                
                Divider()
                
                // PART 2: The Details
                VStack(spacing: 20) {
                    // Row 1: Schedule & Date
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("REPAYMENT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(repaymentSchedule.rawValue)
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("MATURITY DATE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(maturityDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                    }
                    
                    Divider().opacity(0.5)
                    
                    // Row 2: Late Fee
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LATE FEE POLICY")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            if let fee = Double(lateFeePolicy), fee > 0 {
                                Text("\(fee.formatted(.currency(code: "USD"))) after grace period")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            } else {
                                Text("No Late Fee")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    
                    Divider().opacity(0.5)
                    
                    // Row 3: Parties
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LENDER")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(authManager.currentUserProfile?.fullName ?? "Me")
                                .font(.body)
                                .fontWeight(.bold)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("BORROWER")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text("\(borrowerFirstName) \(borrowerLastName)")
                                .font(.body)
                                .fontWeight(.bold)
                        }
                    }
                }
                .padding(24)
                .background(Color.gray.opacity(0.04))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 5)
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
    
    // MARK: - Logic
    
    func handleNext() {
        switch currentStep {
        case .amount:
            guard let amount = Double(principalAmount), amount > 0 else {
                errorMessage = "Enter a valid amount"
                return
            }
            withAnimation { currentStep = .terms }
            
        case .terms:
            withAnimation { currentStep = .borrower }
            
        case .borrower:
            guard !borrowerFirstName.isEmpty, !borrowerLastName.isEmpty, !borrowerEmail.isEmpty else {
                errorMessage = "Name and Email are required"
                return
            }
            // Close keyboard
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation { currentStep = .review }
            
        case .review:
            Task {
                await createLoan()
            }
        }
    }
    
    private func createLoan() async {
        // Prevent duplicate creation
        if let existing = createdLoan {
            dismiss()
            return
        }
        
        guard let principal = Double(principalAmount) else { return }
        let interest = isFamilyRate ? 0.0 : (Double(interestRate) ?? 0.0)
        let fullName = "\(borrowerFirstName) \(borrowerLastName)".trimmingCharacters(in: .whitespaces)
        
        do {
            let newLoan = try await loanManager.createDraftLoan(
                principal: principal,
                interest: interest,
                interestType: interestType,
                schedule: repaymentSchedule.rawValue,
                lateFee: lateFeePolicy,
                maturity: maturityDate,
                borrowerName: fullName,
                borrowerEmail: borrowerEmail,
                borrowerPhone: borrowerPhone.isEmpty ? nil : borrowerPhone
            )
            
            // Success
            createdLoan = newLoan
            onLoanCreated?(newLoan)
            dismiss()
            
        } catch {
            errorMessage = "Failed to create: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        LoanConstructionView()
            .environment(LoanManager())
    }
}
