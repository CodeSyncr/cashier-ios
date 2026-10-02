import XCTest
@testable import NimbusCashier

/// Offerings experiments, paywall analytics events, answer capture and
/// localization (the shared product-gaps spec, sections 1–4).
final class PaywallGapsTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        MockAPI.routes = [:]; MockAPI.requests = []; MockAPI.bodies = [:]
        defaults = UserDefaults(suiteName: "cashier-gaps-\(UUID().uuidString)")
    }

    func makeCashier(appUserID: String? = nil) -> Cashier {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAPI.self]
        return Cashier(apiKey: "cshr_pub_test", appUserID: appUserID, baseURL: URL(string: "https://cashier.test/")!,
                       session: URLSession(configuration: config), userDefaults: defaults, observeTransactions: false)
    }

    static let theme = ##"{"background":"#FFFFFF","surface":"#EEEEEE","text":"#000000","muted":"#666666","accent":"#FF0000","accent_text":"#FFFFFF","radius":8,"font":"system"}"##

    func decode(_ json: String) throws -> PaywallDoc {
        try JSONDecoder().decode(PaywallDoc.self, from: Data(json.utf8))
    }

    func body(_ key: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(MockAPI.bodies[key])) as? [String: Any])
    }

    // MARK: - 1. Offerings

    func testOfferingsSendTheUserAndCarryPaywallIDAndExperiment() async throws {
        let c = makeCashier(appUserID: "user 1&2")
        MockAPI.routes["GET /api/cashier/v1/offerings"] = (200, """
        {"current_offering":"b","experiment":{"id":3,"variant":"b"},"offerings":[
          {"id":"a","packages":[],"paywall_id":11,"paywall":{"version":2,"theme":\(Self.theme),"screens":[]}},
          {"id":"b","packages":[],"paywall_id":12,"paywall":{"version":2,"theme":\(Self.theme),"screens":[]}},
          {"id":"c","packages":[],"paywall_id":13}]}
        """)
        let offerings = try await c.offerings()
        let url = try XCTUnwrap(MockAPI.requests.first?.url)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems, [URLQueryItem(name: "app_user_id", value: "user 1&2")])
        XCTAssertEqual(offerings.experiment, PaywallExperiment(id: 3, variant: "b"))
        XCTAssertEqual(offerings.current?.identifier, "b")
        XCTAssertEqual(offerings.current?.paywallID, 12)
        XCTAssertEqual(offerings.current?.experiment, PaywallExperiment(id: 3, variant: "b"))
        XCTAssertEqual(offerings["a"]?.paywallID, 11)
        XCTAssertNil(offerings["a"]?.experiment, "only the offering the experiment chose carries it")
        XCTAssertNil(offerings["c"]?.paywallID, "no paywall, no paywall id")
    }

    func testOfferingsWithoutExperimentOrABadOne() throws {
        let plain = try JSONDecoder().decode(OfferingsResponse.self, from: Data(#"{"current_offering":"a","offerings":[]}"#.utf8))
        XCTAssertNil(plain.experiment)
        let bad = try JSONDecoder().decode(OfferingsResponse.self, from: Data(#"{"offerings":[],"experiment":{"id":"x"}}"#.utf8))
        XCTAssertNil(bad.experiment, "an unreadable experiment never breaks offerings")
    }

    func testPreviewOfferingHasNoPaywallID() async throws {
        let c = makeCashier(appUserID: "u")
        MockAPI.routes["GET /api/cashier/v1/paywalls/preview/pvw_x"] = (200, """
        {"current_offering":"a","offerings":[{"id":"a","packages":[],"paywall_id":9,"paywall":{"version":2,"theme":\(Self.theme),"screens":[]}}]}
        """)
        let offering = try await c.previewOffering(token: "pvw_x")
        XCTAssertNil(offering.paywallID)
        MockAPI.requests = []
        await c.postPaywallEvent("view", offering: offering)
        await c.postAnswer(PaywallAnswer(screenID: "s", question: "q", answer: "a"), offering: offering)
        XCTAssertTrue(MockAPI.requests.isEmpty, "preview drafts record nothing")
    }

    // MARK: - 2. Events

    func testPaywallEventsPost() async throws {
        let c = makeCashier(appUserID: "user_1")
        MockAPI.routes["GET /api/cashier/v1/offerings"] = (200, """
        {"current_offering":"a","experiment":{"id":3,"variant":"a"},"offerings":[
          {"id":"a","packages":[],"paywall_id":12,"paywall":{"version":2,"theme":\(Self.theme),"screens":[]}},
          {"id":"b","packages":[],"paywall_id":14,"paywall":{"version":2,"theme":\(Self.theme),"screens":[]}}]}
        """)
        MockAPI.routes["POST /api/cashier/v1/paywalls/events"] = (204, "")
        let offerings = try await c.offerings()
        await c.postPaywallEvent("view", offering: try XCTUnwrap(offerings.current))
        let sent = try body("POST /api/cashier/v1/paywalls/events")
        XCTAssertEqual(sent["app_user_id"] as? String, "user_1")
        XCTAssertEqual(sent["paywall_id"] as? Int, 12)
        XCTAssertEqual(sent["type"] as? String, "view")
        XCTAssertEqual(sent["experiment_id"] as? Int, 3)
        XCTAssertEqual(sent["variant"] as? String, "a")

        await c.postPaywallEvent("close", offering: try XCTUnwrap(offerings["b"]))
        let close = try body("POST /api/cashier/v1/paywalls/events")
        XCTAssertEqual(close["type"] as? String, "close")
        XCTAssertEqual(close["paywall_id"] as? Int, 14)
        XCTAssertNil(close["experiment_id"], "no experiment, no experiment fields")
        XCTAssertNil(close["variant"])

        // Errors are swallowed.
        MockAPI.routes["POST /api/cashier/v1/paywalls/events"] = (500, #"{"error":"boom"}"#)
        await c.postPaywallEvent("view", offering: try XCTUnwrap(offerings.current))
    }

    // MARK: - 3. Answers

    func testAnswersDecodeAndPost() async throws {
        let doc = try decode("""
        {"version":2,"theme":\(Self.theme),"screens":[
          {"id":"s1","name":"Feedback","question":"How did you hear about us?","blocks":[
            {"id":"b1","type":"button","text":"A friend","action":"next","answer":"A friend told me"},
            {"id":"b2","type":"button","text":"Skip","action":"next"}]},
          {"id":"s2","name":"Consent","blocks":[{"id":"b3","type":"button","text":"Yes","action":"next","answer":" yes "}]}]}
        """)
        let s1 = doc.flow[0], s2 = doc.flow[1]
        XCTAssertEqual(s1.question, "How did you hear about us?")
        XCTAssertEqual(PaywallAnswer(block: s1.blocks[0], screen: s1), PaywallAnswer(screenID: "s1", question: "How did you hear about us?", answer: "A friend told me"))
        XCTAssertNil(PaywallAnswer(block: s1.blocks[1], screen: s1), "a button without an answer records nothing")
        XCTAssertEqual(PaywallAnswer(block: s2.blocks[0], screen: s2), PaywallAnswer(screenID: "s2", question: "Consent", answer: "yes"),
                       "the question falls back to the screen's name")

        let c = makeCashier(appUserID: "user_1")
        MockAPI.routes["GET /api/cashier/v1/offerings"] = (200, """
        {"current_offering":"a","offerings":[{"id":"a","packages":[],"paywall_id":12,"paywall":{"version":2,"theme":\(Self.theme),"screens":[]}}]}
        """)
        MockAPI.routes["POST /api/cashier/v1/paywalls/responses"] = (204, "")
        let offerings = try await c.offerings()
        let offering = try XCTUnwrap(offerings.current)
        await c.postAnswer(PaywallAnswer(screenID: "s1", question: "How did you hear about us?", answer: "A friend told me"), offering: offering)
        let sent = try body("POST /api/cashier/v1/paywalls/responses")
        XCTAssertEqual(sent as NSDictionary, [
            "app_user_id": "user_1", "paywall_id": 12, "screen_id": "s1",
            "question": "How did you hear about us?", "answer": "A friend told me",
        ] as NSDictionary)
    }

    // MARK: - 4. Localization

    static let localizable = """
    {"version":2,"theme":\(theme),"default_locale":"en","locales":["es","pt","pt-BR","en-GB"],
     "strings":{
       "es":{"t1.text":"Hazte Pro","c1.text":"Continuar","f1.items.0.title":"Sin anuncios","f1.items.1.text":"Todo, siempre",
             "s1.question":"¿Cómo nos conociste?","b1.answer":"Un amigo","b1.text":"","inner.text":"Dentro","deep.subtext":"Muy dentro",
             "p1.badges.$annual":"Ahorra {{savings}}","card.badge":"Popular ES","q1.author":"Ana","t1.subtext":"Por {{price}}"},
       "pt":{"t1.text":"Seja Pro"},
       "pt-BR":{"t1.text":"Seja Pro (BR)"},
       "en-GB":{"t1.text":"Go Pro, mate"}},
     "screens":[{"id":"s1","name":"Paywall","question":"How did you hear about us?","blocks":[
       {"id":"t1","type":"title","text":"Go Pro","subtext":"For {{price}}"},
       {"id":"f1","type":"features","items":[{"icon":"star","title":"No ads","text":"Ever"},{"icon":"star","title":"Sync","text":"Always, everything"}]},
       {"id":"p1","type":"packages","badges":{"$annual":"Save {{savings}}","$monthly":"Flexible"}},
       {"id":"q1","type":"testimonial","text":"Great","author":"Ann"},
       {"id":"b1","type":"button","text":"A friend","action":"next","answer":"A friend"},
       {"id":"box","type":"stack","children":[
         {"id":"inner","type":"text","text":"Inside"},
         {"id":"card","type":"custom","package":"$annual","badge":"Popular","children":[{"id":"deep","type":"title","text":"Deep","subtext":"Deeper"}]}]},
       {"id":"c1","type":"cta","text":"Continue"}]}]}
    """

    func title(_ doc: PaywallDoc) -> String? { doc.allBlocks.first { $0.id == "t1" }?.text }

    func testLocalizationExactMatch() throws {
        let doc = try decode(Self.localizable)
        XCTAssertEqual(doc.defaultLocale, "en")
        XCTAssertEqual(doc.locales, ["es", "pt", "pt-BR", "en-GB"])
        XCTAssertEqual(title(doc.localized(to: "es")), "Hazte Pro")
        XCTAssertEqual(title(doc.localized(to: "ES")), "Hazte Pro", "case-insensitive")
        XCTAssertEqual(title(doc.localized(to: "pt_BR")), "Seja Pro (BR)", "_ reads as -")
        XCTAssertEqual(title(doc.localized(to: "pt-br")), "Seja Pro (BR)")
        XCTAssertEqual(title(doc.localized(for: Locale(identifier: "pt_BR"))), "Seja Pro (BR)")
        XCTAssertEqual(title(doc), "Go Pro", "the original is untouched")
    }

    func testLocalizationLanguageFallback() throws {
        let doc = try decode(Self.localizable.replacingOccurrences(of: #""pt","pt-BR","#, with: #""pt","#))
        XCTAssertEqual(title(doc.localized(to: "pt-BR")), "Seja Pro", "pt-BR → pt")
        XCTAssertEqual(title(doc.localized(to: "es-MX")), "Hazte Pro", "es-MX → es")
        // The first locale of the language wins.
        let both = try decode(Self.localizable)
        XCTAssertEqual(title(both.localized(to: "pt-PT")), "Seja Pro")
    }

    func testLocalizationDefaultFallback() throws {
        let doc = try decode(Self.localizable)
        XCTAssertEqual(title(doc.localized(to: "fr-FR")), "Go Pro", "no translation: the default texts")
        XCTAssertEqual(title(doc.localized(to: "de")), "Go Pro")
        XCTAssertEqual(title(doc.localized(to: "")), "Go Pro")
        let untranslated = try decode(#"{"version":2,"theme":\#(Self.theme),"screens":[{"id":"s","name":"S","blocks":[{"id":"t1","type":"title","text":"Go Pro"}]}]}"#)
        XCTAssertEqual(title(untranslated.localized(to: "es")), "Go Pro")
        // A locale listed without strings keeps the defaults.
        let empty = try decode(#"{"version":2,"theme":\#(Self.theme),"locales":["es"],"screens":[{"id":"s","name":"S","blocks":[{"id":"t1","type":"title","text":"Go Pro"}]}]}"#)
        XCTAssertEqual(title(empty.localized(to: "es")), "Go Pro")
        // Unreadable strings never break the document.
        let bad = try decode(#"{"version":2,"theme":\#(Self.theme),"locales":["es"],"strings":{"es":42},"screens":[{"id":"s","name":"S","blocks":[{"id":"t1","type":"title","text":"Go Pro"}]}]}"#)
        XCTAssertNil(bad.strings)
        XCTAssertEqual(title(bad.localized(to: "es")), "Go Pro")
    }

    func testLocalizationSameLanguageAsDefault() throws {
        let doc = try decode(Self.localizable)
        XCTAssertEqual(title(doc.localized(to: "en-US")), "Go Pro", "the default's language without an exact match: defaults, not en-GB")
        XCTAssertEqual(title(doc.localized(to: "en")), "Go Pro")
        XCTAssertEqual(title(doc.localized(to: "en-GB")), "Go Pro, mate", "an exact match still wins")
        // An empty default_locale means "en".
        let noDefault = try decode(Self.localizable.replacingOccurrences(of: #""default_locale":"en""#, with: #""default_locale":"""#))
        XCTAssertEqual(title(noDefault.localized(to: "en-AU")), "Go Pro")
        // A non-English default.
        let spanish = try decode(Self.localizable.replacingOccurrences(of: #""default_locale":"en""#, with: #""default_locale":"es-ES""#))
        XCTAssertEqual(title(spanish.localized(to: "es-MX")), "Go Pro", "es-MX is the default's language")
        XCTAssertEqual(title(spanish.localized(to: "es")), "Hazte Pro", "…but an exact match is translated")
    }

    func testLocalizationWalksNestedChildren() throws {
        let doc = try decode(Self.localizable).localized(to: "es")
        let byID = Dictionary(uniqueKeysWithValues: doc.allBlocks.map { ($0.id, $0) })
        XCTAssertEqual(byID["inner"]?.text, "Dentro")
        XCTAssertEqual(byID["deep"]?.subtext, "Muy dentro")
        XCTAssertEqual(byID["deep"]?.text, "Deep", "missing keys keep the default")
        XCTAssertEqual(byID["card"]?.badge, "Popular ES")
        // Version 1 documents (top-level blocks) too.
        let v1 = try decode(#"{"version":1,"theme":\#(Self.theme),"locales":["es"],"strings":{"es":{"t1.text":"Hazte Pro"}},"blocks":[{"id":"box","type":"stack","children":[{"id":"t1","type":"title","text":"Go Pro"}]}]}"#)
        XCTAssertEqual(title(v1.localized(to: "es")), "Hazte Pro")
    }

    func testLocalizationKeys() throws {
        let doc = try decode(Self.localizable).localized(to: "es")
        let byID = Dictionary(uniqueKeysWithValues: doc.allBlocks.map { ($0.id, $0) })
        let items = try XCTUnwrap(byID["f1"]?.items)
        XCTAssertEqual(items.map(\.title), ["Sin anuncios", "Sync"])
        XCTAssertEqual(items.map(\.text), ["Ever", "Todo, siempre"])
        XCTAssertEqual(items.map(\.icon), ["star", "star"])
        XCTAssertEqual(byID["p1"]?.badges, ["$annual": "Ahorra {{savings}}", "$monthly": "Flexible"])
        XCTAssertEqual(byID["q1"]?.author, "Ana")
        XCTAssertEqual(byID["q1"]?.text, "Great")
        XCTAssertEqual(byID["b1"]?.answer, "Un amigo")
        XCTAssertEqual(byID["b1"]?.text, "A friend", "an empty translation keeps the default")
        XCTAssertEqual(byID["c1"]?.text, "Continuar")
        let screen = try XCTUnwrap(doc.flow.first)
        XCTAssertEqual(screen.question, "¿Cómo nos conociste?")
        XCTAssertEqual(PaywallAnswer(block: try XCTUnwrap(byID["b1"]), screen: screen),
                       PaywallAnswer(screenID: "s1", question: "¿Cómo nos conociste?", answer: "Un amigo"))
    }

    func testTemplateVariablesInsideTranslations() throws {
        let doc = try decode(Self.localizable).localized(to: "es")
        let byID = Dictionary(uniqueKeysWithValues: doc.allBlocks.map { ($0.id, $0) })
        let annual = PaywallTests.packages[1]
        XCTAssertEqual(PaywallText.resolve(try XCTUnwrap(byID["t1"]?.subtext), appName: "Acme", package: annual), "Por $39.99")
        let withSavings = PaywallPackageView(id: "$annual", productName: "Annual", price: "$39.99", period: "year",
                                             pricePerMonth: "$3.33", trial: "", savings: "33%")
        XCTAssertEqual(PaywallText.resolve(try XCTUnwrap(byID["p1"]?.badges?["$annual"]), appName: "Acme", package: withSavings), "Ahorra 33%")
    }

    /// The server's own translated document (Fixtures/paywalls.json "localized").
    func testServerLocalizedFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "paywalls", withExtension: "json", subdirectory: "Fixtures"))
        let doc = try XCTUnwrap(try JSONDecoder().decode([String: PaywallDoc].self, from: Data(contentsOf: url))["localized"])
        XCTAssertEqual(doc.defaultLocale, "en")
        XCTAssertEqual(doc.locales, ["es", "pt-BR"])
        let es = doc.localized(to: "es-419")
        let byID = Dictionary(uniqueKeysWithValues: es.allBlocks.map { ($0.id, $0) })
        XCTAssertEqual(byID["t2"]?.text, "Hazte Pro")
        XCTAssertEqual(byID["o1"]?.text, "Un amigo")
        XCTAssertEqual(byID["o1"]?.answer, "friend", "an untranslated answer keeps its default")
        XCTAssertEqual(byID["o2"]?.text, "Social media")
        XCTAssertEqual(byID["f1"]?.items?.first?.title, "Sin anuncios")
        XCTAssertEqual(byID["p1"]?.badges?["annual"], "Mejor precio")
        XCTAssertEqual(PaywallText.resolve(try XCTUnwrap(byID["c1"]?.text), appName: "", package: PaywallTests.packages[1]), "Continuar por $39.99")
        let ask = try XCTUnwrap(es.flow.first { $0.id == "ask" })
        XCTAssertEqual(PaywallAnswer(block: try XCTUnwrap(byID["o1"]), screen: ask),
                       PaywallAnswer(screenID: "ask", question: "¿Cómo nos conociste?", answer: "friend"))
        XCTAssertEqual(doc.localized(to: "pt").allBlocks.first { $0.id == "t2" }?.text, "Seja Pro", "pt → the first Portuguese locale")
        XCTAssertEqual(doc.localized(to: "en-US").allBlocks.first { $0.id == "t2" }?.text, "Go Pro")
    }

    func testLocaleMatching() {
        XCTAssertEqual(PaywallLocalization.match(requested: "zh_Hans_CN", locales: ["zh-Hans"], defaultLocale: "en"), "zh-Hans")
        XCTAssertEqual(PaywallLocalization.match(requested: "zh-Hans", locales: ["zh-hans"], defaultLocale: "en"), "zh-hans")
        XCTAssertNil(PaywallLocalization.match(requested: "en-US", locales: ["en-GB"], defaultLocale: nil))
        XCTAssertEqual(PaywallLocalization.tag(Locale(identifier: "pt_BR")), "pt-BR")
        XCTAssertEqual(PaywallLocalization.normalize("de_DE@calendar=gregorian"), "de-DE")
    }
}
