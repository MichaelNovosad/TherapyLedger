import Foundation

nonisolated struct NBURate: Decodable {
    let rate: Double
    let cc: String
}

/// Historical daily UAH exchange rates from the National Bank of Ukraine's
/// free open API. Each (currency, day) pair is fetched once and cached in
/// UserDefaults, so conversions work offline afterwards.
enum ExchangeRateService {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// Official UAH per 1 unit of `currency` on the given day.
    static func rate(currency: String, on day: Date) async throws -> Decimal {
        let dayString = dayFormatter.string(from: day)
        let cacheKey = "fx.\(currency).\(dayString)"
        if let cached = UserDefaults.standard.object(forKey: cacheKey) as? Double {
            return Decimal(cached)
        }

        guard let url = URL(string:
            "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?valcode=\(currency)&date=\(dayString)&json"
        ) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let rate = try JSONDecoder().decode([NBURate].self, from: data).first?.rate, rate > 0 else {
            throw URLError(.cannotParseResponse)
        }
        UserDefaults.standard.set(rate, forKey: cacheKey)
        return Decimal(rate)
    }

    /// Converts UAH minor units to the target currency's minor units at the
    /// given rate (UAH per 1 unit of target).
    nonisolated static func convert(minorUAH: Int, rate: Decimal) -> Int {
        guard rate > 0 else { return 0 }
        var value = Decimal(minorUAH) / rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
