import XCTest
@testable import NimbusCashier

/// Answers requests from a table: "METHOD path" → (status, JSON body).
final class MockAPI: URLProtocol {
    nonisolated(unsafe) static var routes: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = "\(request.httpMethod ?? "GET") \(request.url!.path)"
        MockAPI.requests.append(request)
        if let stream = request.httpBodyStream {
            stream.open(); var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            MockAPI.bodies[key] = data
        }
        let (status, body) = MockAPI.routes[key] ?? (404, #"{"error":"not_found","message":"no route \#(key)"}"#)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class NimbusCashierTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        MockAPI.routes = [:]; MockAPI.requests = []; MockAPI.bodies = [:]
        defaults = UserDefaults(suiteName: "cashier-tests-\(UUID().uuidString)")
    }

    func makeCashier(appUserID: String? = nil) -> Cashier {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAPI.self]
        return Cashier(apiKey: "cshr_pub_test", appUserID: appUserID, baseURL: URL(string: "https://cashier.test/")!,
                       session: URLSession(configuration: config), userDefaults: defaults, observeTransactions: false)
    }

    static func subscriber(_ id: String, premium: Bool) -> String {
        """
        {"subject":"\(id)","requested_at":"2026-09-27T09:57:08.80715+05:30",
         "entitlements":{"premium":{"id":"premium","active":\(premium),"will_renew":true,"period_type":"trial",
           "product_id":"pro_monthly","source":"purchase","expires_at":"2026-10-27T04:27:08.296621Z"}},
         "active_entitlement_ids":\(premium ? #"["premium"]"# : "[]"),"active_product_ids":[],
         "latest_expires_at":"0001-01-01T00:00:00Z"}
        """
    }

    func testDecodesCustomerInfoAndDates() throws {
        let info = try JSONDecoder().decode(CustomerInfo.self, from: Data(Self.subscriber("u1", premium: true).utf8))
        XCTAssertEqual(info.appUserID, "u1")
        XCTAssertTrue(info.isEntitled(to: "premium"))
        XCTAssertFalse(info.isEntitled(to: "gold"))
        let prem = try XCTUnwrap(info.entitlements["premium"])
        XCTAssertEqual(prem.periodType, .trial)
        XCTAssertEqual(prem.productIdentifier, "pro_monthly")
        // Microsecond precision and a non-UTC offset both parse.
        XCTAssertEqual(prem.expirationDate?.timeIntervalSince1970 ?? 0, 1_793_075_228.296, accuracy: 0.001)
        XCTAssertNotNil(info.requestDate)
        // Go's zero time is "never", not year one.
        XCTAssertNil(info.latestExpirationDate)
    }

    func testDateParsing() {
        XCTAssertNotNil(CashierDate.parse("2026-10-04T09:57:08+05:30"))
        XCTAssertNotNil(CashierDate.parse("2026-10-04T09:57:08.1Z"))
        XCTAssertEqual(CashierDate.parse("2026-10-04T09:57:08.123456789Z")?.timeIntervalSince1970 ?? 0,
                       CashierDate.parse("2026-10-04T09:57:08.123Z")?.timeIntervalSince1970 ?? 1, accuracy: 0.001)
        XCTAssertNil(CashierDate.parse(""))
    }

    func testAppAccountTokenIsStable() {
        let a = Identity.appAccountToken(for: "user_42")
        XCTAssertEqual(a, Identity.appAccountToken(for: "user_42"))
        XCTAssertNotEqual(a, Identity.appAccountToken(for: "user_43"))
        XCTAssertEqual(a.uuidString, "7D6D0177-C9A5-551E-9AE4-DD553EC57E2D", "RFC 4122 v5 — every Cashier SDK derives the same token")
        let uuid = UUID()
        XCTAssertEqual(Identity.appAccountToken(for: uuid.uuidString), uuid, "a UUID user id is used as-is")
    }

    func testAnonymousIdPersistsUntilLogIn() async throws {
        let c = makeCashier()
        XCTAssertTrue(c.isAnonymous)
        let anon = c.appUserID
        XCTAssertEqual(makeCashier().appUserID, anon, "the anonymous id survives relaunch")

        MockAPI.routes["POST /api/cashier/v1/subscribers/\(anon)/alias"] = (200, Self.subscriber("user_7", premium: true))
        let info = try await c.logIn("user_7")
        XCTAssertEqual(info.appUserID, "user_7")
        XCTAssertEqual(c.appUserID, "user_7")
        XCTAssertEqual(c.cachedCustomerInfo?.appUserID, "user_7")
        let body = try JSONSerialization.jsonObject(with: MockAPI.bodies["POST /api/cashier/v1/subscribers/\(anon)/alias"] ?? Data()) as? [String: String]
        XCTAssertEqual(body?["new_app_user_id"], "user_7")
        XCTAssertEqual(makeCashier().appUserID, "user_7", "the identified user survives relaunch")
    }

    func testCustomerInfoIsCachedAndAuthenticated() async throws {
        let c = makeCashier(appUserID: "user_1")
        MockAPI.routes["GET /api/cashier/v1/subscribers/user_1"] = (200, Self.subscriber("user_1", premium: true))
        _ = try await c.customerInfo()
        _ = try await c.customerInfo()
        XCTAssertEqual(MockAPI.requests.count, 1, "the second read is served from cache")
        XCTAssertEqual(MockAPI.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer cshr_pub_test")
        _ = try await c.customerInfo(fetchPolicy: .fetchCurrent)
        XCTAssertEqual(MockAPI.requests.count, 2)
    }

    func testStreamDeliversUpdates() async throws {
        let c = makeCashier(appUserID: "user_1")
        MockAPI.routes["GET /api/cashier/v1/subscribers/user_1"] = (200, Self.subscriber("user_1", premium: true))
        var it = c.customerInfoStream.makeAsyncIterator()
        _ = try await c.customerInfo()
        let got = await it.next()
        XCTAssertEqual(got?.appUserID, "user_1")
    }

    func testReceiptPostAndServerErrors() async throws {
        let c = makeCashier(appUserID: "user_1")
        let backend = Backend(apiKey: "cshr_pub_test", baseURL: URL(string: "https://cashier.test/")!,
                              session: { let s = URLSessionConfiguration.ephemeral; s.protocolClasses = [MockAPI.self]; return URLSession(configuration: s) }())
        MockAPI.routes["POST /api/cashier/v1/receipts"] = (200, #"{"subscriber":\#(Self.subscriber("user_1", premium: true))}"#)
        let info = try await backend.postReceipt(appUserID: "user_1", receipt: ReceiptPayload(token: "jws", renewalInfo: "rjws", productID: "com.app.monthly"))
        XCTAssertTrue(info.isEntitled(to: "premium"))
        let sent = try JSONSerialization.jsonObject(with: MockAPI.bodies["POST /api/cashier/v1/receipts"] ?? Data()) as? [String: Any]
        XCTAssertEqual(sent?["platform"] as? String, "apple")
        XCTAssertEqual(sent?["app_user_id"] as? String, "user_1")
        XCTAssertEqual(sent?["renewal_info"] as? String, "rjws")

        MockAPI.routes["POST /api/cashier/v1/receipts"] = (422, #"{"error":"invalid_receipt","message":"bad signature"}"#)
        do {
            _ = try await backend.postReceipt(appUserID: "user_1", receipt: ReceiptPayload(token: "x", renewalInfo: nil, productID: nil))
            XCTFail("expected an error")
        } catch let CashierError.server(status, code, _) {
            XCTAssertEqual(status, 422); XCTAssertEqual(code, "invalid_receipt")
            XCTAssertFalse(CashierError.server(status: status, code: code, message: "").isTransient)
        }
        XCTAssertTrue(CashierError.server(status: 503, code: "retry", message: "").isTransient)
        _ = c
    }

    func testPreviewOfferingCarriesTheDraft() async throws {
        let c = makeCashier(appUserID: "user_1")
        let fixture = try String(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "paywalls", withExtension: "json", subdirectory: "Fixtures")), encoding: .utf8)
        let classic = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [String: Any])["classic"]!
        let doc = String(data: try JSONSerialization.data(withJSONObject: classic), encoding: .utf8)!
        MockAPI.routes["GET /api/cashier/v1/paywalls/preview/pvw_abc"] = (200, #"{"current_offering":"launch","app_name":"Acme","offerings":[{"id":"launch","packages":[],"paywall":"# + doc + "}]}")
        let offering = try await c.previewOffering(token: "pvw_abc")
        XCTAssertEqual(offering.identifier, "launch")
        XCTAssertEqual(offering.appName, "Acme")
        XCTAssertNotNil(offering.paywall)
        MockAPI.routes["GET /api/cashier/v1/paywalls/preview/pvw_gone"] = (404, #"{"error":"not_found","message":"No paywall preview for that token."}"#)
        do { _ = try await c.previewOffering(token: "pvw_gone"); XCTFail("expected an error") } catch let CashierError.server(status, _, _) { XCTAssertEqual(status, 404) }
    }

    func testOfferingsWithoutAppStoreProductsAreEmpty() async throws {
        let c = makeCashier(appUserID: "user_1")
        MockAPI.routes["GET /api/cashier/v1/offerings"] = (200, """
        {"current_offering":"launch","offerings":[{"id":"launch","packages":[
          {"id":"$monthly","product":{"id":"pro_monthly","name":"Pro","amount":499,"currency":"USD","period_months":1,"entitlements":["premium"]}}]}]}
        """)
        let offerings = try await c.offerings()
        XCTAssertEqual(offerings.current?.identifier, "launch")
        XCTAssertEqual(offerings.current?.availablePackages.count, 0, "a product with no App Store id cannot be sold on iOS")
    }
}
