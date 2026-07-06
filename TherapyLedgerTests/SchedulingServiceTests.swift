import Foundation
import Testing
import SwiftData
@testable import TherapyLedger

struct SchedulingServiceTests {
    @Test func autoCompleteStartsFromActivationAndRespectsSessionEndTime() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)

        // Toggle switched on 2026-07-06; "now" is 12:00 the same day.
        let activation = date(2026, 7, 6, 0)
        let now = date(2026, 7, 6, 12)

        let beforeActivation = TherapySession(patient: patient, scheduledAt: date(2026, 6, 10, 10), feeMinor: 100_000)
        let endedToday = TherapySession(patient: patient, scheduledAt: date(2026, 7, 6, 10), feeMinor: 100_000)
        // Started 11:30, ends 12:20 — still in progress at 12:00.
        let inProgress = TherapySession(patient: patient, scheduledAt: date(2026, 7, 6, 11, 30), feeMinor: 100_000)
        let future = TherapySession(patient: patient, scheduledAt: date(2026, 7, 8, 10), feeMinor: 100_000)
        let missed = TherapySession(patient: patient, scheduledAt: date(2026, 7, 6, 8), feeMinor: 100_000)
        missed.status = .missed
        for session in [beforeActivation, endedToday, inProgress, future, missed] {
            context.insert(session)
        }

        let changed = SchedulingService.autoCompleteEndedSessions(context: context, start: activation, now: now)

        #expect(changed == 1)
        #expect(endedToday.status == .completed)
        // Sessions before the activation date are never touched.
        #expect(beforeActivation.status == .scheduled)
        // A session completes only after its own end time has passed.
        #expect(inProgress.status == .scheduled)
        #expect(future.status == .scheduled)
        // Manually set statuses stay.
        #expect(missed.status == .missed)
    }

    @Test func endSeriesDeletesFutureScheduledAndPausesSlot() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(weekday: 3, hour: 15, minute: 0, patient: patient)
        context.insert(slot)

        let past = TherapySession(patient: patient, scheduledAt: date(2026, 6, 2, 15), feeMinor: 100_000, slot: slot)
        past.status = .completed
        let current = TherapySession(patient: patient, scheduledAt: date(2026, 6, 9, 15), feeMinor: 100_000, slot: slot)
        let future = TherapySession(patient: patient, scheduledAt: date(2026, 6, 16, 15), feeMinor: 100_000, slot: slot)
        context.insert(past)
        context.insert(current)
        context.insert(future)
        try context.save()

        SchedulingService.endSeries(after: current, context: context)

        let remaining = try context.fetch(FetchDescriptor<TherapySession>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.status == .completed)
        #expect(slot.isActive == false)
    }

    @Test func createSeriesBuildsSlotFromFirstSessionAndMaterializes() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 120_000)
        context.insert(patient)

        // Tuesday Jun 2 at 15:00, weekly, "now" pinned to Jun 1, 28-day window.
        let slot = SchedulingService.createSeries(
            patient: patient,
            firstDate: date(2026, 6, 2, 15),
            durationMinutes: 50,
            feeMinor: 120_000,
            frequency: .weekly,
            context: context,
            horizonDays: 28,
            now: date(2026, 6, 1)
        )

        #expect(slot.weekday == 3)
        #expect(slot.hour == 15)
        let sessions = try context.fetch(FetchDescriptor<TherapySession>())
            .sorted { $0.scheduledAt < $1.scheduledAt }
        // First session + generated Jun 9/16/23 within the 28-day horizon, no duplicate on Jun 2.
        #expect(sessions.map(\.scheduledAt) == [
            date(2026, 6, 2, 15), date(2026, 6, 9, 15), date(2026, 6, 16, 15), date(2026, 6, 23, 15)
        ])
        #expect(sessions.allSatisfy { $0.slot === slot })
    }

    @Test func seriesStartingWeeksAheadStillCreatesFullYearCycle() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 120_000)
        context.insert(patient)

        // First session is over a month away; with the default one-year
        // window the whole cycle must exist, not just the first session.
        let slot = SchedulingService.createSeries(
            patient: patient,
            firstDate: date(2026, 8, 6, 15),
            durationMinutes: 50,
            feeMinor: 120_000,
            frequency: .weekly,
            context: context,
            now: date(2026, 7, 6)
        )

        let sessions = try context.fetch(FetchDescriptor<TherapySession>())
            .sorted { $0.scheduledAt < $1.scheduledAt }
        #expect(sessions.first?.scheduledAt == date(2026, 8, 6, 15))
        // Roughly weekly occurrences from Aug 6 to next July.
        #expect(sessions.count >= 40)
        #expect(sessions.allSatisfy { $0.slot === slot })
    }

    @Test func feeChangePropagatesOnlyToFutureGeneratedSessions() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(weekday: 3, hour: 15, minute: 0, patient: patient)
        context.insert(slot)

        let pastCompleted = TherapySession(patient: patient, scheduledAt: date(2026, 6, 2, 15), feeMinor: 100_000, slot: slot)
        pastCompleted.status = .completed
        let futureGenerated = TherapySession(patient: patient, scheduledAt: date(2026, 7, 14, 15), feeMinor: 100_000, slot: slot)
        let futureManual = TherapySession(patient: patient, scheduledAt: date(2026, 7, 20, 15), feeMinor: 80_000)
        for session in [pastCompleted, futureGenerated, futureManual] {
            context.insert(session)
        }

        SchedulingService.updateFee(for: patient, to: 130_000, now: date(2026, 7, 6))

        #expect(patient.sessionFeeMinor == 130_000)
        #expect(futureGenerated.feeMinor == 130_000)
        // Billing history and custom-priced manual sessions stay as they were.
        #expect(pastCompleted.feeMinor == 100_000)
        #expect(futureManual.feeMinor == 80_000)
    }

    @Test func seriesWithPastFirstDateCreatesNoPastSessions() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)

        // First date a month in the past; "now" is Jul 6. The schedule is
        // future-only: no session may exist before today.
        SchedulingService.createSeries(
            patient: patient,
            firstDate: date(2026, 6, 2, 15),
            durationMinutes: 50,
            feeMinor: 100_000,
            frequency: .weekly,
            context: context,
            horizonDays: 28,
            now: date(2026, 7, 6)
        )

        let sessions = try context.fetch(FetchDescriptor<TherapySession>())
            .sorted { $0.scheduledAt < $1.scheduledAt }
        let today = Calendar.current.startOfDay(for: date(2026, 7, 6))
        #expect(!sessions.isEmpty)
        #expect(sessions.allSatisfy { $0.scheduledAt >= today })
        // The rhythm continues on the same weekday: next Tuesday, Jul 7.
        #expect(sessions.first?.scheduledAt == date(2026, 7, 7, 15))
    }

    @Test func backfillWindowsCoverOneYearWithoutGaps() {
        let now = date(2026, 7, 6)
        let windows = MonobankSyncService.backfillWindows(coveredUntil: nil, now: now)

        #expect(!windows.isEmpty)
        // Starts just below the regular sync range, ends a year back.
        #expect(windows.first?.to == now.addingTimeInterval(-(31 * 86_400 - 60)))
        #expect(windows.last?.from == now.addingTimeInterval(-365 * 86_400))
        for window in windows {
            // Every window fits the API's 31-day + 1-hour limit.
            #expect(window.to.timeIntervalSince(window.from) <= 31 * 86_400 + 3_600)
        }
        // Consecutive windows are contiguous — no gaps, no overlaps.
        for index in 0..<(windows.count - 1) {
            #expect(windows[index].from == windows[index + 1].to)
        }

        // Fully covered year → nothing left to fetch.
        let done = MonobankSyncService.backfillWindows(
            coveredUntil: now.addingTimeInterval(-365 * 86_400),
            now: now
        )
        #expect(done.isEmpty)
    }

    @Test func skippedOccurrenceIsDeletedAndNeverRegenerated() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(weekday: 3, hour: 15, minute: 0, patient: patient)
        context.insert(slot)
        let keep = TherapySession(patient: patient, scheduledAt: date(2026, 6, 2, 15), feeMinor: 100_000, slot: slot)
        let skip = TherapySession(patient: patient, scheduledAt: date(2026, 6, 9, 15), feeMinor: 100_000, slot: slot)
        context.insert(keep)
        context.insert(skip)
        try context.save()

        SchedulingService.skipOccurrence(of: skip, context: context)

        let remaining = try context.fetch(FetchDescriptor<TherapySession>())
        #expect(remaining.count == 1)
        #expect(slot.skippedDays.count == 1)

        // Regeneration must not bring Jun 9 back; Jun 16 is still planned.
        let planned = ScheduleGenerator.plan(
            slots: [slot],
            existingSessions: remaining,
            from: date(2026, 6, 1),
            horizonDays: 16
        )
        #expect(planned.map(\.date) == [date(2026, 6, 16, 15)])
    }

    @Test func deletingFutureScheduledSessionRecordsSkip() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(weekday: 3, hour: 15, minute: 0, patient: patient)
        context.insert(slot)
        let future = TherapySession(patient: patient, scheduledAt: date(2026, 6, 9, 15), feeMinor: 100_000, slot: slot)
        let past = TherapySession(patient: patient, scheduledAt: date(2026, 5, 26, 15), feeMinor: 100_000, slot: slot)
        past.status = .completed
        context.insert(future)
        context.insert(past)
        try context.save()

        SchedulingService.delete(session: future, context: context, now: date(2026, 6, 1))
        SchedulingService.delete(session: past, context: context, now: date(2026, 6, 1))

        #expect(try context.fetch(FetchDescriptor<TherapySession>()).isEmpty)
        // Only the future scheduled one records a skip; deleting history doesn't.
        #expect(slot.skippedDays == [Calendar.current.startOfDay(for: date(2026, 6, 9, 15))])
    }

    @Test func deletingSlotRemovesItsFutureSessionsButKeepsHistory() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(weekday: 3, hour: 15, minute: 0, patient: patient)
        context.insert(slot)

        let past = TherapySession(patient: patient, scheduledAt: date(2026, 6, 2, 15), feeMinor: 100_000, slot: slot)
        past.status = .missed
        let future = TherapySession(patient: patient, scheduledAt: date(2026, 6, 16, 15), feeMinor: 100_000, slot: slot)
        context.insert(past)
        context.insert(future)
        try context.save()

        SchedulingService.delete(slot: slot, context: context, now: date(2026, 6, 10))

        let remainingSessions = try context.fetch(FetchDescriptor<TherapySession>())
        let remainingSlots = try context.fetch(FetchDescriptor<RecurringSlot>())
        #expect(remainingSessions.count == 1)
        #expect(remainingSessions.first?.status == .missed)
        #expect(remainingSlots.isEmpty)
    }
}
