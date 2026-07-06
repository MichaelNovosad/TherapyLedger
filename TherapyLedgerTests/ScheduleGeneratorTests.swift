import Foundation
import Testing
import SwiftData
@testable import TherapyLedger

struct ScheduleGeneratorTests {
    // Monday 2026-06-01 12:00.
    let start = date(2026, 6, 1)

    @Test func nextDatesFallOnRequestedWeekdayAndTime() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        // Tuesday (weekday 3) at 15:00.
        let slot = RecurringSlot(weekday: 3, hour: 15, minute: 0, patient: patient)
        context.insert(slot)

        let dates = ScheduleGenerator.nextDates(for: slot, from: start, horizonDays: 21)
        #expect(dates.count == 3)
        let calendar = Calendar.current
        for slotDate in dates {
            #expect(calendar.component(.weekday, from: slotDate) == 3)
            #expect(calendar.component(.hour, from: slotDate) == 15)
        }
        #expect(dates[0] == date(2026, 6, 2, 15))
        #expect(dates[1] == date(2026, 6, 9, 15))
    }

    @Test func dailySlotGeneratesEveryDay() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(weekday: 1, hour: 9, minute: 0, patient: patient, frequency: .daily)
        context.insert(slot)

        let dates = ScheduleGenerator.nextDates(for: slot, from: start, horizonDays: 5)
        #expect(dates.count == 5)
        #expect(dates.first == date(2026, 6, 2, 9))
        #expect(dates.last == date(2026, 6, 6, 9))
    }

    @Test func biweeklySlotSkipsAlternateWeeks() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(
            weekday: 3, hour: 15, minute: 0,
            patient: patient,
            frequency: .biweekly,
            anchorDate: start
        )
        context.insert(slot)

        let dates = ScheduleGenerator.nextDates(for: slot, from: start, horizonDays: 28)
        #expect(dates == [date(2026, 6, 2, 15), date(2026, 6, 16, 15)])
    }

    @Test func monthlySlotLandsOnDayOfMonth() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(
            weekday: 1, hour: 10, minute: 0,
            patient: patient,
            frequency: .monthly,
            dayOfMonth: 15
        )
        context.insert(slot)

        let dates = ScheduleGenerator.nextDates(for: slot, from: start, horizonDays: 60)
        #expect(dates == [date(2026, 6, 15, 10), date(2026, 7, 15, 10)])
    }

    @Test func planSkipsDaysWithExistingSessions() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(weekday: 3, hour: 15, minute: 0, patient: patient)
        context.insert(slot)
        // Session already exists on the first Tuesday (moved to 16:00 manually).
        let existing = TherapySession(patient: patient, scheduledAt: date(2026, 6, 2, 16), feeMinor: 100_000)
        context.insert(existing)

        let planned = ScheduleGenerator.plan(
            slots: [slot],
            existingSessions: [existing],
            from: start,
            horizonDays: 14
        )
        #expect(planned.count == 1)
        #expect(planned[0].date == date(2026, 6, 9, 15))
    }

    @Test func planDoesNotResurrectRescheduledSessions() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let slot = RecurringSlot(weekday: 3, hour: 15, minute: 0, patient: patient)
        context.insert(slot)
        // Session was on Tue Jun 2, then rescheduled to Thu Jun 4:
        // regeneration must not recreate a session on Jun 2.
        let moved = TherapySession(patient: patient, scheduledAt: date(2026, 6, 2, 15), feeMinor: 100_000)
        context.insert(moved)
        moved.reschedule(to: date(2026, 6, 4, 15))

        let planned = ScheduleGenerator.plan(
            slots: [slot],
            existingSessions: [moved],
            from: start,
            horizonDays: 14
        )
        #expect(planned.count == 1)
        #expect(planned[0].date == date(2026, 6, 9, 15))
    }

    @Test func inactiveSlotsAndArchivedPatientsAreSkipped() throws {
        let context = try makeInMemoryContext()
        let active = Patient(name: "Anna", sessionFeeMinor: 100_000)
        let archived = Patient(name: "Gone", sessionFeeMinor: 100_000)
        archived.isArchived = true
        context.insert(active)
        context.insert(archived)

        let pausedSlot = RecurringSlot(weekday: 3, hour: 15, minute: 0, patient: active)
        pausedSlot.isActive = false
        let archivedSlot = RecurringSlot(weekday: 4, hour: 15, minute: 0, patient: archived)
        context.insert(pausedSlot)
        context.insert(archivedSlot)

        let planned = ScheduleGenerator.plan(
            slots: [pausedSlot, archivedSlot],
            existingSessions: [],
            from: start,
            horizonDays: 14
        )
        #expect(planned.isEmpty)
    }

    @Test func rescheduleKeepsHistoryAndResetsStatus() throws {
        let context = try makeInMemoryContext()
        let patient = Patient(name: "Anna", sessionFeeMinor: 100_000)
        context.insert(patient)
        let session = TherapySession(patient: patient, scheduledAt: date(2026, 6, 2, 15), feeMinor: 100_000)
        context.insert(session)

        session.reschedule(to: date(2026, 6, 4, 17))
        #expect(session.wasRescheduled)
        #expect(session.previousDates == [date(2026, 6, 2, 15)])
        #expect(session.scheduledAt == date(2026, 6, 4, 17))
        #expect(session.status == .scheduled)
    }
}
