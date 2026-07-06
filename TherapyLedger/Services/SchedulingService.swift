import Foundation
import SwiftData

/// Keeps the calendar populated by materializing recurring slots into
/// concrete sessions a few weeks ahead. Safe to call repeatedly.
enum SchedulingService {
    static func materializeUpcomingSessions(
        context: ModelContext,
        weeksAhead: Int = 4,
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
                weeksAhead: weeksAhead
            )
            guard !planned.isEmpty else { return }
            for plan in planned {
                context.insert(TherapySession(
                    patient: plan.patient,
                    scheduledAt: plan.date,
                    durationMinutes: plan.durationMinutes,
                    feeMinor: plan.feeMinor
                ))
            }
            try context.save()
        } catch {
            assertionFailure("Schedule materialization failed: \(error)")
        }
    }
}
