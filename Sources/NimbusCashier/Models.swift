import Foundation

// The shapes Cashier's API answers with. Dates arrive as RFC 3339 strings
// (with or without fractional seconds, any offset); Go's zero time means
// "never" and decodes as nil.

/// What a subscriber holds right now — the one object an app gates on.
public struct CustomerInfo: Decodable, Equatable, Sendable {
    /// The app user id this state belongs to (after any alias).
    public let appUserID: String
    public let requestDate: Date?
    /// Every known entitlement, active or not, keyed by identifier.
    public let entitlements: [String: EntitlementInfo]
    /// Identifiers of the entitlements granting access now.
    public let activeEntitlementIDs: [String]
    /// Cashier product ids behind the active entitlements.
    public let activeProductIDs: [String]
    /// The furthest-out expiry across active entitlements; nil when one never expires.
    public let latestExpirationDate: Date?

    /// The entitlements granting access now.
    public var activeEntitlements: [String: EntitlementInfo] { entitlements.filter { $0.value.isActive } }

    /// Whether an entitlement grants access now.
    public func isEntitled(to entitlementID: String) -> Bool { entitlements[entitlementID]?.isActive == true }

    enum CodingKeys: String, CodingKey {
        case appUserID = "subject", requestDate = "requested_at", entitlements
        case activeEntitlementIDs = "active_entitlement_ids", activeProductIDs = "active_product_ids"
        case latestExpirationDate = "latest_expires_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appUserID = try c.decode(String.self, forKey: .appUserID)
        requestDate = try c.decodeCashierDateIfPresent(forKey: .requestDate)
        entitlements = try c.decodeIfPresent([String: EntitlementInfo].self, forKey: .entitlements) ?? [:]
        activeEntitlementIDs = try c.decodeIfPresent([String].self, forKey: .activeEntitlementIDs) ?? []
        activeProductIDs = try c.decodeIfPresent([String].self, forKey: .activeProductIDs) ?? []
        latestExpirationDate = try c.decodeCashierDateIfPresent(forKey: .latestExpirationDate)
    }
}

/// One entitlement's state.
public struct EntitlementInfo: Decodable, Equatable, Sendable {
    public enum PeriodType: String, Decodable, Sendable {
        case trial, intro, normal, promotional, grace, unknown
        public init(from decoder: Decoder) throws {
            self = PeriodType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public let identifier: String
    public let isActive: Bool
    /// False once the subscriber turned off auto-renew; access still lasts to expiry.
    public let willRenew: Bool
    public let periodType: PeriodType
    /// The Cashier product that granted it (nil for a promotional grant).
    public let productIdentifier: String?
    /// "purchase" or "promotional".
    public let source: String?
    public let expirationDate: Date?

    /// Whether the entitlement is in the store's grace period after a failed renewal.
    public var isInGracePeriod: Bool { periodType == .grace }

    enum CodingKeys: String, CodingKey {
        case identifier = "id", isActive = "active", willRenew = "will_renew", periodType = "period_type"
        case productIdentifier = "product_id", source, expirationDate = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        willRenew = try c.decodeIfPresent(Bool.self, forKey: .willRenew) ?? false
        periodType = try c.decodeIfPresent(PeriodType.self, forKey: .periodType) ?? .normal
        productIdentifier = try c.decodeIfPresent(String.self, forKey: .productIdentifier)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        expirationDate = try c.decodeCashierDateIfPresent(forKey: .expirationDate)
    }
}

/// A product as configured in the Cashier console.
public struct CashierProduct: Decodable, Equatable, Sendable {
    public let identifier: String
    public let name: String
    /// The console price in the currency's smallest unit (the store charges its own price).
    public let amount: Int64
    public let currency: String
    /// Billing period in months; 0 is a one-time purchase.
    public let periodMonths: Int
    public let trialDays: Int
    public let entitlements: [String]
    public let appleProductID: String?
    public let googleProductID: String?

    enum CodingKeys: String, CodingKey {
        case identifier = "id", name, amount, currency, periodMonths = "period_months", trialDays = "trial_days"
        case entitlements, appleProductID = "apple_product_id", googleProductID = "google_product_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? identifier
        amount = try c.decodeIfPresent(Int64.self, forKey: .amount) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? ""
        periodMonths = try c.decodeIfPresent(Int.self, forKey: .periodMonths) ?? 0
        trialDays = try c.decodeIfPresent(Int.self, forKey: .trialDays) ?? 0
        entitlements = try c.decodeIfPresent([String].self, forKey: .entitlements) ?? []
        appleProductID = try c.decodeIfPresent(String.self, forKey: .appleProductID).flatMap { $0.isEmpty ? nil : $0 }
        googleProductID = try c.decodeIfPresent(String.self, forKey: .googleProductID).flatMap { $0.isEmpty ? nil : $0 }
    }
}

// Wire shapes for offerings; the public Offering/Package types (with their
// StoreKit products attached) are built from these in Cashier.swift.
struct OfferingsResponse: Decodable {
    struct WireOffering: Decodable {
        let id: String
        let description: String?
        let packages: [WirePackage]
        /// The published paywall. A document this SDK cannot read never
        /// breaks offerings; the offering simply has no paywall.
        let paywall: PaywallDoc?
        /// The published paywall's id, for analytics events and answers.
        let paywallID: Int?

        enum CodingKeys: String, CodingKey { case id, description, packages, paywall, paywallID = "paywall_id" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            description = try c.decodeIfPresent(String.self, forKey: .description)
            packages = try c.decodeIfPresent([WirePackage].self, forKey: .packages) ?? []
            paywall = try? c.decodeIfPresent(PaywallDoc.self, forKey: .paywall)
            paywallID = try? c.decodeIfPresent(Int.self, forKey: .paywallID)
        }
    }
    struct WirePackage: Decodable {
        let id: String
        let product: CashierProduct
    }
    let currentOffering: String?
    let offerings: [WireOffering]
    let appName: String?
    /// The experiment the user is enrolled in, if any (`current_offering`
    /// already reflects its variant).
    let experiment: PaywallExperiment?

    enum CodingKeys: String, CodingKey {
        case currentOffering = "current_offering", offerings, appName = "app_name", experiment
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentOffering = try c.decodeIfPresent(String.self, forKey: .currentOffering)
        offerings = try c.decode([WireOffering].self, forKey: .offerings)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        // An experiment this SDK cannot read never breaks offerings.
        experiment = try? c.decodeIfPresent(PaywallExperiment.self, forKey: .experiment)
    }
}

// MARK: - Dates

enum CashierDate {
    // ISO8601DateFormatter is thread-safe once configured, and these never change.
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Parses RFC 3339 with any number of fractional digits. Year 1 (Go's zero time) is nil.
    static func parse(_ raw: String) -> Date? {
        guard !raw.isEmpty, !raw.hasPrefix("0001-01-01") else { return nil }
        var s = raw
        // ISO8601DateFormatter accepts at most millisecond precision.
        if let dot = s.firstIndex(of: "."), let end = s[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let digits = s[s.index(after: dot)..<end]
            let ms = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            s.replaceSubrange(s.index(after: dot)..<end, with: ms)
        }
        return fractional.date(from: s) ?? plain.date(from: s)
    }
}

extension KeyedDecodingContainer {
    func decodeCashierDateIfPresent(forKey key: Key) throws -> Date? {
        guard let raw = try decodeIfPresent(String.self, forKey: key) else { return nil }
        return CashierDate.parse(raw)
    }
}
