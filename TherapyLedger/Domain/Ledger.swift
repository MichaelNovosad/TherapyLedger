import Foundation
import SwiftData

nonisolated struct PatientBalance {
    var billedMinor: Int
    var paidMinor: Int

    /// Money the patient still owes.
    var debtMinor: Int { max(0, billedMinor - paidMinor) }
    /// Money paid ahead of billed sessions.
    var creditMinor: Int { max(0, paidMinor - billedMinor) }
    var isSettled: Bool { billedMinor == paidMinor }
}

nonisolated struct MonthSummary: Identifiable {
    let year: Int
    let month: Int
    var billedMinor: Int = 0
    var receivedMinor: Int = 0
    var completedCount: Int = 0
    var missedCount: Int = 0

    var id: Int { year * 100 + month }

    var monthName: String {
        Calendar.current.monthSymbols[month - 1]
    }
}

/// Pure bookkeeping rules. A session is billed once it is billable
/// (completed, or missed for patients charged for missed sessions) and its
/// date is in the past. Debt is billed minus received — no per-session
/// paid flag to maintain.
nonisolated enum Ledger {
    static func balance(sessions: [TherapySession], payments: [Payment], asOf: Date = .now) -> PatientBalance {
        let billed = sessions
            .filter { $0.isBillable && $0.scheduledAt <= asOf }
            .reduce(0) { $0 + $1.feeMinor }
        let paid = payments.reduce(0) { $0 + $1.amountMinor }
        return PatientBalance(billedMinor: billed, paidMinor: paid)
    }

    static func monthlySummaries(
        sessions: [TherapySession],
        payments: [Payment],
        year: Int,
        asOf: Date = .now,
        calendar: Calendar = .current
    ) -> [MonthSummary] {
        var byMonth: [Int: MonthSummary] = [:]
        for month in 1...12 {
            byMonth[month] = MonthSummary(year: year, month: month)
        }

        for session in sessions where session.scheduledAt <= asOf {
            let components = calendar.dateComponents([.year, .month], from: session.scheduledAt)
            guard components.year == year, let month = components.month else { continue }
            if session.isBillable {
                byMonth[month]?.billedMinor += session.feeMinor
            }
            switch session.status {
            case .completed: byMonth[month]?.completedCount += 1
            case .missed: byMonth[month]?.missedCount += 1
            case .scheduled, .cancelled: break
            }
        }

        for payment in payments {
            let components = calendar.dateComponents([.year, .month], from: payment.date)
            guard components.year == year, let month = components.month else { continue }
            byMonth[month]?.receivedMinor += payment.amountMinor
        }

        return (1...12).compactMap { byMonth[$0] }
    }

    static func yearTotals(_ summaries: [MonthSummary]) -> (billedMinor: Int, receivedMinor: Int) {
        (
            summaries.reduce(0) { $0 + $1.billedMinor },
            summaries.reduce(0) { $0 + $1.receivedMinor }
        )
    }

    /// FIFO coverage: total payments are applied to billable sessions oldest
    /// first. A session is "covered" (paid for) if the running payment total
    /// reaches its fee. Used to show a paid checkmark per session.
    static func coveredSessions(sessions: [TherapySession], payments: [Payment], asOf: Date = .now) -> Set<ObjectIdentifier> {
        var remaining = payments.reduce(0) { $0 + $1.amountMinor }
        var covered: Set<ObjectIdentifier> = []
        let billable = sessions
            .filter { $0.isBillable && $0.scheduledAt <= asOf }
            .sorted { $0.scheduledAt < $1.scheduledAt }
        for session in billable {
            guard remaining >= session.feeMinor else { break }
            remaining -= session.feeMinor
            covered.insert(ObjectIdentifier(session))
        }
        return covered
    }
}
