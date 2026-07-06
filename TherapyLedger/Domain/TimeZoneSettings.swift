import Foundation

/// Dual time-zone display for the schedule. Both zones are user-selected;
/// Ukraine is the default.
nonisolated enum TimeZoneSettings {
    static let dualEnabledKey = "tz.dualEnabled"
    static let primaryKey = "tz.primary"
    static let secondaryKey = "tz.secondary"
    static let defaultIdentifier = "Europe/Kyiv"

    static func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier)
            ?? TimeZone(identifier: "Europe/Kiev")
            ?? .current
    }

    /// "Europe/Kyiv" → "Kyiv".
    static func cityName(_ identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    static func timeLabel(_ date: Date, in identifier: String) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone(identifier)).hour().minute())
    }

    /// "15:00 Kyiv · 14:00 Warsaw"
    static func dualLabel(_ date: Date, primary: String, secondary: String) -> String {
        let first = "\(timeLabel(date, in: primary)) \(cityName(primary))"
        guard secondary != primary else { return first }
        return "\(first) · \(timeLabel(date, in: secondary)) \(cityName(secondary))"
    }
}
