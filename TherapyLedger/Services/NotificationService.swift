import Foundation
import SwiftData
import UserNotifications

nonisolated enum ReminderStyle: String, CaseIterable, Identifiable {
    case dailySummary
    case afterEachSession
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dailySummary: "Daily summary"
        case .afterEachSession: "After each session"
        case .both: "Both"
        }
    }

    var includesDaily: Bool { self != .afterEachSession }
    var includesPerSession: Bool { self != .dailySummary }
}

/// Schedules local "review your sessions" reminders. Notification texts never
/// include patient names — they are visible on the lock screen.
enum NotificationService {
    static let dailyReminderId = "review-daily"
    static let sessionReminderPrefix = "review-session-"
    /// iOS caps pending local notifications at 64 per app.
    static let maxSessionReminders = 40

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Rebuilds all pending reminders from current settings and schedule.
    /// Safe to call often; it replaces only this app's review reminders.
    static func refresh(context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter {
            $0 == dailyReminderId || $0.hasPrefix(sessionReminderPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKeys.remindersEnabled) else { return }
        let style = ReminderStyle(rawValue: defaults.string(forKey: SettingsKeys.reminderStyle) ?? "") ?? .dailySummary

        if style.includesDaily {
            let hour = defaults.object(forKey: SettingsKeys.reminderDailyHour) as? Int ?? 20
            let minute = defaults.object(forKey: SettingsKeys.reminderDailyMinute) as? Int ?? 0
            let content = UNMutableNotificationContent()
            content.title = "Session review"
            content.body = "Check today's sessions — mark them completed, missed or rescheduled."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: minute),
                repeats: true
            )
            try? await center.add(UNNotificationRequest(identifier: dailyReminderId, content: content, trigger: trigger))
        }

        if style.includesPerSession {
            let delayMinutes = defaults.object(forKey: SettingsKeys.reminderSessionDelayMinutes) as? Int ?? 10
            let scheduledRaw = SessionStatus.scheduled.rawValue
            let descriptor = FetchDescriptor<TherapySession>(
                predicate: #Predicate { $0.statusRaw == scheduledRaw },
                sortBy: [SortDescriptor(\.scheduledAt)]
            )
            let upcoming = ((try? context.fetch(descriptor)) ?? [])
                .filter { $0.endDate > now }
                .prefix(maxSessionReminders)

            for (index, session) in upcoming.enumerated() {
                let fireDate = session.endDate.addingTimeInterval(TimeInterval(delayMinutes * 60))
                guard fireDate > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Session ended"
                content.body = "Did the \(session.scheduledAt.formatted(date: .omitted, time: .shortened)) session happen? Mark its status."
                content.sound = .default
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(sessionReminderPrefix)\(index)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }
    }
}
