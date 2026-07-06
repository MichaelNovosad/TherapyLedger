import Foundation
import SwiftData

nonisolated enum SlotFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        }
    }
}

/// A recurring session slot, e.g. "Tuesdays at 15:00" or "the 5th of every month".
/// Slots are materialized into individual `TherapySession`s a few weeks ahead.
///
/// v2 fields (`frequencyRaw`, `anchorDate`, `dayOfMonth`) are additive with
/// safe defaults so v1 stores migrate untouched: existing slots stay weekly.
@Model
final class RecurringSlot {
    /// `Calendar` weekday component: 1 = Sunday … 7 = Saturday. Used by weekly/biweekly.
    var weekday: Int = 2
    var hour: Int = 10
    var minute: Int = 0
    var durationMinutes: Int = 50
    var isActive: Bool = true
    var createdAt: Date = Date()
    var patient: Patient?

    var frequencyRaw: String = "weekly"
    /// Phase reference for biweekly slots; falls back to `createdAt` when nil (migrated v1 rows).
    var anchorDate: Date?
    /// Day of month for monthly slots (1…31).
    var dayOfMonth: Int = 1
    /// Days (start-of-day) the user removed a single occurrence from the
    /// series; generation never recreates a session on these days.
    var skippedDays: [Date] = []

    @Relationship(deleteRule: .nullify, inverse: \TherapySession.slot)
    var sessions: [TherapySession] = []

    init(
        weekday: Int,
        hour: Int,
        minute: Int,
        durationMinutes: Int = 50,
        patient: Patient?,
        frequency: SlotFrequency = .weekly,
        anchorDate: Date? = nil,
        dayOfMonth: Int = 1
    ) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.durationMinutes = durationMinutes
        self.patient = patient
        self.createdAt = Date()
        self.frequencyRaw = frequency.rawValue
        self.anchorDate = anchorDate
        self.dayOfMonth = dayOfMonth
    }

    var frequency: SlotFrequency {
        get { SlotFrequency(rawValue: frequencyRaw) ?? .weekly }
        set { frequencyRaw = newValue.rawValue }
    }

    var biweeklyAnchor: Date { anchorDate ?? createdAt }

    var weekdayName: String {
        let symbols = Calendar.current.weekdaySymbols
        guard (1...symbols.count).contains(weekday) else { return "?" }
        return symbols[weekday - 1]
    }

    var timeLabel: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var scheduleLabel: String {
        switch frequency {
        case .daily: "Daily \(timeLabel)"
        case .weekly: "\(weekdayName) \(timeLabel)"
        case .biweekly: "\(weekdayName) \(timeLabel), every 2 weeks"
        case .monthly: "Day \(dayOfMonth) of each month, \(timeLabel)"
        }
    }
}
