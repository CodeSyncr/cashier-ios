import Foundation
import SwiftUI

/// A paywall designed in the Cashier console. The same document the web
/// editor previews and the web SDK renders; `PaywallView` draws it natively.
public struct PaywallDoc: Decodable, Equatable, Sendable {
    /// The schema version this SDK understands. A newer document is not
    /// guessed at: `PaywallView` shows a fallback instead.
    public static let supportedVersion = 2

    public let version: Int
    public let theme: Theme
    /// The screen the flow opens on.
    public let initial: String?
    /// The flow. A version-1 document has `blocks` instead; `flow` reads
    /// either.
    public internal(set) var screens: [Screen]?
    public internal(set) var blocks: [Block]?
    /// The language the block texts are written in ("" or nil means "en").
    public var defaultLocale: String? = nil
    /// Extra locales that have translations (`es`, `pt-BR`, `zh-Hans`).
    public var locales: [String]? = nil
    /// The translations: locale → key → text. Keys are `<blockID>.text`,
    /// `<blockID>.items.0.title`, `<screenID>.question`, … (see
    /// `localized(to:)`). Unreadable translations are ignored.
    public var strings: [String: [String: String]]? { stringsBox?.value }
    var stringsBox: LenientStrings? = nil

    enum CodingKeys: String, CodingKey {
        case version, theme, initial, screens, blocks, defaultLocale = "default_locale", locales, stringsBox = "strings"
    }

    /// Every screen of the flow, a version-1 document read as one.
    public var flow: [Screen] {
        if let screens, !screens.isEmpty { return screens }
        return [Screen(id: "paywall", name: "Paywall", background: nil, backgroundEnd: nil, paddingX: nil, paddingY: nil,
                       spacing: nil, justify: nil, align: nil, blocks: blocks ?? [])]
    }

    /// The id of the screen the flow opens on.
    public var initialScreenID: String {
        let all = flow
        if let initial, all.contains(where: { $0.id == initial }) { return initial }
        return all.first?.id ?? "paywall"
    }

    /// One step of the flow.
    public struct Screen: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let background: String?
        public let backgroundEnd: String?
        public let paddingX: Double?
        public let paddingY: Double?
        public let spacing: Double?
        /// start | center | end | space_between
        public let justify: String?
        /// left | center
        public let align: String?
        public internal(set) var blocks: [Block]
        /// The question this screen's answers are grouped under (Feedback,
        /// Marketing Consent); `answerQuestion` falls back to the name.
        public internal(set) var question: String? = nil
        /// The question key answers on this screen are recorded under.
        public var answerQuestion: String {
            if let q = question?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty { return q }
            return name
        }
        /// An animated background from the accent, behind the blocks:
        /// glow | aurora | orbs | grid | rays
        public var effect: String? = nil
        /// How the blocks come in when the screen opens: rise | fade | zoom
        public var entrance: String? = nil
        /// Media behind everything on the screen (https), aspect-filled; a
        /// video wins over an image.
        public var backgroundImage: String? = nil
        public var backgroundVideo: String? = nil
        /// A colour (usually translucent) over the media, under the blocks.
        public var backgroundOverlay: String? = nil
        /// This screen's own theme, drawn instead of the document's; nil when
        /// it has none or it could not be read.
        public var theme: Theme? { ownTheme?.value }
        var ownTheme: LenientTheme? = nil

        /// Every block on the screen, containers' children included (depth first).
        public var allBlocks: [Block] { blocks.flatMap(\.withDescendants) }

        enum CodingKeys: String, CodingKey {
            case id, name, background, backgroundEnd = "background_end", paddingX = "padding_x", paddingY = "padding_y"
            case spacing, justify, align, blocks, question, effect, entrance, ownTheme = "theme"
            case backgroundImage = "background_image", backgroundVideo = "background_video", backgroundOverlay = "background_overlay"
        }
    }

    public struct Theme: Decodable, Equatable, Sendable {
        public let background: String
        public let backgroundEnd: String?
        public let surface: String
        public let text: String
        public let muted: String
        public let accent: String
        public let accentText: String
        public let radius: Double
        public let font: String

        enum CodingKeys: String, CodingKey {
            case background, backgroundEnd = "background_end", surface, text, muted, accent
            case accentText = "accent_text", radius, font
        }
    }

    public struct Item: Decodable, Equatable, Sendable {
        public let icon: String
        public internal(set) var title: String
        public internal(set) var text: String?
    }

    public struct Block: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let type: String
        public internal(set) var text: String?
        public internal(set) var subtext: String?
        public let align: String?
        public let size: String?
        public let url: String?
        public let height: Double?
        public internal(set) var items: [Item]?
        public let layout: String?
        public let highlight: String?
        public internal(set) var badges: [String: String]?
        public internal(set) var author: String?
        public let rating: Int?
        public let restore: Bool?
        public let termsURL: String?
        public let privacyURL: String?
        public let icon: String?
        /// Button: next | back | screen | close | restore | url
        public let action: String?
        /// Button with action "screen": the screen id.
        public let target: String?
        /// Button: primary | secondary | outline | link
        public let style: String?
        /// Button: the answer tapping it records (Feedback / Marketing
        /// Consent screens) before its action runs.
        public internal(set) var answer: String? = nil

        /// Containers (stack, custom, sheet, tabs, carousel): the blocks inside.
        /// A tab is a child stack whose `text` is its label.
        public internal(set) var children: [Block]?
        /// stack, custom: vertical | horizontal
        public let axis: String?
        /// stack, custom: start | center | end | space_between
        public let justify: String?
        /// stack, custom, sheet: space between children (0 → 12).
        public let gap: Double?
        /// custom, sheet: inner padding (0 → 16 / 22).
        public let padding: Double?
        /// custom, sheet: fill ("" → the theme's surface).
        public let background: String?
        /// custom: 1pt border colour.
        public let border: String?
        /// custom, sheet: corner radius (0 → the theme's / 28).
        public let radius: Double?
        /// carousel: seconds between pages, 0 = swipe only.
        public let interval: Int?
        /// video: the still shown before it plays.
        public let poster: String?
        /// header: a back chevron to the previous screen.
        public let back: Bool?
        /// switch: the package selected when on / off.
        public let packageOn: String?
        public let packageOff: String?
        /// countdown: to a fixed moment (RFC 3339)…
        public let until: String?
        /// …or for this many minutes from when it is first shown.
        public let minutes: Int?
        /// social_proof: avatar URLs.
        public let images: [String]?
        /// Which of the type's designs to draw (see `PaywallVariants`); nil,
        /// "" or unknown is the type's first.
        public let variant: String?
        /// Drawn instead of the icon (icon block, option button).
        public let emoji: String?
        /// stack, custom: how children line up across the axis:
        /// start | center | end | stretch
        public let cross: String?
        /// Fine-tuning of this block's box and type; nil when absent or unreadable.
        public var look: Look? { lookBox?.value }
        let lookBox: LenientLook?
        /// stack, custom: makes the box a plan card for this package id.
        public let package: String?
        /// Plan card: a pill on its top edge (variables speak of the card's package).
        public internal(set) var badge: String?
        /// art: which built-in illustration (see `PaywallArt.scenes`).
        public let art: String?
        /// Laid over `look` while this block's plan card is selected.
        public var lookSelected: Look? { lookSelectedBox?.value }
        let lookSelectedBox: LenientLook?

        /// The variant to draw: this block's if this SDK knows it, else the
        /// type's default.
        public var resolvedVariant: String { PaywallVariants.resolve(type: type, variant: variant) }

        /// This block and every block inside it (depth first).
        public var withDescendants: [Block] { [self] + (children ?? []).flatMap(\.withDescendants) }

        enum CodingKeys: String, CodingKey {
            case id, type, text, subtext, align, size, url, height, items, layout, highlight, badges, author, rating, restore
            case termsURL = "terms_url", privacyURL = "privacy_url", icon, action, target, style
            case children, axis, justify, gap, padding, background, border, radius, interval, poster, back
            case packageOn = "package_on", packageOff = "package_off", until, minutes, images, variant, emoji, cross, lookBox = "look"
            case package, lookSelectedBox = "look_selected", badge, art, answer
        }
    }

    /// Every block of every screen, containers' children included.
    public var allBlocks: [Block] { flow.flatMap(\.allBlocks) }

    /// The theme a screen is drawn with: its own where it has one, field by
    /// field (an unreadable colour or font falls back to the document's),
    /// else the document's.
    public func theme(for screen: Screen) -> Theme {
        guard let own = screen.theme else { return theme }
        func colour(_ mine: String, _ theirs: String) -> String { Color(paywallHex: mine) != nil ? mine : theirs }
        let end: String?
        if let e = own.backgroundEnd, !e.isEmpty { end = Color(paywallHex: e) != nil ? e : theme.backgroundEnd } else { end = nil }
        return Theme(background: colour(own.background, theme.background), backgroundEnd: end,
                     surface: colour(own.surface, theme.surface), text: colour(own.text, theme.text),
                     muted: colour(own.muted, theme.muted), accent: colour(own.accent, theme.accent),
                     accentText: colour(own.accentText, theme.accentText),
                     radius: own.radius.isFinite && own.radius >= 0 ? own.radius : theme.radius,
                     font: ["system", "rounded", "serif", "mono"].contains(own.font) ? own.font : theme.font)
    }

    /// A block's style panel (`look`): its box, then its type. Every field is
    /// optional; nil, 0 and "" mean "as the design has it".
    public struct Look: Decodable, Equatable, Sendable {
        /// fit | fill | fixed
        public var width: String?
        public var widthPx: Double?
        /// fit | fill | fixed
        public var height: String?
        public var heightPx: Double?
        public var paddingX: Double?
        public var paddingY: Double?
        public var marginX: Double?
        public var marginY: Double?
        public var background: String?
        public var backgroundEnd: String?
        public var backgroundImage: String?
        public var radius: Double?
        /// top-left, top-right, bottom-right, bottom-left
        public var corners: [Double]?
        public var borderColor: String?
        public var borderWidth: Double?
        public var shadowColor: String?
        public var shadowX: Double?
        public var shadowY: Double?
        public var shadowBlur: Double?
        /// 1–100; 0 or nil is fully opaque.
        public var opacity: Double?
        /// system | rounded | serif | mono
        public var font: String?
        /// regular | medium | semibold | bold | heavy
        public var weight: String?
        public var fontSize: Double?
        public var color: String?
        public var italic: Bool?

        public init() {}

        /// This look with every field `top` sets laid over it.
        public func overlaid(with top: Look?) -> Look {
            guard let top else { return self }
            var l = self
            l.width = top.width ?? l.width
            l.widthPx = top.widthPx ?? l.widthPx
            l.height = top.height ?? l.height
            l.heightPx = top.heightPx ?? l.heightPx
            l.paddingX = top.paddingX ?? l.paddingX
            l.paddingY = top.paddingY ?? l.paddingY
            l.marginX = top.marginX ?? l.marginX
            l.marginY = top.marginY ?? l.marginY
            l.background = top.background ?? l.background
            l.backgroundEnd = top.backgroundEnd ?? l.backgroundEnd
            l.backgroundImage = top.backgroundImage ?? l.backgroundImage
            l.radius = top.radius ?? l.radius
            l.corners = top.corners ?? l.corners
            l.borderColor = top.borderColor ?? l.borderColor
            l.borderWidth = top.borderWidth ?? l.borderWidth
            l.shadowColor = top.shadowColor ?? l.shadowColor
            l.shadowX = top.shadowX ?? l.shadowX
            l.shadowY = top.shadowY ?? l.shadowY
            l.shadowBlur = top.shadowBlur ?? l.shadowBlur
            l.opacity = top.opacity ?? l.opacity
            l.font = top.font ?? l.font
            l.weight = top.weight ?? l.weight
            l.fontSize = top.fontSize ?? l.fontSize
            l.color = top.color ?? l.color
            l.italic = top.italic ?? l.italic
            return l
        }

        enum CodingKeys: String, CodingKey {
            case width, widthPx = "width_px", height, heightPx = "height_px", paddingX = "padding_x", paddingY = "padding_y"
            case marginX = "margin_x", marginY = "margin_y", background, backgroundEnd = "background_end"
            case backgroundImage = "background_image", radius, corners, borderColor = "border_color", borderWidth = "border_width"
            case shadowColor = "shadow_color", shadowX = "shadow_x", shadowY = "shadow_y", shadowBlur = "shadow_blur", opacity
            case font, weight, fontSize = "font_size", color, italic
        }
    }

    /// A look that never fails the document: unreadable is nil.
    struct LenientLook: Decodable, Equatable, Sendable {
        let value: Look?
        init(from decoder: Decoder) throws { value = try? Look(from: decoder) }
    }

    /// Translations that never fail the document: unreadable is nil.
    struct LenientStrings: Decodable, Equatable, Sendable {
        let value: [String: [String: String]]?
        init(from decoder: Decoder) throws { value = try? [String: [String: String]](from: decoder) }
    }

    /// A screen's theme that never fails the document: unreadable is nil.
    struct LenientTheme: Decodable, Equatable, Sendable {
        let value: Theme?
        init(from decoder: Decoder) throws { value = try? Theme(from: decoder) }
    }

    /// Whether this SDK can draw the document.
    public var isSupported: Bool { version <= Self.supportedVersion }
}

/// One package as the paywall shows it, prices already localized.
public struct PaywallPackageView: Equatable, Sendable, Identifiable {
    public let id: String
    public let productName: String
    /// "$4.99"
    public let price: String
    /// "month", "year", … or "" for a one-time purchase.
    public let period: String
    /// "$3.33", or "" when not meaningful.
    public let pricePerMonth: String
    /// "7-day", or "" when there is no trial (or the user is not eligible).
    public let trial: String
    /// "17%": what this package saves per month against the shortest plan
    /// of a month or more; "" when not meaningful.
    public let savings: String

    public init(id: String, productName: String, price: String, period: String, pricePerMonth: String, trial: String,
                savings: String = "") {
        self.id = id
        self.productName = productName
        self.price = price
        self.period = period
        self.pricePerMonth = pricePerMonth
        self.trial = trial
        self.savings = savings
    }
}

enum PaywallText {
    private static let variable = try! NSRegularExpression(pattern: #"\{\{\s*([a-z_]+)\s*\}\}"#)

    private static let savingsVariable = try! NSRegularExpression(pattern: #"\{\{\s*savings\s*\}\}"#)

    /// Text that speaks of {{savings}} is not shown at all when the package
    /// it speaks of saves nothing.
    static func hidesForSavings(_ text: String?, package: PaywallPackageView?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let mentions = savingsVariable.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
        return mentions && (package?.savings ?? "").isEmpty
    }

    /// Fills {{variables}}; unknown names become "". Same rules as the web SDK.
    static func resolve(_ text: String, appName: String, package: PaywallPackageView?) -> String {
        let values: [String: String] = [
            "app_name": appName,
            "product_name": package?.productName ?? "",
            "price": package?.price ?? "",
            "period": package?.period ?? "",
            "price_per_month": package?.pricePerMonth ?? "",
            "trial": package?.trial ?? "",
            "savings": package?.savings ?? "",
        ]
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in variable.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += values[ns.substring(with: m.range(at: 1))] ?? ""
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        // Collapse the double spaces an empty variable leaves behind.
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        // …and the space an empty variable leaves before punctuation.
        for p in [",", ".", ":", ";", "!", "?"] { out = out.replacingOccurrences(of: " " + p, with: p) }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

/// A countdown's arithmetic, kept pure so it can be tested.
enum PaywallCountdown {
    private static func parse(_ s: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: s)
    }

    /// The moment the countdown ends: `until` if set (and readable), else
    /// `minutes` after `start` (when the countdown was first shown).
    static func target(until: String?, minutes: Int?, start: Date) -> Date? {
        if let until, !until.isEmpty { return parse(until) }
        if let minutes, minutes > 0 { return start.addingTimeInterval(TimeInterval(minutes) * 60) }
        return nil
    }

    /// Hours, minutes and seconds left, never below zero.
    static func remaining(to target: Date?, now: Date) -> (hours: Int, minutes: Int, seconds: Int) {
        guard let target else { return (0, 0, 0) }
        let left = max(0, Int(target.timeIntervalSince(now).rounded(.down)))
        return (left / 3600, left % 3600 / 60, left % 60)
    }
}

/// A switch block toggles between two packages.
enum PaywallSwitch {
    /// On when the selected package is the switch's "on" package.
    static func isOn(selected: String?, packageOn: String?) -> Bool {
        selected != nil && selected == packageOn
    }

    /// The package to select when the switch is flipped to `on`.
    static func package(on: Bool, packageOn: String?, packageOff: String?) -> String? {
        on ? packageOn : packageOff
    }
}

/// Each block type's designs, the first being the default (the server's
/// `paywall.Variants`). A variant this SDK does not know draws the default.
enum PaywallVariants {
    static let table: [String: [String]] = [
        "header": ["plain", "large", "pill", "brand"],
        "tabs": ["pills", "underline", "outline"],
        "switch": ["card", "plain", "checkbox"],
        "button": ["rounded", "pill", "square", "option"],
        "icon": ["tile", "glow", "rings", "gradient", "plain"],
        "image": ["inline", "hero", "hero_fade"],
        "video": ["inline", "hero", "hero_fade"],
        "art": ["inline", "hero", "hero_fade"],
        "carousel": ["dots", "bars", "peek"],
        "countdown": ["boxes", "labeled", "inline", "banner"],
        "timeline": ["line", "cards", "horizontal"],
        "social_proof": ["avatars", "rating", "badge"],
        "testimonial": ["card", "quote", "bubble"],
        "features": ["list", "checks", "grid", "cards"],
        "award": ["laurel", "badge", "ribbon"],
    ]

    static func resolve(type: String, variant: String?) -> String {
        let known = table[type] ?? []
        if let variant, known.contains(variant) { return variant }
        return known.first ?? ""
    }
}

/// Plan cards: which card to select, and what each saves.
enum PaywallPlans {
    /// Every plan card's package id in document order.
    static func cards(in blocks: [PaywallDoc.Block]) -> [String] {
        blocks.flatMap(\.withDescendants).compactMap { b in
            guard let p = b.package, !p.isEmpty, b.type == "stack" || b.type == "custom" else { return nil }
            return p
        }
    }

    /// The package selected before the user picks: theirs if still
    /// offered; else the packages block's highlight; else the first plan
    /// card (document order) whose package exists; else the first package.
    static func initialSelection(selected: String?, highlight: String?, cards: [String], available: [String]) -> String? {
        if let selected, available.contains(selected) { return selected }
        if let highlight, available.contains(highlight) { return highlight }
        return cards.first(where: available.contains) ?? available.first
    }

    /// Whether a block is drawn: a plan card only when its package is offered.
    static func isShown(_ b: PaywallDoc.Block, available: [String]) -> Bool {
        guard let p = b.package, !p.isEmpty, b.type == "stack" || b.type == "custom" else { return true }
        return available.contains(p)
    }

    /// The package text speaks of: inside a plan card its package, elsewhere the selected one.
    static func scope(card: String?, selected: PaywallPackageView?, packages: [PaywallPackageView]) -> PaywallPackageView? {
        card.flatMap { id in packages.first { $0.id == id } } ?? selected
    }

    /// When `tab` opens: the first of its plan cards whose package exists,
    /// unless the selection is already one of them (or it has none) — nil
    /// means leave the selection alone.
    static func tierSelection(tab: PaywallDoc.Block, selected: String?, available: [String]) -> String? {
        let ids = cards(in: [tab]).filter(available.contains)
        guard let first = ids.first else { return nil }
        if let selected, ids.contains(selected) { return nil }
        return first
    }

    /// "{pct}%" per package id: against the shortest plan of at least a
    /// month, per month; "" for that plan, one-time purchases, and savings
    /// under 1%. `months` is 0 for a one-time purchase (weeks are 0.25).
    static func savings(_ plans: [(id: String, price: Double, months: Double)]) -> [String: String] {
        var out = Dictionary(plans.map { ($0.id, "") }, uniquingKeysWith: { a, _ in a })
        guard let ref = plans.filter({ $0.months >= 1 }).min(by: { $0.months < $1.months }), ref.price > 0 else { return out }
        let refPerMonth = ref.price / ref.months
        for p in plans where p.months > 0 && p.id != ref.id {
            let pct = Int(((1 - (p.price / p.months) / refPerMonth) * 100).rounded())
            if pct >= 1 { out[p.id] = "\(pct)%" }
        }
        return out
    }
}


/// Which URLs a paywall may load or open: https anywhere, and plain http
/// only from this machine (the console serves uploads from localhost in
/// development). Same rule as the server and the web SDK.
public enum PaywallURL {
    public static func safe(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty, let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        switch scheme {
        case "https": return url
        case "http": return host == "localhost" || host == "127.0.0.1" ? url : nil
        default: return nil
        }
    }
}
