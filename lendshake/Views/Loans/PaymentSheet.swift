//
//  PaymentSheet.swift
//  lendshake
//
//  Created by Assistant on 2/3/26.
//

import SwiftUI

import PhotosUI
import Supabase

struct PaymentSheet: View {
    let loan: Loan
    @Binding var isPresented: Bool
    @Environment(LoanManager.self) var loanManager
    
    @State private var amount: Double?
    @State private var date: Date = Date()
    @State private var isLoading: Bool = false
    @State private var errorMsg: String?
    
    // Photo Picker State
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @FocusState private var isAmountFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Payment Details") {
                    TextField("Amount ($)", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .focused($isAmountFieldFocused)
                    
                    DatePicker("Date Paid", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Proof of Payment (Optional)") {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "photo")
                            Text(selectedImageData == nil ? "Select Screenshot" : "Change Screenshot")
                        }
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                selectedImageData = data
                            }
                        }
                    }
                    
                    if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .cornerRadius(10)
                    }
                }
                
                Section {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Button {
                            submit()
                        } label: {
                            Text("Submit Payment")
                                .frame(maxWidth: .infinity)
                                .bold()
                        }
                    }
                }
                
                if let errorMsg {
                    Section {
                        Text(errorMsg)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Record Payment")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isAmountFieldFocused = false
                    }
                }
            }
        }
    }
    
    func submit() {
        guard let amount = amount, amount > 0 else {
            errorMsg = "Please enter a valid amount."
            return
        }
        
        isLoading = true
        
        Task {
            do {
                var proofURL: String? = nil
                
                // Upload Proof if exists
                if let data = selectedImageData {
                    let user = try await supabase.auth.session.user
                    proofURL = try await StorageManager.shared.uploadProof(data: data, userId: user.id)
                }
                
                try await loanManager.submitPayment(for: loan, amount: amount, date: date, proofURL: proofURL)
                isPresented = false
            } catch {
                errorMsg = error.localizedDescription
            }
            isLoading = false
        }
    }
}
