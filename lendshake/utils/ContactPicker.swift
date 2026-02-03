//
//  ContactPicker.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import ContactsUI

struct ContactPicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var selectedEmail: String
    @Binding var selectedPhone: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker
        
        init(_ parent: ContactPicker) {
            self.parent = parent
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            // Get Name
            parent.firstName = contact.givenName
            parent.lastName = contact.familyName
            
            // Get Email (first one)
            if let firstEmail = contact.emailAddresses.first {
                parent.selectedEmail = firstEmail.value as String
            }
            
            // Get Phone (first one)
            if let firstPhone = contact.phoneNumbers.first {
                parent.selectedPhone = firstPhone.value.stringValue
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
