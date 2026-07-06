import Foundation
import SwiftData

/// Links a payment to a patient and, optionally, remembers the payer so
/// future and pending transfers from the same sender match automatically.
enum PaymentLinker {
    static func link(
        _ payment: Payment,
        to patient: Patient,
        rememberPayer: Bool,
        context: ModelContext
    ) {
        payment.patient = patient
        guard rememberPayer else {
            try? context.save()
            return
        }

        var newAliases: [PayerAlias] = []
        if let iban = payment.senderIban, !iban.isEmpty,
           !aliasExists(matching: iban, kind: .iban, for: patient) {
            newAliases.append(PayerAlias(matchText: iban, kind: .iban, patient: patient))
        }
        if let name = payment.senderName, !name.isEmpty,
           !aliasExists(matching: name, kind: .senderName, for: patient) {
            newAliases.append(PayerAlias(matchText: name, kind: .senderName, patient: patient))
        }
        for alias in newAliases {
            context.insert(alias)
        }
        relinkPendingPayments(with: newAliases, context: context)
        try? context.save()
    }

    private static func aliasExists(matching text: String, kind: AliasKind, for patient: Patient) -> Bool {
        patient.aliases.contains { alias in
            guard alias.kind == kind else { return false }
            return switch kind {
            case .iban: PaymentMatcher.normalizeIban(alias.matchText) == PaymentMatcher.normalizeIban(text)
            case .senderName: PaymentMatcher.normalizeName(alias.matchText) == PaymentMatcher.normalizeName(text)
            }
        }
    }

    /// Applies just-confirmed aliases to other unlinked payments. Only ever
    /// *fills* a missing link — existing links are never overwritten or
    /// cleared. Unlinked payments are filtered in memory: a nil comparison
    /// on a SwiftData relationship inside #Predicate is unreliable, and a
    /// wrong fetch here would corrupt existing links.
    private static func relinkPendingPayments(with aliases: [PayerAlias], context: ModelContext) {
        guard !aliases.isEmpty else { return }
        let allPayments = (try? context.fetch(FetchDescriptor<Payment>())) ?? []
        for other in allPayments where other.patient == nil {
            if let match = PaymentMatcher.match(
                senderName: other.senderName,
                senderIban: other.senderIban,
                description: other.comment,
                aliases: aliases
            ) {
                other.patient = match
            }
        }
    }
}
