import Foundation
import SwiftData

nonisolated enum SessionStatus: String, Codable, CaseIterable, Identifiable {
    case scheduled
    case completed
    case missed
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scheduled: "Scheduled"
        case .completed: "Completed"
        case .missed: "Missed"
        case .cancelled: "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .scheduled: "clock"
        case .completed: "checkmark.circle.fill"
        case .missed: "person.fill.xmark"
        case .cancelled: "xmark.circle"
        }
    }
}

@Model
final class TherapySession {
    var scheduledAt: Date = Date()
    var durationMinutes: Int = 50
    var feeMinor: Int = 0
    var statusRaw: String = SessionStatus.scheduled.rawValue
    var notes: String = ""
    /// Dates this session previously occupied; non-empty means it was rescheduled.
    var previousDates: [Date] = []
    var createdAt: Date = Date()
    var patient: Patient?
    /// The recurring slot that generated this session, if any (v2, additive).
    var slot: RecurringSlot?

    init(patient: Patient?, scheduledAt: Date, durationMinutes: Int = 50, feeMinor: Int, slot: RecurringSlot? = nil) {
        self.patient = patient
        self.scheduledAt = scheduledAt
        self.durationMinutes = durationMinutes
        self.feeMinor = feeMinor
        self.createdAt = Date()
        self.slot = slot
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    var endDate: Date {
        scheduledAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    var wasRescheduled: Bool {
        !previousDates.isEmpty
    }

    var isBillable: Bool {
        switch status {
        case .completed: true
        case .missed: patient?.chargesForMissedSessions ?? false
        case .scheduled, .cancelled: false
        }
    }

    func reschedule(to newDate: Date) {
        previousDates.append(scheduledAt)
        scheduledAt = newDate
        status = .scheduled
    }
}
