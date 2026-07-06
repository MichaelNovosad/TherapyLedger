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

    /// FIFO allocation: payments (oldest first) are applied to billable
    /// sessions (oldest first), splitting lump sums across sessions. A
    /// session's payment date is the date of the payment that covered its
    /// last kopiyka; comparing calendar weeks yields paid vs delayed. This is
    /// how one transfer equal to several session fees marks *each* of those
    /// sessions as delayed by its own number of weeks.
    static func paymentStatuses(
        sessions: [TherapySession],
        payments: [Payment],
        asOf: Date = .now,
        calendar: Calendar = .current
    ) -> [ObjectIdentifier: SessionPaymentStatus] {
        let billable = sessions
            .filter { $0.isBillable && $0.scheduledAt <= asOf }
            .sorted { $0.scheduledAt < $1.scheduledAt }
        let sortedPayments = payments.sorted { $0.date < $1.date }

        var statuses: [ObjectIdentifier: SessionPaymentStatus] = [:]
        var paymentIndex = 0
        var remainingInPayment = sortedPayments.first?.amountMinor ?? 0

        for session in billable {
            if session.feeMinor == 0 {
                statuses[ObjectIdentifier(session)] = .paid(on: session.scheduledAt)
                continue
            }
            var needed = session.feeMinor
            var coveredOn: Date?
            while needed > 0 && paymentIndex < sortedPayments.count {
                let taken = min(needed, remainingInPayment)
                needed -= taken
                remainingInPayment -= taken
                if needed == 0 {
                    coveredOn = sortedPayments[paymentIndex].date
                }
                if remainingInPayment == 0 {
                    paymentIndex += 1
                    remainingInPayment = paymentIndex < sortedPayments.count
                        ? sortedPayments[paymentIndex].amountMinor
                        : 0
                }
            }
            if let coveredOn {
                let weeksLate = weeksBetween(session.scheduledAt, and: coveredOn, calendar: calendar)
                statuses[ObjectIdentifier(session)] = weeksLate >= 1
                    ? .delayed(on: coveredOn, weeksLate: weeksLate)
                    : .paid(on: coveredOn)
            } else {
                statuses[ObjectIdentifier(session)] = .awaiting
            }
        }
        return statuses
    }

    /// Whole calendar weeks from the session's week to the payment's week;
    /// 0 for the same week, negative values (prepayment) are clamped to 0.
    private static func weeksBetween(_ sessionDate: Date, and paymentDate: Date, calendar: Calendar) -> Int {
        guard
            let sessionWeek = calendar.dateInterval(of: .weekOfYear, for: sessionDate)?.start,
            let paymentWeek = calendar.dateInterval(of: .weekOfYear, for: paymentDate)?.start
        else { return 0 }
        return max(0, Int((paymentWeek.timeIntervalSince(sessionWeek) / 604_800).rounded()))
    }

    /// Sum of payments received within the month or year containing `period`.
    static func receivedTotal(
        payments: [Payment],
        in period: Date,
        granularity: Calendar.Component,
        calendar: Calendar = .current
    ) -> Int {
        payments
            .filter { calendar.isDate($0.date, equalTo: period, toGranularity: granularity) }
            .reduce(0) { $0 + $1.amountMinor }
    }
}

nonisolated enum SessionPaymentStatus: Equatable {
    /// No payment has fully covered this session yet.
    case awaiting
    /// Covered within the session's calendar week (or prepaid).
    case paid(on: Date)
    /// Covered in a later week than the session's.
    case delayed(on: Date, weeksLate: Int)
}
