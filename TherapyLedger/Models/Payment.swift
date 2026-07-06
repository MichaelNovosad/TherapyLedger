import Foundation
import SwiftData

nonisolated enum PaymentSource: String, Codable {
    case manual
    case monobank

    var label: String {
        switch self {
        case .manual: "Manual"
        case .monobank: "Monobank"
        }
    }
}

@Model
final class Payment {
    var date: Date = Date()
    var amountMinor: Int = 0
    var currencyCode: String = "UAH"
    var sourceRaw: String = PaymentSource.manual.rawValue
    /// Monobank transaction id, used to deduplicate on sync.
    var monoId: String?
    var senderName: String?
    var senderIban: String?
    var comment: String?
    var createdAt: Date = Date()
    var patient: Patient?
    /// Which Monobank account received this payment (v2, additive).
    var accountId: String?
    var accountLabel: String?

    init(
        date: Date,
        amountMinor: Int,
        currencyCode: String = "UAH",
        source: PaymentSource,
        monoId: String? = nil,
        senderName: String? = nil,
        senderIban: String? = nil,
        comment: String? = nil,
        patient: Patient? = nil,
        accountId: String? = nil,
        accountLabel: String? = nil
    ) {
        self.date = date
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.sourceRaw = source.rawValue
        self.monoId = monoId
        self.senderName = senderName
        self.senderIban = senderIban
        self.comment = comment
        self.patient = patient
        self.createdAt = Date()
        self.accountId = accountId
        self.accountLabel = accountLabel
    }

    var source: PaymentSource {
        get { PaymentSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var isLinked: Bool { patient != nil }

    var senderSummary: String {
        senderName ?? comment ?? "Unknown payer"
    }
}
