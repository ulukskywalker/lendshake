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
        vm.borrowerFirstName = "Jane"
        vm.borrowerLastName = "Doe"
        vm.borrowerEmail = "  JANE.DOE@Example.COM  "
        vm.borrowerPhone = ""

        let isValid = vm.validateBorrowerStep()

        #expect(isValid == true)
        #expect(vm.borrowerEmail == "jane.doe@example.com")
    }
}
