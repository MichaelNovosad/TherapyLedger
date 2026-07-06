import Foundation

enum MonobankError: LocalizedError {
    case invalidToken
    case rateLimited
    case server(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            "Monobank rejected the token. Check it at api.monobank.ua and paste it again."
        case .rateLimited:
            "Monobank allows one request per minute. Wait a moment and try again."
        case .server(let code):
            "Monobank returned an unexpected response (HTTP \(code))."
        case .decoding:
            "Could not read the Monobank response."
        }
    }
}

/// Thin client for the free personal Monobank Open API (https://api.monobank.ua).
/// Personal endpoints are rate-limited to 1 request per 60 seconds.
struct MonobankClient {
    let token: String
    var session: URLSession = .shared

    private static let baseURL = "https://api.monobank.ua/"

    func clientInfo() async throws -> MonoClientInfo {
        try await get("personal/client-info")
    }

    /// The API serves at most 31 days + 1 hour per statement request.
    func statement(accountId: String, from: Date, to: Date) async throws -> [MonoStatementItem] {
        let fromStamp = Int(from.timeIntervalSince1970)
        let toStamp = Int(to.timeIntervalSince1970)
        return try await get("personal/statement/\(accountId)/\(fromStamp)/\(toStamp)")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: Self.baseURL + path) else {
            throw MonobankError.server(0)
        }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Token")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MonobankError.server(0)
        }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw MonobankError.invalidToken
        case 429:
            throw MonobankError.rateLimited
        default:
            throw MonobankError.server(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MonobankError.decoding
        }
    }
}
