//
//  ContactPicker.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import ContactsUI

struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var selectedEmail: String
    @Binding var selectedPhone: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        
        guard isPresented else { return }
        guard !context.coordinator.isPickerPresented else { return }
        guard uiViewController.presentedViewController == nil else { return }
        
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        context.coordinator.isPickerPresented = true
        uiViewController.present(picker, animated: true)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker
        var isPickerPresented = false
        
        init(_ parent: ContactPicker) {
            self.parent = parent
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            DispatchQueue.main.async {
                if contact.isKeyAvailable(CNContactGivenNameKey) {
                    self.parent.firstName = contact.givenName
                }
                if contact.isKeyAvailable(CNContactFamilyNameKey) {
                    self.parent.lastName = contact.familyName
                }
                
                if contact.isKeyAvailable(CNContactEmailAddressesKey),
                   let firstEmail = contact.emailAddresses.first {
                    self.parent.selectedEmail = firstEmail.value as String
                }
                
                if contact.isKeyAvailable(CNContactPhoneNumbersKey),
                   let firstPhone = contact.phoneNumbers.first {
                    self.parent.selectedPhone = firstPhone.value.stringValue
                }
                
                self.dismissPicker(picker)
            }
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            DispatchQueue.main.async {
                self.dismissPicker(picker)
            }
        }
        
        private func dismissPicker(_ picker: CNContactPickerViewController) {
            picker.dismiss(animated: true)
            isPickerPresented = false
            parent.isPresented = false
        }
    }
}
