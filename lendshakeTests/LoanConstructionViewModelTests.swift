//
//  LoanConstructionViewModelTests.swift
//  lendshakeTests
//
//  Created by Assistant on 2/8/26.
//

import Testing
@testable import lendshake

struct LoanConstructionViewModelTests {
    @MainActor
    @Test
    func amountValidationRejectsOverLimit() {
        let vm = LoanConstructionViewModel()
        vm.principalAmount = "10001"

        let isValid = vm.validateAmountStep()

        #expect(isValid == false)
        #expect(vm.errorMessage == "Principal cannot be more than $10,000.")
    }

    @MainActor
    @Test
    func sanitizePrincipalCapsToMaximum() {
        let vm = LoanConstructionViewModel()

        vm.sanitizePrincipalInput("25000")

        #expect(vm.principalAmount == "10000")
    }

    @MainActor
    @Test
    func borrowerValidationNormalizesEmail() {
        let vm = LoanConstructionViewModel()
        vm.borrowerEmail = "  JANE.DOE@Example.COM  "

        let isValid = vm.validateBorrowerStep()

        #expect(isValid == true)
        #expect(vm.borrowerEmail == "jane.doe@example.com")
    }

    @MainActor
    @Test
    func lenderValidationRequiresCompleteIdentity() {
        let vm = LoanConstructionViewModel()
        vm.lenderFirstName = "John"
        vm.lenderLastName = "Smith"
        vm.lenderAddressLine1 = "123 Main St"
        vm.lenderPhone = "555-123-4567"
        vm.lenderState = "ca"
        vm.lenderCountry = "United States"
        vm.lenderPostalCode = "60601"

        let isValid = vm.validateLenderStep()

        #expect(isValid == true)
        #expect(vm.lenderState == "CA")
    }
}
