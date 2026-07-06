import Foundation
import SwiftData

struct SyncResult {
    var imported = 0
    var matched = 0
    var skipped = 0

    var summary: String {
        if imported == 0 {
            return "No new incoming payments."
        }
        let unmatched = imported - matched
        var parts = ["\(imported) new payment\(imported == 1 ? "" : "s")"]
        if unmatched > 0 {
            parts.append("\(unmatched) need\(unmatched == 1 ? "s" : "") linking")
        }
        return parts.joined(separator: ", ")
    }

    mutating func merge(_ other: SyncResult) {
        imported += other.imported
        matched += other.matched
        skipped += other.skipped
    }
}

/// Pulls incoming transfers from the linked Monobank account, deduplicates by
/// transaction id, and links each payment to a patient via confirmed payer
/// aliases. Unmatched payments land in the "needs linking" inbox.
enum MonobankSyncService {
    /// Stay just under the API's 31 days + 1 hour statement window limit.
    private nonisolated static let statementWindow: TimeInterval = 31 * 86_400 - 3_600

    static func sync(
        context: ModelContext,
        token: String,
        accountId: String,
        accountLabel: String? = nil,
        now: Date = .now
    ) async throws -> SyncResult {
        let client = MonobankClient(token: token)
        let from = now.addingTimeInterval(-(31 * 86_400 - 60))
        let items = try await client.statement(accountId: accountId, from: from, to: now)
        return try importItems(items, context: context, accountId: accountId, accountLabel: accountLabel)
    }

    /// Loads up to a year of past transactions for statistics, one 31-day
    /// window at a time (the API allows 1 request/minute). Progress is
    /// persisted after every window, so an interrupted run resumes where it
    /// stopped instead of starting over.
    static func backfillYearHistory(
        context: ModelContext,
        token: String,
        accountId: String,
        accountLabel: String? = nil,
        now: Date = .now,
        progress: (Int, Int) -> Void = { _, _ in }
    ) async throws -> SyncResult {
        let client = MonobankClient(token: token)
        let defaults = UserDefaults.standard
        let savedOldest = defaults.double(forKey: SettingsKeys.monobankHistoryOldest)
        let coveredUntil = savedOldest > 0 ? Date(timeIntervalSince1970: savedOldest) : nil
        let windows = backfillWindows(coveredUntil: coveredUntil, now: now)

        var total = SyncResult()
        for (index, window) in windows.enumerated() {
            progress(index + 1, windows.count)
            let items = try await statementWithRetry(
                client: client, accountId: accountId, from: window.from, to: window.to
            )
            total.merge(try importItems(items, context: context, accountId: accountId, accountLabel: accountLabel))
            defaults.set(window.from.timeIntervalSince1970, forKey: SettingsKeys.monobankHistoryOldest)
            if index < windows.count - 1 {
                try await Task.sleep(for: .seconds(61))
            }
        }
        return total
    }

    /// Consecutive statement windows from just below the regular sync range
    /// back to one year before `now`. Empty when the year is already covered.
    nonisolated static func backfillWindows(
        coveredUntil: Date?,
        now: Date
    ) -> [(from: Date, to: Date)] {
        let oldestTarget = now.addingTimeInterval(-365 * 86_400)
        var upper = coveredUntil ?? now.addingTimeInterval(-(31 * 86_400 - 60))
        var windows: [(from: Date, to: Date)] = []
        while upper > oldestTarget {
            let lower = max(oldestTarget, upper.addingTimeInterval(-statementWindow))
            windows.append((from: lower, to: upper))
            upper = lower
        }
        return windows
    }

    private static func statementWithRetry(
        client: MonobankClient,
        accountId: String,
        from: Date,
        to: Date,
        attempts: Int = 3
    ) async throws -> [MonoStatementItem] {
        for attempt in 1...attempts {
            do {
                return try await client.statement(accountId: accountId, from: from, to: to)
            } catch MonobankError.rateLimited where attempt < attempts {
                try await Task.sleep(for: .seconds(61))
            }
        }
        throw MonobankError.rateLimited
    }

    private static func importItems(
        _ items: [MonoStatementItem],
        context: ModelContext,
        accountId: String,
        accountLabel: String?
    ) throws -> SyncResult {
        let existingMono = try context.fetch(
            FetchDescriptor<Payment>(predicate: #Predicate { $0.monoId != nil })
        )
        let existingIds = Set(existingMono.compactMap(\.monoId))
        let aliases = try context.fetch(FetchDescriptor<PayerAlias>())

        var result = SyncResult()
        for item in items where item.isIncoming {
            if existingIds.contains(item.id) {
                result.skipped += 1
                continue
            }
            let patient = PaymentMatcher.match(
                senderName: item.counterName,
                senderIban: item.counterIban,
                description: item.description,
                aliases: aliases
            )
            let payment = Payment(
                date: item.date,
                amountMinor: item.amount,
                currencyCode: CurrencyCodeMap.iso(item.currencyCode ?? 980),
                source: .monobank,
                monoId: item.id,
                senderName: item.counterName ?? senderFromDescription(item.description),
                senderIban: item.counterIban,
                comment: item.comment,
                patient: patient,
                accountId: accountId,
                accountLabel: accountLabel
            )
            context.insert(payment)
            result.imported += 1
            if patient != nil {
                result.matched += 1
            }
        }
        try context.save()
        return result
    }

    /// Incoming p2p transfers describe the sender as "Від: Ім'я Прізвище".
    static func senderFromDescription(_ description: String?) -> String? {
        guard let description, !description.isEmpty else { return nil }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Від: ", "Від:", "From: ", "From:"] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}
