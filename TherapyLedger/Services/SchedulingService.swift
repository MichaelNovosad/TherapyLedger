import Foundation
import SwiftData

/// Keeps the calendar populated by materializing recurring slots into
/// concrete sessions a few weeks ahead. Safe to call repeatedly.
enum SchedulingService {
    static func materializeUpcomingSessions(
        context: ModelContext,
        horizonDays: Int = ScheduleGenerator.defaultHorizonDays,
        now: Date = .now
    ) {
        do {
            let slots = try context.fetch(FetchDescriptor<RecurringSlot>())
            guard !slots.isEmpty else { return }
            let sessions = try context.fetch(FetchDescriptor<TherapySession>())
            let planned = ScheduleGenerator.plan(
                slots: slots,
                existingSessions: sessions,
                from: now,
                horizonDays: horizonDays
            )
            guard !planned.isEmpty else { return }
            for plan in planned {
                context.insert(TherapySession(
                    patient: plan.patient,
                    scheduledAt: plan.date,
                    durationMinutes: plan.durationMinutes,
                    feeMinor: plan.feeMinor,
                    slot: plan.slot
                ))
            }
            try context.save()
        } catch {
            assertionFailure("Schedule materialization failed: \(error)")
        }
    }

    /// Deletes this and all future *scheduled* sessions of the series and
    /// pauses the originating slot so they are not regenerated. Completed,
    /// missed, and cancelled sessions are history and stay untouched.
    /// Sessions created before slot linking existed (v1) fall back to the
    /// patient's whole schedule.
    static func endSeries(after session: TherapySession, context: ModelContext) {
        let start = session.scheduledAt
        var targets: [TherapySession]
        if let slot = session.slot {
            targets = slot.sessions.filter { $0.status == .scheduled && $0.scheduledAt >= start }
            slot.isActive = false
        } else if let patient = session.patient {
            targets = patient.sessions.filter { $0.status == .scheduled && $0.scheduledAt >= start }
            for slot in patient.slots {
                slot.isActive = false
            }
        } else {
            targets = [session]
        }
        if session.status == .scheduled && !targets.contains(where: { $0 === session }) {
            targets.append(session)
        }
        for target in targets {
            context.delete(target)
        }
        try? context.save()
    }

    /// Creates a recurring series starting at a concrete first session —
    /// the Calendar-page way of setting up recurrence. The slot's rhythm
    /// (weekday, time, day-of-month, biweekly phase) derives from `firstDate`.
    @discardableResult
    static func createSeries(
        patient: Patient,
        firstDate: Date,
        durationMinutes: Int,
        feeMinor: Int,
        frequency: SlotFrequency,
        context: ModelContext,
        horizonDays: Int = ScheduleGenerator.defaultHorizonDays,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RecurringSlot {
        let components = calendar.dateComponents([.weekday, .day, .hour, .minute], from: firstDate)
        let slot = RecurringSlot(
            weekday: components.weekday ?? 2,
            hour: components.hour ?? 10,
            minute: components.minute ?? 0,
            durationMinutes: durationMinutes,
            patient: patient,
            frequency: frequency,
            anchorDate: firstDate,
            dayOfMonth: components.day ?? 1
        )
        context.insert(slot)
        // The schedule is future-only: the explicit first session is created
        // only when it falls on today or a later day.
        if firstDate >= calendar.startOfDay(for: now) {
            context.insert(TherapySession(
                patient: patient,
                scheduledAt: firstDate,
                durationMinutes: durationMinutes,
                feeMinor: feeMinor,
                slot: slot
            ))
        }
        try? context.save()
        materializeUpcomingSessions(context: context, horizonDays: horizonDays, now: now)
        return slot
    }

    /// Changes a patient's fee and propagates it to their future scheduled
    /// slot-generated sessions, which snapshot the fee at creation time.
    /// Manually added sessions keep their custom fee; past sessions and
    /// settled statuses are never rewritten.
    static func updateFee(for patient: Patient, to newFeeMinor: Int, now: Date = .now) {
        patient.sessionFeeMinor = newFeeMinor
        for session in patient.sessions
        where session.status == .scheduled && session.scheduledAt > now && session.slot != nil {
            session.feeMinor = newFeeMinor
        }
    }

    /// Removes a single occurrence while the series continues: the day is
    /// recorded on the slot so regeneration never brings the session back.
    /// Sessions without a slot link (v1 data) record the skip on all of the
    /// patient's slots.
    static func skipOccurrence(
        of session: TherapySession,
        context: ModelContext,
        calendar: Calendar = .current
    ) {
        let day = calendar.startOfDay(for: session.scheduledAt)
        if let slot = session.slot {
            slot.skippedDays.append(day)
        } else if let patient = session.patient {
            for slot in patient.slots {
                slot.skippedDays.append(day)
            }
        }
        context.delete(session)
        try? context.save()
    }

    /// Deletes a session; future scheduled occurrences are removed via
    /// `skipOccurrence` so the series does not recreate them.
    static func delete(
        session: TherapySession,
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        if session.status == .scheduled && session.scheduledAt >= calendar.startOfDay(for: now) {
            skipOccurrence(of: session, context: context, calendar: calendar)
        } else {
            context.delete(session)
            try? context.save()
        }
    }

    /// Deletes a slot together with its future scheduled sessions.
    static func delete(slot: RecurringSlot, context: ModelContext, now: Date = .now) {
        for session in slot.sessions where session.status == .scheduled && session.scheduledAt >= now {
            context.delete(session)
        }
        context.delete(slot)
        try? context.save()
    }

    /// Marks scheduled sessions as completed once their own end time has
    /// passed — but only sessions scheduled at or after `start`, the moment
    /// the toggle was switched on. A session never completes early: its
    /// `endDate` (start + duration) must be in the past.
    @discardableResult
    static func autoCompleteEndedSessions(context: ModelContext, start: Date, now: Date = .now) -> Int {
        guard let sessions = try? context.fetch(FetchDescriptor<TherapySession>()) else { return 0 }
        var changed = 0
        for session in sessions
        where session.status == .scheduled
            && session.scheduledAt >= start
            && session.endDate <= now {
            session.status = .completed
            changed += 1
        }
        if changed > 0 {
            try? context.save()
        }
        return changed
    }

    /// Applies auto-complete when the toggle is on. The start date is set
    /// automatically at the moment of enabling — nothing older is touched.
    static func autoCompleteIfEnabled(context: ModelContext, now: Date = .now) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKeys.autoCompleteEnabled) else { return }
        let startStamp = defaults.double(forKey: SettingsKeys.autoCompleteStart)
        guard startStamp > 0 else { return }
        autoCompleteEndedSessions(context: context, start: Date(timeIntervalSince1970: startStamp), now: now)
    }
}

enum SettingsKeys {
    static let autoCompleteEnabled = "sessions.autoCompleteEnabled"
    /// Set automatically when the toggle turns on; sessions before it are never auto-completed.
    static let autoCompleteStart = "sessions.autoCompleteStart"
    /// Oldest date already covered by the transaction-history backfill.
    static let monobankHistoryOldest = "monobank.historyOldestLoaded"
    static let remindersEnabled = "reminders.enabled"
    static let reminderStyle = "reminders.style"
    static let reminderDailyHour = "reminders.dailyHour"
    static let reminderDailyMinute = "reminders.dailyMinute"
    static let reminderSessionDelayMinutes = "reminders.sessionDelayMinutes"
}
