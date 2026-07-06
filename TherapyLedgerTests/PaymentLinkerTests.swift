import Foundation
import Testing
import SwiftData
@testable import TherapyLedger

struct PaymentLinkerTests {
    @Test func linkingOnePayerNeverDisturbsExistingLinks() throws {
        let context = try makeInMemoryContext()
        let anna = Patient(name: "Anna", sessionFeeMinor: 100_000)
        let ivan = Patient(name: "Ivan", sessionFeeMinor: 100_000)
        context.insert(anna)
        context.insert(ivan)

        // Ivan's payment is already linked; Anna's arrives unlinked.
        let ivansLinked = Payment(
            date: date(2026, 7, 1), amountMinor: 100_000, source: .monobank,
            monoId: "ivan-1", senderName: "Іван Петренко", patient: ivan
        )
        let annasPending = Payment(
            date: date(2026, 7, 3), amountMinor: 100_000, source: .monobank,
            monoId: "anna-1", senderName: "Анна Коваль"
        )
        context.insert(ivansLinked)
        context.insert(annasPending)
        try context.save()

        PaymentLinker.link(annasPending, to: anna, rememberPayer: true, context: context)

        // The regression: linking Anna's payer used to clear Ivan's link.
        #expect(ivansLinked.patient === ivan)
        #expect(annasPending.patient === anna)
    }

    @Test func rememberedPayerFillsOnlyMatchingPendingPayments() throws {
        let context = try makeInMemoryContext()
        let anna = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(anna)

        let first = Payment(
            date: date(2026, 7, 1), amountMinor: 100_000, source: .monobank,
            monoId: "a-1", senderName: "Анна Коваль"
        )
        let sameSenderPending = Payment(
            date: date(2026, 7, 8), amountMinor: 100_000, source: .monobank,
            monoId: "a-2", senderName: "Анна Коваль"
        )
        let strangerPending = Payment(
            date: date(2026, 7, 9), amountMinor: 100_000, source: .monobank,
            monoId: "x-1", senderName: "Олена Шевченко"
        )
        for payment in [first, sameSenderPending, strangerPending] {
            context.insert(payment)
        }
        try context.save()

        PaymentLinker.link(first, to: anna, rememberPayer: true, context: context)

        #expect(sameSenderPending.patient === anna)
        #expect(strangerPending.patient == nil)
    }

    @Test func repeatedLinkingDoesNotDuplicateAliases() throws {
        let context = try makeInMemoryContext()
        let anna = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(anna)

        for index in 0..<2 {
            let payment = Payment(
                date: date(2026, 7, 1 + index), amountMinor: 100_000, source: .monobank,
                monoId: "a-\(index)", senderName: "Анна Коваль"
            )
            context.insert(payment)
            PaymentLinker.link(payment, to: anna, rememberPayer: true, context: context)
        }

        #expect(anna.aliases.count == 1)
    }
}
