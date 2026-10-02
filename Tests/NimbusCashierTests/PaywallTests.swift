import SwiftUI
import XCTest
@testable import NimbusCashier

/// The documents in Fixtures/paywalls.json are exported from the Cashier
/// server's own templates (plus a showcase using every block type, and two multi-step flows), so these tests
/// prove that what the web editor saves, the iOS SDK can draw.
final class PaywallTests: XCTestCase {
    static let packages = [
        PaywallPackageView(id: "$monthly", productName: "Monthly", price: "$4.99", period: "month", pricePerMonth: "", trial: ""),
        PaywallPackageView(id: "$annual", productName: "Annual", price: "$39.99", period: "year", pricePerMonth: "$3.33", trial: "7-day"),
    ]

    func fixtures() throws -> [String: PaywallDoc] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "paywalls", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([String: PaywallDoc].self, from: Data(contentsOf: url))
    }

    /// Every block type the server can save (doc.go's BlockTypes).
    static let blockTypes: Set<String> = [
        "title", "text", "image", "video", "art", "icon", "stack", "footer", "header", "custom", "spacer",
        "packages", "cta", "sheet", "tabs", "switch", "button", "carousel",
        "countdown", "timeline", "social_proof", "testimonial", "features", "award",
    ]

    func testEveryServerDocumentDecodesAndIsSupported() throws {
        let docs = try fixtures()
        XCTAssertEqual(docs.count, 51, "the gallery templates, plans, the showcase, the variants, three flows of every step and a translated flow")
        for (name, doc) in docs {
            XCTAssertTrue(doc.isSupported, name)
            let all = doc.allBlocks
            // A package picker: the packages block, or plan cards.
            XCTAssertTrue(all.filter { $0.type == "packages" }.count == 1 || all.contains { !($0.package ?? "").isEmpty }, name)
            XCTAssertEqual(all.filter { $0.type == "cta" }.count, 1, name)
            XCTAssertTrue(doc.flow.contains { $0.id == doc.initialScreenID }, name)
            for screen in doc.flow {
                XCTAssertTrue(Self.effects.contains(screen.effect ?? "glow"), "\(name): effect \(screen.effect ?? "")")
                XCTAssertTrue(Self.entrances.contains(screen.entrance ?? "rise"), "\(name): entrance \(screen.entrance ?? "")")
            }
            for block in all {
                XCTAssertTrue(Self.blockTypes.contains(block.type), "\(name): the SDK has no renderer for \(block.type)")
                for icon in (block.items ?? []).map(\.icon) + [block.icon].compactMap({ $0 }) {
                    XCTAssertNotNil(PaywallIcons.symbols[icon], "\(name): no SF Symbol for icon \(icon)")
                }
                if block.type == "button" {
                    XCTAssertTrue(["next", "back", "screen", "close", "restore", "url"].contains(block.action ?? ""), "\(name): button action")
                    XCTAssertTrue(["primary", "secondary", "outline", "link"].contains(block.style ?? "primary"), "\(name): button style")
                }
                if let v = block.variant, !v.isEmpty {
                    XCTAssertEqual(block.resolvedVariant, v, "\(name): the SDK has no \(block.type) variant \(v)")
                }
                for hex in [block.background, block.border].compactMap({ $0 }) where !hex.isEmpty {
                    XCTAssertNotNil(Color(paywallHex: hex), "\(name): colour \(hex)")
                }
                if block.type == "tabs" {
                    XCTAssertTrue((block.children ?? []).allSatisfy { $0.type == "stack" && !($0.text ?? "").isEmpty }, "\(name): tabs are labelled stacks")
                }
            }
            for hex in [doc.theme.background, doc.theme.surface, doc.theme.text, doc.theme.muted, doc.theme.accent, doc.theme.accentText] {
                XCTAssertNotNil(Color(paywallHex: hex), "\(name): colour \(hex)")
            }
        }
        let showcase = try XCTUnwrap(docs["showcase"])
        XCTAssertEqual(Set(showcase.allBlocks.map(\.type)), Self.blockTypes, "the showcase covers every block type")
        XCTAssertEqual(showcase.flow.count, 2)
        XCTAssertTrue(showcase.flow.flatMap(\.blocks).contains { !($0.children ?? []).isEmpty }, "the showcase nests blocks")
        XCTAssertEqual(try XCTUnwrap(docs["steps_1"]).flow.count, 10)
        XCTAssertEqual(try XCTUnwrap(docs["steps_2"]).flow.count, 10)
        XCTAssertEqual(try XCTUnwrap(docs["steps_3"]).flow.count, 2)
    }

    /// The server's `paywall.Variants`, restated: a change there must be a
    /// change here.
    static let variants: [String: [String]] = [
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

    /// The server's `paywall.Effects` and `paywall.Entrances`.
    static let effects: Set<String> = ["glow", "aurora", "orbs", "grid", "rays"]
    static let entrances: Set<String> = ["rise", "fade", "zoom"]

    func testVariantsDocumentShowsEveryEffectAndEntrance() throws {
        let doc = try XCTUnwrap(try fixtures()["variants"])
        XCTAssertEqual(Set(doc.flow.compactMap(\.effect)), Self.effects)
        XCTAssertEqual(Set(doc.flow.compactMap(\.entrance)), Self.entrances)
        XCTAssertTrue(doc.allBlocks.contains { $0.type == "button" && $0.resolvedVariant == "option" && !($0.emoji ?? "").isEmpty })
    }

    @MainActor
    func testEmojiIconDecodesAndRenders() throws {
        let json = ##"{"version":2,"theme":{"background":"#FFFFFF","surface":"#EEEEEE","text":"#000000","muted":"#666666","accent":"#F04E28","accent_text":"#FFFFFF","radius":8,"font":"system"},"screens":[{"id":"s","name":"S","effect":"rays","entrance":"zoom","blocks":[{"id":"i","type":"icon","emoji":"🚀","variant":"gradient"},{"id":"j","type":"icon","emoji":"👋","variant":"plain"},{"id":"o","type":"button","variant":"option","icon":"bolt","text":"Faster","action":"next"},{"id":"p","type":"packages"},{"id":"c","type":"cta","text":"Buy"}]}]}"##
        let doc = try JSONDecoder().decode(PaywallDoc.self, from: Data(json.utf8))
        let icon = try XCTUnwrap(doc.allBlocks.first)
        XCTAssertNil(icon.icon)
        XCTAssertEqual(icon.emoji, "🚀")
        XCTAssertEqual(doc.flow[0].effect, "rays")
        XCTAssertEqual(doc.flow[0].entrance, "zoom")
        XCTAssertEqual(doc.allBlocks[2].icon, "bolt")
        guard #available(macOS 13, iOS 16, *) else { return }
        var content = PaywallContent(doc: doc, appName: "Acme", packages: Self.packages, onPurchase: { _ in })
        content.scrolls = false
        XCTAssertNotNil(ImageRenderer(content: content.frame(width: 390, height: 844)).cgImage)
    }

    func testHueShift() {
        let hsb = PaywallHue.hsb(r: 0, g: 1, b: 0)
        XCTAssertEqual(hsb.h, 1.0 / 3, accuracy: 0.0001, "green sits a third of the way round")
        XCTAssertNotNil(Color(paywallHex: "#FF0000", hueShift: 120))
        XCTAssertNil(Color(paywallHex: "red", hueShift: 30))
    }

    func testScreensDrawWithTheirOwnTheme() throws {
        let docs = try fixtures()
        let variants = try XCTUnwrap(docs["variants"])
        let own = try XCTUnwrap(variants.flow.first { $0.id == "variants-1" })
        let plain = try XCTUnwrap(variants.flow.first { $0.id == "variants-2" })
        XCTAssertEqual(variants.theme(for: own).background, "#0B0B1F")
        XCTAssertEqual(variants.theme(for: own).accent, "#8B7CFF")
        XCTAssertNil(plain.theme)
        XCTAssertEqual(variants.theme(for: plain), variants.theme)
        // Every step screen of the step flows has its own palette.
        for name in ["steps_1", "steps_2", "steps_3"] {
            let doc = try XCTUnwrap(docs[name])
            for screen in doc.flow where screen.theme != nil {
                XCTAssertEqual(doc.theme(for: screen), screen.theme, "\(name)/\(screen.id)")
            }
        }
        XCTAssertGreaterThan(Set(try XCTUnwrap(docs["steps_1"]).flow.compactMap(\.theme?.accent)).count, 1)
    }

    func testABadScreenThemeFallsBack() throws {
        let theme = ##""theme":{"background":"#FFFFFF","surface":"#EEEEEE","text":"#000000","muted":"#666666","accent":"#FF0000","accent_text":"#FFFFFF","radius":8,"font":"system"}"##
        let json = ##"{"version":2,"##+theme+##","screens":[{"id":"a","name":"A","theme":{"background":"#000000","surface":"nope","text":"#FFFFFF","muted":"#999999","accent":"#00FF00","accent_text":"#000000","radius":20,"font":"comic"},"blocks":[]},{"id":"b","name":"B","theme":{"background":42},"blocks":[]}]}"##
        let doc = try JSONDecoder().decode(PaywallDoc.self, from: Data(json.utf8))
        let a = doc.theme(for: doc.flow[0])
        XCTAssertEqual(a.background, "#000000")
        XCTAssertEqual(a.accent, "#00FF00")
        XCTAssertEqual(a.radius, 20)
        XCTAssertEqual(a.surface, "#EEEEEE", "an unreadable colour falls back to the document's")
        XCTAssertEqual(a.font, "system", "an unknown font falls back to the document's")
        XCTAssertNil(doc.flow[1].theme, "an unreadable screen theme is dropped, not the document")
        XCTAssertEqual(doc.theme(for: doc.flow[1]), doc.theme)
    }

    func testLooksDecode() throws {
        let doc = try XCTUnwrap(try fixtures()["variants"])
        let looks = try XCTUnwrap(doc.flow.first { $0.id == "looks" })
        let blocks = looks.allBlocks
        let title = try XCTUnwrap(blocks.first { $0.id == "title-10" })
        XCTAssertEqual(title.align, "right")
        XCTAssertEqual(title.look?.font, "serif")
        XCTAssertEqual(title.look?.weight, "heavy")
        XCTAssertEqual(title.look?.fontSize, 34)
        XCTAssertEqual(title.look?.italic, true)
        let card = try XCTUnwrap(blocks.first { $0.id == "custom-2" }?.look)
        XCTAssertEqual(card.width, "fixed")
        XCTAssertEqual(card.widthPx, 300)
        XCTAssertEqual(card.corners, [0, 0, 12, 12])
        XCTAssertEqual(PaywallLookMath.corners(card), [0, 0, 12, 12])
        XCTAssertEqual(card.backgroundEnd, "#EEF4FF")
        XCTAssertEqual(card.shadowBlur, 18)
        XCTAssertEqual(blocks.first { $0.id == "stack-18" }?.cross, "center")
        XCTAssertEqual(blocks.first { $0.id == "stack-19" }?.axis, "layers")
        XCTAssertEqual(blocks.first { $0.id == "icon-11" }?.look?.opacity, 30)

        // An unreadable look is ignored, never the document.
        let json = ##"{"id":"t","type":"title","text":"Hi","look":{"width":7,"corners":"round"}}"##
        let bad = try JSONDecoder().decode(PaywallDoc.Block.self, from: Data(json.utf8))
        XCTAssertNil(bad.look)
        XCTAssertEqual(bad.text, "Hi")
    }

    func testLookArithmetic() {
        var look = PaywallDoc.Look()
        look.radius = 20
        XCTAssertEqual(PaywallLookMath.corners(look), [20, 20, 20, 20])
        look.corners = [1, 2, 3]
        XCTAssertEqual(PaywallLookMath.corners(look), [20, 20, 20, 20], "corners need all four")
        look.corners = [0, 300, 4, 5]
        XCTAssertEqual(PaywallLookMath.corners(look), [0, 200, 4, 5], "clamped to 200")

        XCTAssertEqual(PaywallLookMath.size("fit", nil), .fit)
        XCTAssertEqual(PaywallLookMath.size("fill", 50), .fill)
        XCTAssertEqual(PaywallLookMath.size("fixed", 300), .fixed(300))
        XCTAssertNil(PaywallLookMath.size("fixed", 0), "a fixed size needs its pixels")
        XCTAssertNil(PaywallLookMath.size(nil, 300))

        let none = PaywallLookMath.font(size: 30, weight: .bold, design: .default, type: PaywallType())
        XCTAssertEqual(none.size, 30)
        XCTAssertEqual(none.weight, .bold)
        XCTAssertFalse(none.italic)
        var titleLook = PaywallDoc.Look()
        titleLook.font = "serif"
        titleLook.weight = "heavy"
        titleLook.fontSize = 34
        titleLook.italic = true
        let styled = PaywallLookMath.font(size: 30, weight: .bold, design: .default, type: PaywallType().merged(titleLook))
        XCTAssertEqual(styled.size, 34)
        XCTAssertEqual(styled.weight, .heavy)
        XCTAssertEqual(styled.design, .serif)
        XCTAssertTrue(styled.italic)
        // A child's look lays over its container's, field by field.
        var childLook = PaywallDoc.Look()
        childLook.weight = "medium"
        childLook.weight = "not a weight"
        let inherited = PaywallType().merged(titleLook).merged(childLook)
        XCTAssertEqual(inherited.weight, "heavy", "an unknown weight keeps the inherited one")
        XCTAssertEqual(inherited.font, "serif")
    }

    @MainActor
    func testLooksScreenRenders() throws {
        guard #available(macOS 13, iOS 16, *) else { throw XCTSkip("ImageRenderer needs macOS 13") }
        let doc = try XCTUnwrap(try fixtures()["variants"])
        var content = PaywallContent(doc: doc, appName: "Acme", packages: Self.packages, onPurchase: { _ in }, onClose: {})
        content.scrolls = false
        content.screen = "looks"
        XCTAssertNotNil(ImageRenderer(content: content.frame(width: 390, height: 844)).cgImage)
    }

    func testSavings() {
        // Against the monthly plan ($4.99 a month).
        let s = PaywallPlans.savings([
            ("$monthly", 4.99, 1), ("$annual", 39.99, 12), ("$weekly", 0.99, 0.25),
            ("$lifetime", 99.99, 0), ("$pricey_year", 79.99, 12),
        ])
        XCTAssertEqual(s["$monthly"], "", "the reference saves nothing")
        XCTAssertEqual(s["$annual"], "33%")  // 1 − 3.3325 / 4.99 = 33.2%
        XCTAssertEqual(s["$weekly"], "21%")  // 3.96 a month
        XCTAssertEqual(s["$lifetime"], "", "one-time purchases have no savings")
        XCTAssertEqual(s["$pricey_year"], "", "costing more is not a saving")
        // The shortest plan of a month or more is the reference, even listed last.
        XCTAssertEqual(PaywallPlans.savings([("$y", 60, 12), ("$q", 18, 3)]), ["$y": "17%", "$q": ""])
        XCTAssertEqual(PaywallPlans.savings([("$life", 50, 0)]), ["$life": ""], "no reference, no savings")
        XCTAssertEqual(PaywallText.resolve("Save {{savings}} with a year", appName: "Acme",
            package: PaywallPackageView(id: "a", productName: "A", price: "$39.99", period: "year", pricePerMonth: "$3.33", trial: "", savings: "33%")),
            "Save 33% with a year")
        XCTAssertEqual(PaywallText.resolve("Save {{savings}}!", appName: "Acme", package: Self.packages[0]), "Save!")
    }

    func testPlanCards() throws {
        let doc = try XCTUnwrap(try fixtures()["plans"])
        let top = doc.flow.flatMap(\.blocks)
        XCTAssertEqual(PaywallPlans.cards(in: top), ["$monthly", "$annual", "$premium_monthly", "$premium_annual"])
        let ids = Self.packages.map(\.id)
        // Initial selection: theirs, the highlight, the first card on offer, the first package.
        XCTAssertEqual(PaywallPlans.initialSelection(selected: "$annual", highlight: nil, cards: ["$monthly"], available: ids), "$annual")
        XCTAssertEqual(PaywallPlans.initialSelection(selected: "$gone", highlight: "$annual", cards: ["$monthly"], available: ids), "$annual")
        XCTAssertEqual(PaywallPlans.initialSelection(selected: nil, highlight: nil, cards: ["$premium_monthly", "$annual"], available: ids), "$annual")
        XCTAssertEqual(PaywallPlans.initialSelection(selected: nil, highlight: nil, cards: [], available: ids), "$monthly")

        // A card whose package is not offered is not drawn.
        let cards = doc.allBlocks.filter { $0.package != nil }
        XCTAssertEqual(cards.filter { PaywallPlans.isShown($0, available: ids) }.map(\.package), ["$monthly", "$annual"])
        XCTAssertTrue(PaywallPlans.isShown(top[0], available: []), "other blocks always show")

        // Inside a card, variables speak of the card's package.
        let annual = Self.packages[1]
        XCTAssertEqual(PaywallPlans.scope(card: "$monthly", selected: annual, packages: Self.packages)?.id, "$monthly")
        XCTAssertEqual(PaywallPlans.scope(card: nil, selected: annual, packages: Self.packages)?.id, "$annual")
        XCTAssertEqual(PaywallPlans.scope(card: "$gone", selected: annual, packages: Self.packages)?.id, "$annual")

        // Tiers: opening a tab selects its first plan unless the selection is already there.
        let tabs = try XCTUnwrap(doc.allBlocks.first { $0.type == "tabs" }?.children)
        let all = ids + ["$premium_monthly", "$premium_annual"]
        XCTAssertEqual(PaywallPlans.tierSelection(tab: tabs[1], selected: "$annual", available: all), "$premium_monthly")
        XCTAssertNil(PaywallPlans.tierSelection(tab: tabs[1], selected: "$premium_annual", available: all))
        XCTAssertNil(PaywallPlans.tierSelection(tab: tabs[1], selected: "$annual", available: ids), "no plan of that tier on offer")
        XCTAssertEqual(PaywallPlans.tierSelection(tab: tabs[0], selected: "$premium_annual", available: all), "$monthly")
    }

    func testLookSelectedOverLook() throws {
        let doc = try XCTUnwrap(try fixtures()["plans"])
        let card = try XCTUnwrap(doc.allBlocks.first { $0.package == "$monthly" })
        let merged = (card.look ?? PaywallDoc.Look()).overlaid(with: card.lookSelected)
        XCTAssertEqual(merged.width, "fill", "look's fields stay")
        XCTAssertEqual(merged.background, "#FFF1EC")
        XCTAssertEqual(merged.borderWidth, 2)
        var base = PaywallDoc.Look()
        base.color = "#111111"
        base.weight = "regular"
        var top = PaywallDoc.Look()
        top.weight = "bold"
        let over = base.overlaid(with: top)
        XCTAssertEqual(over.weight, "bold", "look_selected wins")
        XCTAssertEqual(over.color, "#111111")
        XCTAssertEqual(base.overlaid(with: nil), base)
        let text = try XCTUnwrap(card.children?.first { $0.type == "text" })
        XCTAssertEqual(text.lookSelected?.color, "#F04E28")
    }

    func testScreenMediaDecodes() throws {
        let doc = try XCTUnwrap(try fixtures()["plans"])
        let s = doc.flow[0]
        XCTAssertEqual(s.backgroundImage, "https://example.com/bg.jpg")
        XCTAssertEqual(s.backgroundOverlay, "#00000066")
        XCTAssertNil(s.backgroundVideo)
        XCTAssertEqual(s.blocks.first?.resolvedVariant, "hero_fade")
        let json = ##"{"id":"s","name":"S","background_video":"https://example.com/v.mp4","blocks":[]}"##
        XCTAssertEqual(try JSONDecoder().decode(PaywallDoc.Screen.self, from: Data(json.utf8)).backgroundVideo, "https://example.com/v.mp4")
    }

    @MainActor
    func testPlansRender() throws {
        guard #available(macOS 13, iOS 16, *) else { throw XCTSkip("ImageRenderer needs macOS 13") }
        let doc = try XCTUnwrap(try fixtures()["plans"])
        let premium = Self.packages + [
            PaywallPackageView(id: "$premium_monthly", productName: "Premium Monthly", price: "$9.99", period: "month", pricePerMonth: "", trial: ""),
            PaywallPackageView(id: "$premium_annual", productName: "Premium Annual", price: "$79.99", period: "year", pricePerMonth: "$6.67", trial: "", savings: "33%"),
        ]
        let standard = [Self.packages[0], PaywallPackageView(id: "$annual", productName: "Annual", price: "$39.99", period: "year",
                                                             pricePerMonth: "$3.33", trial: "7-day", savings: "33%")]
        let out = ProcessInfo.processInfo.environment["PAYWALL_RENDER_DIR"]
        for (name, packages) in [("standard", standard), ("premium", premium)] {
            var content = PaywallContent(doc: doc, appName: "Acme", packages: packages, onPurchase: { _ in }, onClose: {})
            content.scrolls = false
            let image = try XCTUnwrap(ImageRenderer(content: content.frame(width: 390, height: 844)).cgImage, name)
            if let out {
                let url = URL(fileURLWithPath: out).appendingPathComponent("plans-\(name).png")
                let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(dest, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(dest))
            }
        }
    }

    /// The server's `paywall.Arts`.
    static let arts = ["stars", "mountains", "waves", "blobs", "planet", "sunburst", "gift", "synthwave", "hills", "confetti"]

    func testArtColoursMatchTheWeb() {
        // Expected strings from cashier-cloud's artColor (node, dist build).
        let palette = ["A": "#F04E28", "AT": "#FFFFFF", "T": "#111114", "B": "#FFFFFF", "S": "#F4F4F6", "M": "#6B6B76"]
        let expected = [
            "A": "rgba(240, 78, 40, 1)",
            "A+40*0.8@0.5": "rgba(209, 181, 15, 0.5)",
            "A-20*0.35": "rgba(92, 6, 19, 1)",
            "#FFFFFF@0.61": "rgba(255, 255, 255, 0.61)",
            "S*0.9": "rgba(217, 217, 224, 1)",
            "M@0.3": "rgba(107, 107, 118, 0.3)",
            "A+180": "rgba(40, 202, 240, 1)",
            "T*2": "rgba(34, 34, 40, 1)",
            "B-10*0.5@0.25": "rgba(128, 128, 128, 0.25)",
            "AT@0.8": "rgba(255, 255, 255, 0.8)",
            "#FFD76A+15*1.2": "rgba(255, 254, 178, 1)",
        ]
        for (token, css) in expected {
            XCTAssertEqual(PaywallArt.color(token, palette: palette)?.css, css, token)
        }
        XCTAssertEqual(PaywallArt.color("A+40*0.8@0.5", palette: ["A": "#8B5CF6"])?.css, "rgba(236, 28, 242, 0.5)")
        XCTAssertNil(PaywallArt.color("nope", palette: palette), "unreadable is transparent")
    }

    func testArtPathParser() {
        let square = PaywallArt.path("M0 0 L10 0 L10 10 L0 10 Z")
        XCTAssertEqual(square.boundingRect, CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertTrue(square.contains(CGPoint(x: 5, y: 5)))
        // Commas, negatives run together, implicit line-tos after M.
        let tight = PaywallArt.path("M-5-5 5,-5L5,5-5,5Z")
        XCTAssertEqual(tight.boundingRect, CGRect(x: -5, y: -5, width: 10, height: 10))
        let curve = PaywallArt.path("M0 100 C0 0 100 0 100 100 Z")
        XCTAssertEqual(curve.boundingRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(curve.boundingRect.maxX, 100, accuracy: 0.001)
        XCTAssertEqual(curve.boundingRect.minY, 25, accuracy: 0.5, "a cubic's top is at 3/4 of its control height")
        XCTAssertEqual(PaywallArt.path("M.5.5L1.5.5").boundingRect.width, 1, accuracy: 0.0001)
    }

    @MainActor
    func testEveryArtDecodesAndRenders() throws {
        XCTAssertEqual(Set(PaywallArt.scenes.keys), Set(Self.arts))
        for name in Self.arts { XCTAssertFalse(PaywallArt.scenes[name]?.isEmpty ?? true, name) }
        XCTAssertEqual(PaywallArt.swing(0, duration: 2, delay: 0), 0)
        XCTAssertEqual(PaywallArt.swing(2, duration: 2, delay: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(PaywallArt.swing(4, duration: 2, delay: 0), 0, accuracy: 0.0001, "alternates back")
        XCTAssertEqual(PaywallArt.swing(1, duration: 2, delay: 3), 0, "rests until its delay")
        guard #available(macOS 13, iOS 16, *) else { throw XCTSkip("ImageRenderer needs macOS 13") }
        let out = ProcessInfo.processInfo.environment["PAYWALL_RENDER_DIR"]
        for (label, accent) in [("orange", "#F04E28"), ("violet", "#7C5CFF")] {
            let palette = ["A": accent, "AT": "#FFFFFF", "T": "#111114", "B": "#FFFFFF", "S": "#F4F4F6", "M": "#6B6B76"]
            // All ten scenes in a grid, like the web's art picker.
            let grid = VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<2, id: \.self) { col in
                            PaywallArtView(name: Self.arts[row * 2 + col], palette: palette, animates: false)
                                .frame(width: 200, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.white)
            let renderer = ImageRenderer(content: grid)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, label)
            if let out {
                let url = URL(fileURLWithPath: out).appendingPathComponent("art-\(label).png")
                let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(dest, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(dest))
            }
        }
    }

    func testSavingsTextHidesWithoutSavings() {
        let annual = PaywallPackageView(id: "$annual", productName: "Annual", price: "$39.99", period: "year", pricePerMonth: "", trial: "", savings: "33%")
        let monthly = Self.packages[0]
        XCTAssertTrue(PaywallText.hidesForSavings("Save {{savings}} with a year", package: monthly))
        XCTAssertTrue(PaywallText.hidesForSavings("SAVE {{ savings }}", package: nil))
        XCTAssertFalse(PaywallText.hidesForSavings("Save {{savings}} with a year", package: annual))
        XCTAssertFalse(PaywallText.hidesForSavings("{{price}} / {{period}}", package: monthly), "only savings text hides")
        XCTAssertFalse(PaywallText.hidesForSavings(nil, package: monthly))
    }

    @MainActor
    func testCardBadgesDecodeAndRender() throws {
        guard #available(macOS 13, iOS 16, *) else { throw XCTSkip("ImageRenderer needs macOS 13") }
        let json = ##"{"version":2,"theme":{"background":"#FFFFFF","surface":"#F4F4F6","text":"#111114","muted":"#6B6B76","accent":"#F04E28","accent_text":"#FFFFFF","radius":16,"font":"system"},"screens":[{"id":"s","name":"S","blocks":[{"id":"row","type":"stack","axis":"horizontal","children":[{"id":"m","type":"custom","package":"$monthly","badge":"SAVE {{savings}}","children":[{"id":"mt","type":"title","text":"Monthly","size":"s"}]},{"id":"a","type":"custom","package":"$annual","badge":"BEST · SAVE {{savings}}","children":[{"id":"at","type":"title","text":"Yearly","size":"s"},{"id":"as","type":"text","text":"{{savings}} off"}]}]},{"id":"t","type":"text","text":"Save {{savings}}"},{"id":"c","type":"cta","text":"Continue"}]}]}"##
        let doc = try JSONDecoder().decode(PaywallDoc.self, from: Data(json.utf8))
        let cards = doc.allBlocks.filter { $0.package != nil }
        XCTAssertEqual(cards.map(\.badge), ["SAVE {{savings}}", "BEST · SAVE {{savings}}"])
        let packages = [Self.packages[0], PaywallPackageView(id: "$annual", productName: "Annual", price: "$39.99", period: "year",
                                                              pricePerMonth: "$3.33", trial: "", savings: "33%")]
        var content = PaywallContent(doc: doc, appName: "Acme", packages: packages, onPurchase: { _ in })
        content.scrolls = false
        let renderer = ImageRenderer(content: content.frame(width: 390, height: 500))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        if let out = ProcessInfo.processInfo.environment["PAYWALL_RENDER_DIR"] {
            let url = URL(fileURLWithPath: out).appendingPathComponent("badges.png")
            let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(dest, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
        }
    }

    func testVariantsDocumentShowsEveryVariant() throws {
        XCTAssertEqual(PaywallVariants.table, Self.variants)
        let doc = try XCTUnwrap(try fixtures()["variants"])
        XCTAssertEqual(doc.flow.count, 10)
        let shown = Set(doc.allBlocks.map { "\($0.type)/\($0.resolvedVariant)" })
        for (type, list) in Self.variants {
            for v in list {
                XCTAssertTrue(shown.contains("\(type)/\(v)"), "the variants document lacks \(type) \(v)")
            }
        }
    }

    @MainActor
    func testUnknownVariantDrawsTheDefault() throws {
        let json = ##"{"id":"t","type":"timeline","variant":"sparkly","items":[{"icon":"lock","title":"Today"},{"icon":"star","title":"Day 7"}]}"##
        let b = try JSONDecoder().decode(PaywallDoc.Block.self, from: Data(json.utf8))
        XCTAssertEqual(b.variant, "sparkly")
        XCTAssertEqual(b.resolvedVariant, "line")
        XCTAssertEqual(PaywallVariants.resolve(type: "button", variant: nil), "rounded")
        XCTAssertEqual(PaywallVariants.resolve(type: "award", variant: ""), "laurel")
        XCTAssertEqual(PaywallVariants.resolve(type: "title", variant: "large"), "", "types without variants have none")
        guard #available(macOS 13, iOS 16, *) else { return }
        let docJSON = ##"{"version":2,"theme":{"background":"#FFFFFF","surface":"#EEEEEE","text":"#000000","muted":"#666666","accent":"#FF0000","accent_text":"#FFFFFF","radius":8,"font":"system"},"screens":[{"id":"s","name":"S","blocks":[{"id":"t","type":"timeline","variant":"sparkly","items":[{"icon":"lock","title":"Today"},{"icon":"star","title":"Day 7"}]},{"id":"h","type":"header","variant":"sparkly","text":"Hi"},{"id":"b","type":"button","variant":"sparkly","style":"outline","text":"Go","action":"next"},{"id":"p","type":"packages"},{"id":"c","type":"cta","text":"Buy"}]}]}"##
        let doc = try JSONDecoder().decode(PaywallDoc.self, from: Data(docJSON.utf8))
        var content = PaywallContent(doc: doc, appName: "Acme", packages: Self.packages, onPurchase: { _ in })
        content.scrolls = false
        let renderer = ImageRenderer(content: content.frame(width: 390, height: 844))
        XCTAssertNotNil(renderer.cgImage)
    }

    func testNestedBlocksDecode() throws {
        let json = ##"{"id":"s","type":"sheet","radius":24,"children":[{"id":"c","type":"custom","axis":"horizontal","justify":"space_between","gap":8,"padding":12,"background":"#FFF4E8","border":"#F04E28","children":[{"id":"t","type":"text","text":"Hi"}]},{"id":"sw","type":"switch","text":"Trial","package_on":"$annual","package_off":"$monthly"},{"id":"cd","type":"countdown","until":"2026-12-31T23:59:00Z","minutes":0},{"id":"sp","type":"social_proof","text":"Loved","images":["https://example.com/a.png"]},{"id":"v","type":"video","url":"https://example.com/v.mp4","poster":"https://example.com/p.png"},{"id":"h","type":"header","back":true},{"id":"car","type":"carousel","interval":3,"children":[{"id":"p1","type":"title","text":"One"}]}]}"##
        let b = try JSONDecoder().decode(PaywallDoc.Block.self, from: Data(json.utf8))
        XCTAssertEqual(b.radius, 24)
        XCTAssertEqual(b.children?.count, 7)
        let custom = try XCTUnwrap(b.children?.first)
        XCTAssertEqual(custom.axis, "horizontal")
        XCTAssertEqual(custom.justify, "space_between")
        XCTAssertEqual(custom.gap, 8)
        XCTAssertEqual(custom.padding, 12)
        XCTAssertEqual(custom.background, "#FFF4E8")
        XCTAssertEqual(custom.border, "#F04E28")
        XCTAssertEqual(custom.children?.first?.text, "Hi")
        XCTAssertEqual(b.children?[1].packageOn, "$annual")
        XCTAssertEqual(b.children?[1].packageOff, "$monthly")
        XCTAssertEqual(b.children?[2].until, "2026-12-31T23:59:00Z")
        XCTAssertEqual(b.children?[3].images, ["https://example.com/a.png"])
        XCTAssertEqual(b.children?[4].poster, "https://example.com/p.png")
        XCTAssertEqual(b.children?[5].back, true)
        XCTAssertEqual(b.children?[6].interval, 3)
        XCTAssertEqual(b.withDescendants.map(\.id), ["s", "c", "t", "sw", "cd", "sp", "v", "h", "car", "p1"])
    }

    func testCountdownArithmetic() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        // Minutes count from when the countdown was first shown.
        let target = try XCTUnwrap(PaywallCountdown.target(until: nil, minutes: 30, start: start))
        XCTAssertEqual(target.timeIntervalSince(start), 1800)
        var left = PaywallCountdown.remaining(to: target, now: start)
        XCTAssertEqual([left.hours, left.minutes, left.seconds], [0, 30, 0])
        left = PaywallCountdown.remaining(to: target, now: start.addingTimeInterval(61.4))
        XCTAssertEqual([left.hours, left.minutes, left.seconds], [0, 28, 58])
        left = PaywallCountdown.remaining(to: target, now: start.addingTimeInterval(5000))
        XCTAssertEqual([left.hours, left.minutes, left.seconds], [0, 0, 0], "stops at zero")
        // A fixed moment, with or without fractional seconds; it wins over minutes.
        let until = try XCTUnwrap(PaywallCountdown.target(until: "2026-12-31T23:59:00Z", minutes: 5, start: start))
        XCTAssertEqual(until.timeIntervalSince1970, 1_798_761_540)
        let fractional = try XCTUnwrap(PaywallCountdown.target(until: "2026-12-31T23:59:00.500+01:00", minutes: nil, start: start))
        XCTAssertEqual(fractional.timeIntervalSince1970, 1_798_761_540 - 3600 + 0.5, accuracy: 0.001)
        left = PaywallCountdown.remaining(to: until, now: until.addingTimeInterval(-(26 * 3600 + 5 * 60 + 7)))
        XCTAssertEqual([left.hours, left.minutes, left.seconds], [26, 5, 7])
        XCTAssertNil(PaywallCountdown.target(until: "tomorrow", minutes: nil, start: start))
        XCTAssertNil(PaywallCountdown.target(until: nil, minutes: 0, start: start))
        left = PaywallCountdown.remaining(to: nil, now: start)
        XCTAssertEqual([left.hours, left.minutes, left.seconds], [0, 0, 0])
    }

    func testSwitchPicksItsPackages() {
        XCTAssertTrue(PaywallSwitch.isOn(selected: "$annual", packageOn: "$annual"))
        XCTAssertFalse(PaywallSwitch.isOn(selected: "$monthly", packageOn: "$annual"))
        XCTAssertFalse(PaywallSwitch.isOn(selected: nil, packageOn: nil))
        XCTAssertEqual(PaywallSwitch.package(on: true, packageOn: "$annual", packageOff: "$monthly"), "$annual")
        XCTAssertEqual(PaywallSwitch.package(on: false, packageOn: "$annual", packageOff: "$monthly"), "$monthly")
    }

    func testVariablesResolveLikeTheWebSDK() {
        let annual = Self.packages[1]
        XCTAssertEqual(PaywallText.resolve("{{price}} / {{period}}", appName: "Acme", package: annual), "$39.99 / year")
        XCTAssertEqual(PaywallText.resolve("Start my {{trial}} trial", appName: "Acme", package: Self.packages[0]), "Start my trial")
        XCTAssertEqual(PaywallText.resolve("Unlock {{app_name}}{{ unknown }}!", appName: "Acme", package: nil), "Unlock Acme!")
        XCTAssertEqual(PaywallText.resolve("After {{trial}}: billed {{price}}.", appName: "Acme", package: Self.packages[0]), "After: billed $4.99.")
    }

    func testSafeURLs() {
        XCTAssertNotNil(PaywallURL.safe("https://example.com/a.png"))
        XCTAssertNotNil(PaywallURL.safe("http://localhost:8080/media/a.png"), "console uploads in development")
        XCTAssertNotNil(PaywallURL.safe("http://127.0.0.1:3000/media/a.mp4"))
        XCTAssertNotNil(PaywallURL.safe("HTTP://LOCALHOST/media/a.png"), "scheme and host are case-insensitive")
        XCTAssertNil(PaywallURL.safe("http://example.com/a.png"), "plain http elsewhere is refused")
        XCTAssertNil(PaywallURL.safe("javascript:alert(1)"))
        XCTAssertNil(PaywallURL.safe("http://localhost.evil.com/a.png"), "only exactly localhost")
        XCTAssertNil(PaywallURL.safe("http://127.0.0.1.evil.com/a.png"))
        XCTAssertNil(PaywallURL.safe("https:///no-host"))
        XCTAssertNil(PaywallURL.safe("file:///etc/passwd"))
        XCTAssertNil(PaywallURL.safe(""))
        XCTAssertNil(PaywallURL.safe(nil))
    }

    func testHexColours() {
        XCTAssertNotNil(Color(paywallHex: "#FFF"))
        XCTAssertNotNil(Color(paywallHex: "#1B1037"))
        XCTAssertNotNil(Color(paywallHex: "#1B103780"))
        XCTAssertNil(Color(paywallHex: "red"))
        XCTAssertNil(Color(paywallHex: "#12345"))
    }

    func testVersionOneReadsAsOneScreen() throws {
        let json = ##"{"version":1,"theme":{"background":"#FFFFFF","surface":"#EEEEEE","text":"#000000","muted":"#666666","accent":"#FF0000","accent_text":"#FFFFFF","radius":8,"font":"system"},"blocks":[{"id":"p","type":"packages"},{"id":"c","type":"cta","text":"Buy"}]}"##
        let doc = try JSONDecoder().decode(PaywallDoc.self, from: Data(json.utf8))
        XCTAssertTrue(doc.isSupported)
        XCTAssertEqual(doc.flow.map(\.id), ["paywall"])
        XCTAssertEqual(doc.initialScreenID, "paywall")
        XCTAssertEqual(doc.flow[0].blocks.count, 2)
    }

    func testNewerSchemaIsNotGuessedAt() throws {
        let json = ##"{"version":3,"theme":{"background":"#FFFFFF","surface":"#EEEEEE","text":"#000000","muted":"#666666","accent":"#FF0000","accent_text":"#FFFFFF","radius":8,"font":"system"},"blocks":[]}"##
        let doc = try JSONDecoder().decode(PaywallDoc.self, from: Data(json.utf8))
        XCTAssertFalse(doc.isSupported)
    }

    func testOfferingsCarryThePaywallAndSurviveABadOne() throws {
        let good = try String(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "paywalls", withExtension: "json", subdirectory: "Fixtures")), encoding: .utf8)
        let classic = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(good.utf8)) as? [String: Any])["classic"]!
        let classicJSON = String(data: try JSONSerialization.data(withJSONObject: classic), encoding: .utf8)!
        let body = """
        {"current_offering":"a","app_name":"Acme","offerings":[
          {"id":"a","packages":[],"paywall":\(classicJSON)},
          {"id":"b","packages":[],"paywall":{"version":"not a number"}}]}
        """
        let wire = try JSONDecoder().decode(OfferingsResponse.self, from: Data(body.utf8))
        XCTAssertEqual(wire.appName, "Acme")
        XCTAssertNotNil(wire.offerings[0].paywall)
        XCTAssertNil(wire.offerings[1].paywall, "an unreadable paywall leaves the offering usable")
    }

    /// The web editor's sample plans (paywall-editor.js SAMPLE), priced
    /// the same way, so renders line up with the web gallery.
    static let sample: [PaywallPackageView] = {
        let plans: [(id: String, name: String, cents: Int, months: Double, trial: String)] = [
            ("$weekly", "Weekly", 399, 0.25, ""), ("$monthly", "Monthly", 999, 1, ""), ("$six_month", "6 months", 3999, 6, ""),
            ("$annual", "Yearly", 6999, 12, "7-day"), ("$lifetime", "Lifetime", 11999, 0, ""),
            ("$premium_monthly", "Premium monthly", 1999, 1, ""), ("$premium_annual", "Premium yearly", 14999, 12, ""),
        ]
        let money = { (cents: Int) in String(format: "$%d.%02d", cents / 100, cents % 100) }
        let savings = PaywallPlans.savings(plans.map { ($0.id, Double($0.cents) / 100, $0.months) })
        return plans.map { p in
            let period = p.months == 0.25 ? "week" : p.months == 1 ? "month" : p.months == 12 ? "year" : p.months == 0 ? "" : "\(Int(p.months)) months"
            let perMonth = p.months > 1 ? money(Int((Double(p.cents) / p.months).rounded())) : ""
            return PaywallPackageView(id: p.id, productName: p.name, price: money(p.cents), period: period, pricePerMonth: perMonth,
                                      trial: p.trial, savings: savings[p.id] ?? "")
        }
    }()

    func testSamplePlansSave() {
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: Self.sample.map { ($0.id, $0.savings) }), [
            "$weekly": "", "$monthly": "", "$six_month": "33%", "$annual": "42%", "$lifetime": "",
            "$premium_monthly": "", "$premium_annual": "",
        ])
    }

    @MainActor
    func testEveryDocumentRenders() throws {
        guard #available(macOS 13, iOS 16, *) else { throw XCTSkip("ImageRenderer needs macOS 13") }
        let out = ProcessInfo.processInfo.environment["PAYWALL_RENDER_DIR"]
        // Every screen of every document, drawn one at a time, with every sample plan.
        var gallery: [(String, CGImage)] = []
        for (name, doc) in try fixtures().sorted(by: { $0.key < $1.key }) {
            for screen in doc.flow {
                var content = PaywallContent(doc: doc, appName: "QA App", packages: Self.sample, onPurchase: { _ in }, onClose: {})
                content.scrolls = false
                content.screen = screen.id
                let view = content.frame(width: 390, height: 844)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage, "\(name)/\(screen.id) did not render")
                XCTAssertEqual(image.width, 780, name)
                if let out {
                    try Self.writePNG(image, to: URL(fileURLWithPath: out).appendingPathComponent("\(name)-\(screen.id).png"))
                    if !name.hasPrefix("steps_") && name != "variants" && name != "showcase" { gallery.append(("\(name)/\(screen.id)", image)) }
                }
            }
        }
        // Contact sheets of the gallery templates, twelve screens a sheet.
        if let out {
            for (n, start) in stride(from: 0, to: gallery.count, by: 12).enumerated() {
                let page = Array(gallery[start..<min(start + 12, gallery.count)])
                let cellW = 390, cellH = 844 + 28, cols = 6, rows = (page.count + cols - 1) / cols
                guard let ctx = CGContext(data: nil, width: cols * cellW, height: rows * cellH, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: cols * cellW, height: rows * cellH))
                for (i, (label, image)) in page.enumerated() {
                    let x = (i % cols) * cellW, y = (rows - 1 - i / cols) * cellH
                    ctx.draw(image, in: CGRect(x: x + 4, y: y + 4, width: cellW - 8, height: 844 - 8))
                    let text = ImageRenderer(content: Text(label).font(.system(size: 16, weight: .semibold)).foregroundColor(.black)
                        .frame(width: CGFloat(cellW), height: 24))
                    if let t = text.cgImage { ctx.draw(t, in: CGRect(x: x, y: y + 844, width: cellW, height: 24)) }
                }
                if let sheet = ctx.makeImage() {
                    try Self.writePNG(sheet, to: URL(fileURLWithPath: out).appendingPathComponent("gallery-\(n + 1).png"))
                }
            }
        }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
