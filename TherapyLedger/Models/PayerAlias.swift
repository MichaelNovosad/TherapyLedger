import Foundation
import SwiftData

nonisolated enum AliasKind: String, Codable {
    case senderName
    case iban
}

/// Links a bank payer identity (sender name or IBAN) to a patient so future
/// incoming transfers are matched automatically.
@Model
final class PayerAlias {
    var matchText: String = ""
    var kindRaw: String = AliasKind.senderName.rawValue
    var createdAt: Date = Date()
    var patient: Patient?

    init(matchText: String, kind: AliasKind, patient: Patient?) {
        self.matchText = matchText
        self.kindRaw = kind.rawValue
        self.patient = patient
        self.createdAt = Date()
    }

    var kind: AliasKind {
        get { AliasKind(rawValue: kindRaw) ?? .senderName }
        set { kindRaw = newValue.rawValue }
    }
}
