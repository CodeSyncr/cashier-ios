import Foundation

/// An error from Cashier: a server answer (with its code) or a transport failure.
public enum CashierError: Error, Equatable, Sendable, LocalizedError {
    /// The server refused the request. `code` is Cashier's machine-readable
    /// reason, e.g. "invalid_receipt", "receipt_in_use", "store_not_configured".
    case server(status: Int, code: String, message: String)
    /// Cashier could not be reached.
    case network(String)
    /// The store purchase did not complete.
    case purchase(String)
    /// The configuration is unusable (no key, SDK not configured).
    case configuration(String)

    public var errorDescription: String? {
        switch self {
        case let .server(status, code, message): return "Cashier \(status) \(code): \(message)"
        case let .network(m), let .purchase(m), let .configuration(m): return m
        }
    }

    /// True when retrying later may succeed (the purchase is kept unfinished
    /// so StoreKit redelivers it).
    public var isTransient: Bool {
        switch self {
        case .network: return true
        case let .server(status, _, _): return status >= 500 || status == 429
        default: return false
        }
    }
}

/// One store receipt as the API takes it.
struct ReceiptPayload: Encodable {
    let platform = "apple"
    let token: String
    let renewalInfo: String?
    let productID: String?

    enum CodingKeys: String, CodingKey { case platform, token, renewalInfo = "renewal_info", productID = "product_id" }
}

/// POST /paywalls/events.
struct PaywallEventBody: Encodable, Equatable {
    let appUserID: String
    let paywallID: Int
    /// "view" | "close"
    let type: String
    let experimentID: Int?
    let variant: String?

    enum CodingKeys: String, CodingKey {
        case appUserID = "app_user_id", paywallID = "paywall_id", type, experimentID = "experiment_id", variant
    }
}

/// POST /paywalls/responses.
struct PaywallResponseBody: Encodable, Equatable {
    let appUserID: String
    let paywallID: Int
    let screenID: String
    let question: String
    let answer: String

    enum CodingKeys: String, CodingKey {
        case appUserID = "app_user_id", paywallID = "paywall_id", screenID = "screen_id", question, answer
    }
}

private struct APIFailure: Decodable {
    let error: String?
    let message: String?
}

/// Thin client over /api/cashier/v1.
final class Backend: @unchecked Sendable {
    let apiKey: String
    let baseURL: URL
    let session: URLSession

    init(apiKey: String, baseURL: URL, session: URLSession) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    func customerInfo(_ appUserID: String) async throws -> CustomerInfo {
        try await request("GET", "subscribers/\(escape(appUserID))")
    }

    func offerings(appUserID: String?) async throws -> OfferingsResponse {
        guard let appUserID, !appUserID.isEmpty else { return try await request("GET", "offerings") }
        return try await request("GET", "offerings?app_user_id=\(escapeQuery(appUserID))")
    }

    /// POST /paywalls/events: a paywall was shown ("view") or dismissed
    /// without a purchase ("close"). 204.
    func paywallEvent(_ body: PaywallEventBody) async throws {
        try await send("POST", "paywalls/events", body: body)
    }

    /// POST /paywalls/responses: an answer tapped on a paywall screen. 204.
    func paywallResponse(_ body: PaywallResponseBody) async throws {
        try await send("POST", "paywalls/responses", body: body)
    }

    func paywallPreview(token: String) async throws -> OfferingsResponse {
        try await request("GET", "paywalls/preview/\(escape(token))")
    }

    func postReceipt(appUserID: String, receipt: ReceiptPayload) async throws -> CustomerInfo {
        struct Body: Encodable {
            let appUserID: String
            let platform: String
            let token: String
            let renewalInfo: String?
            let productID: String?
            enum CodingKeys: String, CodingKey {
                case appUserID = "app_user_id", platform, token, renewalInfo = "renewal_info", productID = "product_id"
            }
        }
        struct Answer: Decodable { let subscriber: CustomerInfo }
        let body = Body(appUserID: appUserID, platform: receipt.platform, token: receipt.token,
                        renewalInfo: receipt.renewalInfo, productID: receipt.productID)
        let answer: Answer = try await request("POST", "receipts", body: body)
        return answer.subscriber
    }

    func restore(appUserID: String, receipts: [ReceiptPayload]) async throws -> CustomerInfo {
        struct Body: Encodable { let receipts: [ReceiptPayload] }
        struct Answer: Decodable { let subscriber: CustomerInfo }
        let answer: Answer = try await request("POST", "subscribers/\(escape(appUserID))/restore", body: Body(receipts: receipts))
        return answer.subscriber
    }

    func logIn(from current: String, to newID: String) async throws -> CustomerInfo {
        struct Body: Encodable {
            let newAppUserID: String
            enum CodingKeys: String, CodingKey { case newAppUserID = "new_app_user_id" }
        }
        return try await request("POST", "subscribers/\(escape(current))/alias", body: Body(newAppUserID: newID))
    }

    // MARK: - Transport

    private func escape(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func escapeQuery(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private struct Empty: Encodable {}
    private struct Ignored: Decodable {}

    /// A request whose answer (often 204, no body) is not read.
    private func send<B: Encodable>(_ method: String, _ path: String, body: B) async throws {
        let _: Ignored? = try await request(method, path, body: body, decode: false)
    }

    private func request<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        try await request(method, path, body: Optional<Empty>.none)
    }

    private func request<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> T {
        guard let value: T = try await request(method, path, body: body, decode: true) else {
            throw CashierError.server(status: 0, code: "bad_response", message: "Cashier sent no response")
        }
        return value
    }

    private func request<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?, decode: Bool) async throws -> T? {
        guard let url = URL(string: "api/cashier/v1/" + path, relativeTo: baseURL) else {
            throw CashierError.configuration("Cashier: bad URL for \(path)")
        }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("NimbusCashier-iOS/\(Cashier.version)", forHTTPHeaderField: "User-Agent")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CashierError.network("Cashier could not be reached: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let f = try? JSONDecoder().decode(APIFailure.self, from: data)
            throw CashierError.server(status: status, code: f?.error ?? "http_\(status)", message: f?.message ?? "")
        }
        guard decode else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CashierError.server(status: status, code: "bad_response", message: "Cashier sent a response this SDK cannot read: \(error)")
        }
    }
}
