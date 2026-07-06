import Foundation
import Testing
import SwiftData
@testable import TherapyLedger

struct LedgerTests {
    let asOf = date(2026, 6, 15)

    private func makePatient(context: ModelContext, chargesForMissed: Bool = false) -> Patient {
        let patient = Patient(name: "Test", sessionFeeMinor: 120_000, chargesForMissedSessions: chargesForMissed)
        context.insert(patient)
        return patient
    }

    @discardableResult
    private func addSession(
        _ context: ModelContext,
        patient: Patient,
        on sessionDate: Date,
        status: SessionStatus,
        feeMinor: Int = 120_000
    ) -> TherapySession {
        let session = TherapySession(patient: patient, scheduledAt: sessionDate, feeMinor: feeMinor)
        session.status = status
        context.insert(session)
        return session
    }

    @Test func completedSessionIsBilled() throws {
        let context = try makeInMemoryContext()
        let patient = makePatient(context: context)
        addSession(context, patient: patient, on: date(2026, 6, 1), status: .completed)

        let balance = Ledger.balance(sessions: patient.sessions, payments: [], asOf: asOf)
        #expect(balance.billedMinor == 120_000)
        #expect(balance.debtMinor == 120_000)
    }

    @Test func missedSessionBilledOnlyWhenPatientIsCharged() throws {
        let context = try makeInMemoryContext()
        let lenient = makePatient(context: context, chargesForMissed: false)
        let strict = makePatient(context: context, chargesForMissed: true)
        addSession(context, patient: lenient, on: date(2026, 6, 1), status: .missed)
        addSession(context, patient: strict, on: date(2026, 6, 1), status: .missed)

        #expect(Ledger.balance(sessions: lenient.sessions, payments: [], asOf: asOf).billedMinor == 0)
        #expect(Ledger.balance(sessions: strict.sessions, payments: [], asOf: asOf).billedMinor == 120_000)
    }

    @Test func cancelledScheduledAndFutureSessionsAreNotBilled() throws {
        let context = try makeInMemoryContext()
        let patient = makePatient(context: context)
        addSession(context, patient: patient, on: date(2026, 6, 1), status: .cancelled)
        addSession(context, patient: patient, on: date(2026, 6, 10), status: .scheduled)
        // Completed but in the future relative to asOf — not yet billed.
        addSession(context, patient: patient, on: date(2026, 7, 1), status: .completed)

        let balance = Ledger.balance(sessions: patient.sessions, payments: [], asOf: asOf)
        #expect(balance.billedMinor == 0)
    }

    @Test func paymentsReduceDebtAndBuildCredit() throws {
        let context = try makeInMemoryContext()
        let patient = makePatient(context: context)
        addSession(context, patient: patient, on: date(2026, 6, 1), status: .completed)

        let partial = Payment(date: date(2026, 6, 2), amountMinor: 50_000, source: .manual, patient: patient)
        context.insert(partial)
        var balance = Ledger.balance(sessions: patient.sessions, payments: patient.payments, asOf: asOf)
        #expect(balance.debtMinor == 70_000)
        #expect(balance.creditMinor == 0)

        let overpay = Payment(date: date(2026, 6, 3), amountMinor: 100_000, source: .manual, patient: patient)
        context.insert(overpay)
        balance = Ledger.balance(sessions: patient.sessions, payments: patient.payments, asOf: asOf)
        #expect(balance.debtMinor == 0)
        #expect(balance.creditMinor == 30_000)
    }

    @Test func monthlySummariesGroupByMonth() throws {
        let context = try makeInMemoryContext()
        let patient = makePatient(context: context)
        addSession(context, patient: patient, on: date(2026, 3, 3), status: .completed)
        addSession(context, patient: patient, on: date(2026, 3, 10), status: .completed)
        addSession(context, patient: patient, on: date(2026, 3, 17), status: .missed)
        addSession(context, patient: patient, on: date(2026, 4, 7), status: .completed)
        context.insert(Payment(date: date(2026, 3, 11), amountMinor: 240_000, source: .manual, patient: patient))

        let summaries = Ledger.monthlySummaries(
            sessions: patient.sessions,
            payments: patient.payments,
            year: 2026,
            asOf: asOf
        )
        let march = summaries[2]
        #expect(march.billedMinor == 240_000)
        #expect(march.receivedMinor == 240_000)
        #expect(march.completedCount == 2)
        #expect(march.missedCount == 1)

        let april = summaries[3]
        #expect(april.billedMinor == 120_000)
        #expect(april.receivedMinor == 0)

        let totals = Ledger.yearTotals(summaries)
        #expect(totals.billedMinor == 360_000)
        #expect(totals.receivedMinor == 240_000)
    }

    @Test func fifoCoverageMarksOldestSessionsFirst() throws {
        let context = try makeInMemoryContext()
        let patient = makePatient(context: context)
        let first = addSession(context, patient: patient, on: date(2026, 6, 1), status: .completed)
        let second = addSession(context, patient: patient, on: date(2026, 6, 8), status: .completed)
        context.insert(Payment(date: date(2026, 6, 9), amountMinor: 150_000, source: .manual, patient: patient))

        let covered = Ledger.coveredSessions(sessions: patient.sessions, payments: patient.payments, asOf: asOf)
        #expect(covered.contains(ObjectIdentifier(first)))
        #expect(!covered.contains(ObjectIdentifier(second)))
    }
}
