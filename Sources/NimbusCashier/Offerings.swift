import Foundation
import StoreKit

/// Every offering the console defines, with StoreKit products attached.
public struct Offerings: Sendable {
    /// The offering your paywall should show now.
    public let current: Offering?
    /// Every offering, keyed by identifier.
    public let all: [String: Offering]
    /// The paywall experiment (A/B test) the current user is enrolled in,
    /// if any. `current` is already the offering of their variant.
    public internal(set) var experiment: PaywallExperiment? = nil

    public subscript(identifier: String) -> Offering? { all[identifier] }
}

/// A named set of packages a paywall presents.
public struct Offering: Sendable, Identifiable {
    public let identifier: String
    public let serverDescription: String
    /// Packages whose product is on sale in the App Store, in console order.
    public let availablePackages: [Package]
    /// The paywall designed for this offering in the Cashier console, when
    /// one is published. Show it with `PaywallView(offering:)`.
    public let paywall: PaywallDoc?
    /// Your Cashier app's name, for {{app_name}} in paywall text.
    public let appName: String
    /// The published paywall's id; nil when there is none, or for a
    /// preview-token draft (whose views and answers are not recorded).
    public internal(set) var paywallID: Int? = nil
    /// The experiment this offering was chosen by: set on the current
    /// offering while the user is enrolled in one, nil otherwise.
    public internal(set) var experiment: PaywallExperiment? = nil

    public var id: String { identifier }

    public func package(identifier: String) -> Package? { availablePackages.first { $0.identifier == identifier } }
    public var monthly: Package? { package(identifier: "$monthly") }
    public var annual: Package? { package(identifier: "$annual") }
    public var sixMonth: Package? { package(identifier: "$six_month") }
    public var threeMonth: Package? { package(identifier: "$three_month") }
    public var twoMonth: Package? { package(identifier: "$two_month") }
    public var weekly: Package? { package(identifier: "$weekly") }
    public var lifetime: Package? { package(identifier: "$lifetime") }
}

/// A paywall experiment (A/B test) the user is enrolled in.
public struct PaywallExperiment: Codable, Equatable, Sendable {
    public let id: Int
    /// "a" or "b".
    public let variant: String

    public init(id: Int, variant: String) {
        self.id = id
        self.variant = variant
    }
}

/// One slot of an offering: a Cashier product and the StoreKit product that sells it.
public struct Package: Sendable, Identifiable {
    public enum PackageType: String, Sendable {
        case monthly = "$monthly", annual = "$annual", sixMonth = "$six_month", threeMonth = "$three_month"
        case twoMonth = "$two_month", weekly = "$weekly", lifetime = "$lifetime", custom
    }

    public let identifier: String
    public let offeringIdentifier: String
    public let cashierProduct: CashierProduct
    /// The App Store product — price, localized title, subscription period and
    /// intro offer all come from here; show `storeProduct.displayPrice`.
    public let storeProduct: Product

    public var id: String { offeringIdentifier + "/" + identifier }
    public var packageType: PackageType { PackageType(rawValue: identifier) ?? .custom }
    public var localizedPriceString: String { storeProduct.displayPrice }
}
