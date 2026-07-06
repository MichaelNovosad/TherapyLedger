import Foundation
import SwiftData

@Model
final class Patient {
    var name: String = ""
    var sessionFeeMinor: Int = 0
    var currencyCode: String = "UAH"
    /// Whether a missed (no-show / late cancellation) session is still billed.
    var chargesForMissedSessions: Bool = false
    var notes: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TherapySession.patient)
    var sessions: [TherapySession] = []

    @Relationship(deleteRule: .nullify, inverse: \Payment.patient)
    var payments: [Payment] = []

    @Relationship(deleteRule: .cascade, inverse: \PayerAlias.patient)
    var aliases: [PayerAlias] = []

    @Relationship(deleteRule: .cascade, inverse: \RecurringSlot.patient)
    var slots: [RecurringSlot] = []

    init(
        name: String,
        sessionFeeMinor: Int,
        currencyCode: String = "UAH",
        chargesForMissedSessions: Bool = false,
        notes: String = ""
    ) {
        self.name = name
        self.sessionFeeMinor = sessionFeeMinor
        self.currencyCode = currencyCode
        self.chargesForMissedSessions = chargesForMissedSessions
        self.notes = notes
        self.createdAt = Date()
    }

    var balance: PatientBalance {
        Ledger.balance(sessions: sessions, payments: payments)
    }
}
