import Foundation

nonisolated struct PlannedSession {
    let patient: Patient
    let slot: RecurringSlot
    let date: Date
    let durationMinutes: Int
    let feeMinor: Int
}

/// Turns recurring slots into concrete upcoming sessions.
/// A slot occurrence is skipped when the patient already has a session that
/// calendar day — including a session that was rescheduled *away* from that
/// day (its `previousDates` still claim the day), so regeneration never
/// resurrects a moved session.
nonisolated enum ScheduleGenerator {
    /// Rolling window of pre-created sessions; refilled to a full year every
    /// time the app becomes active, so yearly planning always has concrete
    /// sessions to look at.
    static let defaultHorizonDays = 365

    static func nextDates(
        for slot: RecurringSlot,
        from start: Date,
        horizonDays: Int = defaultHorizonDays,
        calendar: Calendar = .current
    ) -> [Date] {
        guard let end = calendar.date(byAdding: .day, value: horizonDays, to: start) else { return [] }
        // A series begins at its anchor (the first session it was created
        // with) — never back-fill occurrences before it.
        let start = max(start, slot.anchorDate ?? start)
        switch slot.frequency {
        case .daily:
            return matchingDates(
                after: start, until: end, calendar: calendar,
                matching: DateComponents(hour: slot.hour, minute: slot.minute)
            )
        case .weekly:
            return matchingDates(
                after: start, until: end, calendar: calendar,
                matching: DateComponents(hour: slot.hour, minute: slot.minute, weekday: slot.weekday)
            )
        case .biweekly:
            let weekly = matchingDates(
                after: start, until: end, calendar: calendar,
                matching: DateComponents(hour: slot.hour, minute: slot.minute, weekday: slot.weekday)
            )
            return weekly.filter { isOnAnchorFortnight($0, anchor: slot.biweeklyAnchor, calendar: calendar) }
        case .monthly:
            // Months without the requested day (e.g. day 31 in June) are skipped.
            return matchingDates(
                after: start, until: end, calendar: calendar,
                matching: DateComponents(day: slot.dayOfMonth, hour: slot.hour, minute: slot.minute)
            )
        }
    }

    private static func matchingDates(
        after start: Date,
        until end: Date,
        calendar: Calendar,
        matching components: DateComponents
    ) -> [Date] {
        var dates: [Date] = []
        var cursor = start
        while let next = calendar.nextDate(
            after: cursor,
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents
        ), next <= end {
            dates.append(next)
            cursor = next
        }
        return dates
    }

    /// True when `date` falls in a week with an even number of weeks between
    /// it and the anchor's week — keeps biweekly slots on a stable fortnight.
    private static func isOnAnchorFortnight(_ date: Date, anchor: Date, calendar: Calendar) -> Bool {
        guard
            let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start,
            let dateWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start
        else { return true }
        let weeks = Int((dateWeek.timeIntervalSince(anchorWeek) / 604_800).rounded())
        return weeks.isMultiple(of: 2)
    }

    static func plan(
        slots: [RecurringSlot],
        existingSessions: [TherapySession],
        from start: Date = .now,
        horizonDays: Int = defaultHorizonDays,
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
            let skipped = Set(slot.skippedDays.map { calendar.startOfDay(for: $0) })
            for date in nextDates(for: slot, from: start, horizonDays: horizonDays, calendar: calendar) {
                let day = calendar.startOfDay(for: date)
                guard !skipped.contains(day) else { continue }
                guard occupiedDays[key]?.contains(day) != true else { continue }
                occupiedDays[key, default: []].insert(day)
                planned.append(PlannedSession(
                    patient: patient,
                    slot: slot,
                    date: date,
                    durationMinutes: slot.durationMinutes,
                    feeMinor: patient.sessionFeeMinor
                ))
            }
        }
        return planned
    }
}
