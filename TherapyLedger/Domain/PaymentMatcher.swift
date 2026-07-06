import Foundation

/// Matches an incoming bank transfer to a patient using confirmed payer aliases.
/// IBAN matches are exact; name matches compare normalized text, because
/// Monobank p2p transfers carry the sender as "Від: Ім'я Прізвище" in the
/// description or as `counterName` for IBAN transfers.
nonisolated enum PaymentMatcher {
    static func normalizeName(_ text: String) -> String {
        var result = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["від:", "from:"] where result.hasPrefix(prefix) {
            result = String(result.dropFirst(prefix.count))
        }
        return result
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func normalizeIban(_ text: String) -> String {
        text.uppercased().replacingOccurrences(of: " ", with: "")
    }

    static func match(
        senderName: String?,
        senderIban: String?,
        description: String?,
        aliases: [PayerAlias]
    ) -> Patient? {
        if let iban = senderIban, !iban.isEmpty {
            let normalized = normalizeIban(iban)
            if let alias = aliases.first(where: { $0.kind == .iban && normalizeIban($0.matchText) == normalized }) {
                return alias.patient
            }
        }

        let candidates = [senderName, description]
            .compactMap { $0 }
            .map(normalizeName)
            .filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return nil }

        for alias in aliases where alias.kind == .senderName {
            let aliasText = normalizeName(alias.matchText)
            guard !aliasText.isEmpty else { continue }
            for candidate in candidates where candidate == aliasText || candidate.contains(aliasText) {
                return alias.patient
            }
        }
        return nil
    }
}
