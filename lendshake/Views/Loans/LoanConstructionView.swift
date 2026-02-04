//
//  LoanConstructionView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct LoanConstructionView: View {
    @Environment(LoanManager.self) var loanManager
    @Environment(\.dismiss) var dismiss
    
    @State private var principalAmount: String = ""
    @State private var isFamilyRate: Bool = false
    @State private var interestRate: String = ""
    @State private var repaymentSchedule: RepaymentSchedule = .monthly
    @State private var lateFeePolicy: String = ""
    @State private var maturityDate: Date = Date().addingTimeInterval(86400 * 30) // Default 30 days
    
    // Contact Properties
    @State private var borrowerFirstName: String = ""
    @State private var borrowerLastName: String = ""
    @State private var borrowerEmail: String = ""
    @State private var borrowerPhone: String = ""
    @State private var showContactPicker: Bool = false
    
    @State private var createdLoan: Loan?
    @State private var errorMessage: String?
    
    enum RepaymentSchedule: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case biweekly = "Bi-weekly"
        case lumpSum = "Lump Sum"
        
        var id: String { self.rawValue }
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("How it works", systemImage: "info.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Color.lsPrimary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("1.")
                                .bold()
                                .foregroundStyle(.secondary)
                            Text("Draft the loan terms below.")
                        }
                        HStack(alignment: .top) {
                            Text("2.")
                                .bold()
                                .foregroundStyle(.secondary)
                            Text("Review and sign the agreement.")
                        }
                        HStack(alignment: .top) {
                            Text("3.")
                                .bold()
                                .foregroundStyle(.secondary)
                            Text("Transfer funds **only after** both parties sign.")
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.lsBackground)
            
            Section(header: Text("Borrower")) {
                Button {
                    showContactPicker = true
                } label: {
                    Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                        .foregroundStyle(Color.lsPrimary)
                }
                
                TextField("First Name", text: $borrowerFirstName)
                TextField("Last Name", text: $borrowerLastName)
                
                TextField("Email Address (Required)", text: $borrowerEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                
                TextField("Phone Number", text: $borrowerPhone)
                    .keyboardType(.phonePad)
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPicker(
                    firstName: $borrowerFirstName,
                    lastName: $borrowerLastName,
                    selectedEmail: $borrowerEmail,
                    selectedPhone: $borrowerPhone
                )
            }
            
            Section(header: Text("Loan Details"), footer: Group {
                if !isFamilyRate {
                    Text("Interest is calculated yearly. For example, 10% on $1,000 is $100/year. The IRS sets a minimum rate (~4-5%) for family loans to avoid gift tax.")
                }
            }) {
                TextField("Principal Amount ($)", text: $principalAmount)
                    .keyboardType(.decimalPad)
                
                Toggle("Family/Friend Rate (0%)", isOn: $isFamilyRate)
                
                if !isFamilyRate {
                    TextField("Annual Interest Rate (%)", text: $interestRate)
                        .keyboardType(.decimalPad)
                }
            }
            
            Section(header: Text("Repayment Terms"), footer: Text("This fee will apply to any installment not paid by its due date.")) {
                Picker("Repayment Schedule", selection: $repaymentSchedule) {
                    ForEach(RepaymentSchedule.allCases) { schedule in
                        Text(schedule.rawValue).tag(schedule)
                    }
                }
                
                DatePicker("Final Payment Date", selection: $maturityDate, in: Date()..., displayedComponents: .date)
                
                TextField("Late Fee ($)", text: $lateFeePolicy)
            }
            
            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            
            Section {
                HStack(spacing: 12) {
                    // Save Button
                    Button {
                        Task {
                            await createLoan(navigate: false)
                        }
                    } label: {
                        Text("Save Draft")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundStyle(Color.primary)
                            .cornerRadius(10)
                    }
                    .disabled(loanManager.isLoading)
                    
                    // Generate Button
                    Button {
                        Task {
                            await createLoan(navigate: true)
                        }
                    } label: {
                        if loanManager.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Text("Review")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.lsPrimary)
                                .foregroundStyle(.white)
                                .cornerRadius(10)
                        }
                    }
                    .disabled(principalAmount.isEmpty || loanManager.isLoading)
                }
                .listRowInsets(EdgeInsets()) // Remove default list padding for custom look
                .padding()
                .background(Color.clear) // Transparent row
            }
        }
        .navigationTitle("New Loan")
        .navigationDestination(item: $createdLoan) { loan in
            LoanDetailView(loan: loan)
        }
    }
    
    private func createLoan(navigate: Bool) async {
        errorMessage = nil
        guard let principal = Double(principalAmount), principal > 0 else {
            errorMessage = "Please enter a valid principal amount."
            return
        }
        
        guard !borrowerEmail.isEmpty else {
            errorMessage = "Borrower email is required for digital signatures."
            return
        }
        
        guard !borrowerFirstName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "First Name is required."
            return
        }
        
        guard !borrowerLastName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Last Name is required."
            return
        }
        
        let interest = isFamilyRate ? 0.0 : (Double(interestRate) ?? 0.0)
        let fullName = "\(borrowerFirstName) \(borrowerLastName)".trimmingCharacters(in: .whitespaces)
        
        do {
            let newLoan = try await loanManager.createDraftLoan(
                principal: principal,
                interest: interest,
                schedule: repaymentSchedule.rawValue,
                lateFee: lateFeePolicy,
                maturity: maturityDate,
                borrowerName: fullName.isEmpty ? nil : fullName,
                borrowerEmail: borrowerEmail.isEmpty ? nil : borrowerEmail,
                borrowerPhone: borrowerPhone.isEmpty ? nil : borrowerPhone
            )
            
            if navigate {
                // Navigate to the note
                self.createdLoan = newLoan
            } else {
                // Just dismiss
                dismiss()
            }
            
        } catch {
            errorMessage = "Failed to create draft: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        LoanConstructionView()
    }
}
