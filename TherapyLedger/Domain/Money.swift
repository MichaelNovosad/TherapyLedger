import Foundation

/// Amounts are stored as integer minor units (kopiykas) to avoid floating-point drift.
nonisolated enum Money {
    static func format(_ minor: Int, currency: String = "UAH") -> String {
        let amount = Decimal(minor) / 100
        return amount.formatted(.currency(code: currency).presentation(.narrow))
    }

    static func minorUnits(from major: Decimal) -> Int {
        var value = major * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func major(from minor: Int) -> Decimal {
        Decimal(minor) / 100
    }
}
