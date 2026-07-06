import Foundation
import SwiftData

/// A weekly recurring session slot, e.g. "Tuesdays at 15:00".
/// Slots are materialized into individual `TherapySession`s a few weeks ahead.
@Model
final class RecurringSlot {
    /// `Calendar` weekday component: 1 = Sunday … 7 = Saturday.
    var weekday: Int = 2
    var hour: Int = 10
    var minute: Int = 0
    var durationMinutes: Int = 50
    var isActive: Bool = true
    var createdAt: Date = Date()
    var patient: Patient?

    init(weekday: Int, hour: Int, minute: Int, durationMinutes: Int = 50, patient: Patient?) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.durationMinutes = durationMinutes
        self.patient = patient
        self.createdAt = Date()
    }

    var weekdayName: String {
        let symbols = Calendar.current.weekdaySymbols
        guard (1...symbols.count).contains(weekday) else { return "?" }
        return symbols[weekday - 1]
    }

    var timeLabel: String {
        String(format: "%02d:%02d", hour, minute)
    }
}
