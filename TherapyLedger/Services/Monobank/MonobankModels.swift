import Foundation

nonisolated enum CurrencyCodeMap {
    /// ISO 4217 numeric → alphabetic code for currencies Monobank commonly returns.
    static func iso(_ numeric: Int) -> String {
        switch numeric {
        case 980: "UAH"
        case 840: "USD"
        case 978: "EUR"
        case 985: "PLN"
        case 826: "GBP"
        case 756: "CHF"
        case 203: "CZK"
        default: "UAH"
        }
    }
}

nonisolated struct MonoAccount: Decodable, Identifiable, Hashable {
    let id: String
    let balance: Int
    let currencyCode: Int
    let maskedPan: [String]?
    let iban: String?
    let type: String?

    var currency: String { CurrencyCodeMap.iso(currencyCode) }

    var displayName: String {
        if let pan = maskedPan?.first, !pan.isEmpty {
            return pan
        }
        if let iban, !iban.isEmpty {
            return iban
        }
        return id
    }

    var label: String {
        let typePart = type.map { "\($0) " } ?? ""
        return "\(typePart)\(currency) — \(displayName)"
    }
}

nonisolated struct MonoClientInfo: Decodable {
    let clientId: String
    let name: String
    let accounts: [MonoAccount]
}

nonisolated struct MonoStatementItem: Decodable, Identifiable {
    let id: String
    let time: Int
    let description: String?
    let amount: Int
    let operationAmount: Int?
    let currencyCode: Int?
    let balance: Int?
    let comment: String?
    let counterName: String?
    let counterIban: String?
    let mcc: Int?
    let hold: Bool?

    var date: Date { Date(timeIntervalSince1970: TimeInterval(time)) }
    var isIncoming: Bool { amount > 0 }
}
