import Foundation

nonisolated struct PlannedSession {
    let patient: Patient
    let date: Date
    let durationMinutes: Int
    let feeMinor: Int
}

/// Turns weekly recurring slots into concrete upcoming sessions.
/// A slot occurrence is skipped when the patient already has a session that
/// calendar day — including a session that was rescheduled *away* from that
/// day (its `previousDates` still claim the day), so regeneration never
/// resurrects a moved session.
nonisolated enum ScheduleGenerator {
    static func nextDates(
        for slot: RecurringSlot,
        from start: Date,
        weeksAhead: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        var components = DateComponents()
        components.weekday = slot.weekday
        components.hour = slot.hour
        components.minute = slot.minute

        var dates: [Date] = []
        var cursor = start
        while dates.count < weeksAhead {
            guard let next = calendar.nextDate(
                after: cursor,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents
            ) else { break }
            dates.append(next)
            cursor = next
        }
        return dates
    }

    static func plan(
        slots: [RecurringSlot],
        existingSessions: [TherapySession],
        from start: Date = .now,
        weeksAhead: Int = 4,
        calendar: Calendar = .current
    ) -> [PlannedSession] {
        var occupiedDays: [ObjectIdentifier: Set<Date>] = [:]
        for session in existingSessions {
            guard let patient = session.patient else { continue }
            let key = ObjectIdentifier(patient)
            occupiedDays[key, default: []].insert(calendar.startOfDay(for: session.scheduledAt))
            for previous in session.previousDates {
                occupiedDays[key, default: []].insert(calendar.startOfDay(for: previous))
            }
        }

        var planned: [PlannedSession] = []
        for slot in slots where slot.isActive {
            guard let patient = slot.patient, !patient.isArchived else { continue }
            let key = ObjectIdentifier(patient)
            for date in nextDates(for: slot, from: start, weeksAhead: weeksAhead, calendar: calendar) {
                let day = calendar.startOfDay(for: date)
                guard occupiedDays[key]?.contains(day) != true else { continue }
                occupiedDays[key, default: []].insert(day)
                planned.append(PlannedSession(
                    patient: patient,
                    date: date,
                    durationMinutes: slot.durationMinutes,
                    feeMinor: patient.sessionFeeMinor
                ))
            }
        }
        return planned
    }
}
