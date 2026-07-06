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
}

/// Pulls incoming transfers from the linked Monobank account, deduplicates by
/// transaction id, and links each payment to a patient via confirmed payer
/// aliases. Unmatched payments land in the "needs linking" inbox.
enum MonobankSyncService {
    static func sync(
        context: ModelContext,
        token: String,
        accountId: String,
        now: Date = .now
    ) async throws -> SyncResult {
        let client = MonobankClient(token: token)
        // Stay just under the API's 31 days + 1 hour window limit.
        let from = now.addingTimeInterval(-(31 * 86_400 - 60))
        let items = try await client.statement(accountId: accountId, from: from, to: now)

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
                patient: patient
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
