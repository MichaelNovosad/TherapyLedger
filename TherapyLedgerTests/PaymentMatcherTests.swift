import Foundation
import Testing
import SwiftData
@testable import TherapyLedger

struct PaymentMatcherTests {
    @Test func normalizationStripsSenderPrefixAndWhitespace() {
        #expect(PaymentMatcher.normalizeName("Від: Іван  Петренко ") == "іван петренко")
        #expect(PaymentMatcher.normalizeName("From: John Smith") == "john smith")
        #expect(PaymentMatcher.normalizeName("  Марія   Коваль") == "марія коваль")
    }

    @Test func ibanMatchesExactlyIgnoringSpacesAndCase() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        context.insert(PayerAlias(matchText: "ua21 3223 1300 0002 6007 2335 6600 1", kind: .iban, patient: patient))

        let aliases = try context.fetch(FetchDescriptor<PayerAlias>())
        let match = PaymentMatcher.match(
            senderName: nil,
            senderIban: "UA213223130000026007233566001",
            description: nil,
            aliases: aliases
        )
        #expect(match === patient)
    }

    @Test func senderNameInDescriptionMatchesAlias() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Ivan", sessionFeeMinor: 100_000)
        context.insert(patient)
        context.insert(PayerAlias(matchText: "Іван Петренко", kind: .senderName, patient: patient))

        let aliases = try context.fetch(FetchDescriptor<PayerAlias>())
        let match = PaymentMatcher.match(
            senderName: nil,
            senderIban: nil,
            description: "Від: Іван Петренко",
            aliases: aliases
        )
        #expect(match === patient)
    }

    @Test func partialAliasMatchesLongerSenderName() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Ivan", sessionFeeMinor: 100_000)
        context.insert(patient)
        context.insert(PayerAlias(matchText: "Петренко", kind: .senderName, patient: patient))

        let aliases = try context.fetch(FetchDescriptor<PayerAlias>())
        let match = PaymentMatcher.match(
            senderName: "Іван Петренко",
            senderIban: nil,
            description: nil,
            aliases: aliases
        )
        #expect(match === patient)
    }

    @Test func unknownSenderDoesNotMatch() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Ivan", sessionFeeMinor: 100_000)
        context.insert(patient)
        context.insert(PayerAlias(matchText: "Іван Петренко", kind: .senderName, patient: patient))

        let aliases = try context.fetch(FetchDescriptor<PayerAlias>())
        let match = PaymentMatcher.match(
            senderName: "Олена Шевченко",
            senderIban: nil,
            description: "Дякую!",
            aliases: aliases
        )
        #expect(match == nil)
    }
}
