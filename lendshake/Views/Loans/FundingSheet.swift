//
//  FundingSheet.swift
//  lendshake
//
//  Created by Assistant on 2/4/26.
//

import SwiftUI
import PhotosUI
import Supabase

struct FundingSheet: View {
    let loan: Loan
    @Binding var isPresented: Bool
    @Environment(LoanManager.self) var loanManager
    
    @State private var date: Date = Date()
    @State private var isLoading: Bool = false
    @State private var errorMsg: String?
    
    // Photo Picker State
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Funding Details") {
                    LabeledContent("Amount to Send", value: loan.principal_amount.formatted(.currency(code: "USD")))
                    
                    DatePicker("Date Sent", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Proof of Transfer (Screenshot)") {
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
                            Text("Confirm Funds Sent")
                                .frame(maxWidth: .infinity)
                                .bold()
                                .foregroundStyle(.white)
                        }
                        .listRowBackground(Color.green)
                    }
                }
                
                if let errorMsg {
                    Section {
                        Text(errorMsg)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Release Funds")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
    
    func submit() {
        // Require image? Depending on 'required' constraint. Assuming yes for "Evidence".
        guard selectedImageData != nil else {
            errorMsg = "Please attach a screenshot of the transaction."
            return
        }
        
        isLoading = true
        
        Task {
            do {
                var proofURL: String? = nil
                
                // Upload Proof
                if let data = selectedImageData {
                    let user = try await supabase.auth.session.user
                    proofURL = try await StorageManager.shared.uploadProof(data: data, userId: user.id)
                }
                
                try await loanManager.confirmFunding(loan: loan, proofURL: proofURL)
                isPresented = false
            } catch {
                errorMsg = error.localizedDescription
            }
            isLoading = false
        }
    }
}
