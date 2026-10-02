import StoreKit
import SwiftUI

/// Shows an offering's paywall — designed in the Cashier console — natively,
/// with App Store prices, and buys through Cashier.
///
/// ```swift
/// .sheet(isPresented: $showPaywall) {
///     PaywallView { info in if info.isEntitled(to: "premium") { showPaywall = false } }
/// }
/// ```
///
/// With no offering given it loads the current one. If that offering has no
/// published paywall, `fallback` is shown instead (a plain list by default).
///
/// The paywall is drawn in the language best matching `locale` (default:
/// the device's first preferred language) among those the console
/// translated it to. Its first showing and a dismissal without a purchase
/// are reported to Cashier for analytics, and answers tapped on Feedback /
/// Marketing Consent screens are recorded and handed to `onAnswer`.
public struct PaywallView<Fallback: View>: View {
    private let givenOffering: Offering?
    private let onPurchaseCompleted: (CustomerInfo) -> Void
    private let onRestoreCompleted: (CustomerInfo) -> Void
    private let onDismiss: (() -> Void)?
    private let locale: Locale?
    private let onAnswer: ((PaywallAnswer) -> Void)?
    private let fallback: (Offering?) -> Fallback

    @State private var offering: Offering?
    /// The offering's paywall, in the chosen language.
    @State private var doc: PaywallDoc?
    @State private var viewSent = false
    @State private var closeSent = false
    @State private var purchased = false
    @State private var views: [PaywallPackageView] = []
    @State private var loadError: String?
    @State private var purchasing = false
    @State private var alert: String?
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - offering: the offering to show; nil loads the current one.
    ///   - onPurchaseCompleted: after a purchase Cashier accepted.
    ///   - onRestoreCompleted: after a restore (even one that found nothing).
    ///   - onDismiss: the close button; nil dismisses the presenting sheet.
    ///   - locale: the language to draw the paywall in; nil is
    ///     `Locale.preferredLanguages.first`. Falls back to the same
    ///     language's translation (pt-BR → pt), then the default texts.
    ///   - onAnswer: an answer button was tapped (the answer is also
    ///     recorded with Cashier); its action runs right after.
    ///   - fallback: shown when the offering has no published paywall.
    public init(
        offering: Offering? = nil,
        onPurchaseCompleted: @escaping (CustomerInfo) -> Void = { _ in },
        onRestoreCompleted: @escaping (CustomerInfo) -> Void = { _ in },
        onDismiss: (() -> Void)? = nil,
        locale: Locale? = nil,
        onAnswer: ((PaywallAnswer) -> Void)? = nil,
        @ViewBuilder fallback: @escaping (Offering?) -> Fallback
    ) {
        givenOffering = offering
        self.onPurchaseCompleted = onPurchaseCompleted
        self.onRestoreCompleted = onRestoreCompleted
        self.onDismiss = onDismiss
        self.locale = locale
        self.onAnswer = onAnswer
        self.fallback = fallback
    }

    public var body: some View {
        Group {
            if let offering, let doc {
                content(doc, appName: offering.appName)
                    .onAppear { track("view") }
                    .onDisappear { if !purchased { track("close") } }
            } else if offering != nil || loadError != nil {
                fallback(offering)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .alert("Purchase", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alert ?? "")
        }
    }

    private func content(_ doc: PaywallDoc, appName: String) -> PaywallContent {
        var content = PaywallContent(doc: doc, appName: appName, packages: views, isPurchasing: purchasing,
                                     onPurchase: buy, onRestore: restore, onClose: close)
        content.onAnswer = answered
        return content
    }

    private func close() {
        if !purchased { track("close") }
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    /// "view" once, when first shown; "close" once, when dismissed without a
    /// purchase. Fire-and-forget; nothing for preview drafts.
    private func track(_ type: String) {
        guard let offering, Cashier.isConfigured else { return }
        if type == "view" {
            guard !viewSent else { return }
            viewSent = true
        } else {
            guard viewSent, !closeSent else { return }
            closeSent = true
        }
        Cashier.shared.trackPaywall(type, offering: offering)
    }

    private func answered(_ answer: PaywallAnswer) {
        onAnswer?(answer)
        if let offering, Cashier.isConfigured { Cashier.shared.recordAnswer(answer, offering: offering) }
    }

    private func load() async {
        do {
            let o: Offering?
            if let givenOffering { o = givenOffering } else { o = try await Cashier.shared.offerings().current }
            views = await PaywallPricing.views(for: o?.availablePackages ?? [])
            doc = o?.paywall?.localized(for: locale)
            offering = o
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func buy(_ view: PaywallPackageView) {
        guard let pkg = offering?.availablePackages.first(where: { $0.identifier == view.id }) else { return }
        purchasing = true
        Task {
            defer { purchasing = false }
            do {
                let result = try await Cashier.shared.purchase(pkg)
                if let info = result.customerInfo, !result.userCancelled, !result.isPending {
                    purchased = true
                    onPurchaseCompleted(info)
                } else if result.isPending {
                    alert = "Your purchase is waiting for approval. You'll get access as soon as it goes through."
                }
            } catch {
                alert = error.localizedDescription
            }
        }
    }

    private func restore() {
        purchasing = true
        Task {
            defer { purchasing = false }
            do {
                let info = try await Cashier.shared.restorePurchases()
                onRestoreCompleted(info)
                if info.activeEntitlementIDs.isEmpty { alert = "No purchases to restore were found for this Apple ID." }
            } catch {
                alert = error.localizedDescription
            }
        }
    }
}

extension PaywallView where Fallback == DefaultPaywallFallback {
    public init(
        offering: Offering? = nil,
        onPurchaseCompleted: @escaping (CustomerInfo) -> Void = { _ in },
        onRestoreCompleted: @escaping (CustomerInfo) -> Void = { _ in },
        onDismiss: (() -> Void)? = nil,
        locale: Locale? = nil,
        onAnswer: ((PaywallAnswer) -> Void)? = nil
    ) {
        self.init(offering: offering, onPurchaseCompleted: onPurchaseCompleted, onRestoreCompleted: onRestoreCompleted,
                  onDismiss: onDismiss, locale: locale, onAnswer: onAnswer, fallback: { DefaultPaywallFallback(offering: $0) })
    }
}

/// An answer tapped on a paywall screen (Feedback, Marketing Consent).
public struct PaywallAnswer: Codable, Equatable, Hashable, Sendable {
    /// The screen's id.
    public let screenID: String
    /// The screen's `question`, else its name.
    public let question: String
    /// The tapped button's `answer`, in the language shown.
    public let answer: String

    public init(screenID: String, question: String, answer: String) {
        self.screenID = screenID
        self.question = question
        self.answer = answer
    }

    /// The answer a button records, or nil when it carries none.
    init?(block: PaywallDoc.Block, screen: PaywallDoc.Screen) {
        guard block.type == "button", let a = block.answer?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return nil }
        self.init(screenID: screen.id, question: screen.answerQuestion, answer: a)
    }

    enum CodingKeys: String, CodingKey { case screenID = "screen_id", question, answer }
}

/// Shown when an offering has no published paywall: its packages as a plain list.
public struct DefaultPaywallFallback: View {
    let offering: Offering?
    public var body: some View {
        List(offering?.availablePackages ?? []) { pkg in
            HStack {
                Text(pkg.storeProduct.displayName)
                Spacer()
                Text(pkg.storeProduct.displayPrice).foregroundColor(.secondary)
            }
        }
    }
}

/// StoreKit prices for the paywall's variables.
enum PaywallPricing {
    static func views(for packages: [Package]) async -> [PaywallPackageView] {
        var out: [PaywallPackageView] = []
        // {{savings}}: each plan's monthly price against the shortest plan of a month or more.
        let savings = PaywallPlans.savings(packages.map { pkg in
            let p = pkg.storeProduct
            return (pkg.identifier, NSDecimalNumber(decimal: p.price).doubleValue, p.subscription.map { months($0.subscriptionPeriod) } ?? 0)
        })
        for pkg in packages {
            let p = pkg.storeProduct
            var period = "", perMonth = "", trial = ""
            if let sub = p.subscription {
                period = words(sub.subscriptionPeriod)
                let months = monthsIn(sub.subscriptionPeriod)
                if months > 1 {
                    perMonth = (p.price / Decimal(months)).formatted(p.priceFormatStyle)
                }
                if let intro = sub.introductoryOffer, intro.paymentMode == .freeTrial,
                   await sub.isEligibleForIntroOffer {
                    trial = trialWords(intro.period)
                }
            }
            out.append(PaywallPackageView(id: pkg.identifier, productName: p.displayName, price: p.displayPrice,
                                          period: period, pricePerMonth: perMonth, trial: trial, savings: savings[pkg.identifier] ?? ""))
        }
        return out
    }

    static func words(_ period: Product.SubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    static func trialWords(_ period: Product.SubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "day"
        }
        return "\(period.value)-\(unit)"
    }

    /// A period in months, for savings: weeks are a quarter, days not counted.
    static func months(_ period: Product.SubscriptionPeriod) -> Double {
        switch period.unit {
        case .week: return Double(period.value) * 0.25
        case .month: return Double(period.value)
        case .year: return Double(period.value) * 12
        default: return 0
        }
    }

    static func monthsIn(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .month: return period.value
        case .year: return period.value * 12
        default: return 0
        }
    }
}

extension View {
    /// Presents the current offering's paywall as a sheet whenever the user
    /// lacks `entitlement`, and dismisses it once a purchase or restore grants it.
    ///
    /// - Parameters:
    ///   - locale: the paywall's language; nil is `Locale.preferredLanguages.first`.
    ///   - onAnswer: an answer button on the paywall was tapped.
    public func presentPaywallIfNeeded(requiredEntitlement entitlement: String, locale: Locale? = nil,
                                       onAnswer: ((PaywallAnswer) -> Void)? = nil) -> some View {
        modifier(PaywallGate(entitlement: entitlement, locale: locale, onAnswer: onAnswer))
    }
}

struct PaywallGate: ViewModifier {
    let entitlement: String
    let locale: Locale?
    let onAnswer: ((PaywallAnswer) -> Void)?
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .task {
                guard Cashier.isConfigured,
                      let info = try? await Cashier.shared.customerInfo() else { return }
                show = !info.isEntitled(to: entitlement)
            }
            .sheet(isPresented: $show) {
                PaywallView(
                    onPurchaseCompleted: { if $0.isEntitled(to: entitlement) { show = false } },
                    onRestoreCompleted: { if $0.isEntitled(to: entitlement) { show = false } },
                    onDismiss: { show = false },
                    locale: locale,
                    onAnswer: onAnswer
                )
            }
    }
}
