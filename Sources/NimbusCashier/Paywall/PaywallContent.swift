import AVFoundation
import AVKit
import SwiftUI

/// Draws a paywall document with already-priced packages. `PaywallView`
/// wraps it with StoreKit and Cashier; use this directly to render a paywall
/// with your own purchase handling (or in previews).
public struct PaywallContent: View {
    public let doc: PaywallDoc
    public let appName: String
    public let packages: [PaywallPackageView]
    public var isPurchasing: Bool
    public var onPurchase: (PaywallPackageView) -> Void
    public var onRestore: () -> Void
    public var onClose: (() -> Void)?
    /// Called when a button moves the flow to another screen.
    public var onNavigate: ((String) -> Void)?
    /// Called when a button carrying an answer (Feedback / Marketing Consent
    /// screens) is tapped, before the button's action runs.
    public var onAnswer: ((PaywallAnswer) -> Void)?
    /// Draw this one screen and do not navigate (previews, tests). Without
    /// it the flow opens on the initial screen and buttons move through it.
    public var screen: String?

    /// Wrap the blocks in a ScrollView (always, outside tests: ImageRenderer
    /// cannot draw scroll view contents).
    var scrolls = true
    /// While drawing inside a plan card: its package. Variables resolve
    /// against it and `look_selected` applies when it is the selected one.
    private var cardPackage: String? = nil
    /// While drawing a horizontal stack's child: blocks take their natural
    /// width (the web's flex 0 1 auto) instead of the full width.
    private var inRow = false
    /// The full width, except for a row's children.
    private var greedy: CGFloat? { inRow ? nil : .infinity }

    @State private var selected: String?
    @State private var screenID: String?
    /// Screens visited before this one, for "back".
    @State private var history: [String] = []
    /// Selected tab per tabs block id.
    @State private var tabs: [String: Int] = [:]
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Screens whose entrance has run (while they are on show).
    @State private var entered: Set<String> = []

    /// Motion only when drawn live and the user has not asked for less.
    private var animates: Bool { scrolls && !reduceMotion }

    public init(doc: PaywallDoc, appName: String, packages: [PaywallPackageView], isPurchasing: Bool = false,
                onPurchase: @escaping (PaywallPackageView) -> Void, onRestore: @escaping () -> Void = {},
                onClose: (() -> Void)? = nil) {
        self.doc = doc
        self.appName = appName
        self.packages = packages
        self.isPurchasing = isPurchasing
        self.onPurchase = onPurchase
        self.onRestore = onRestore
        self.onClose = onClose
    }

    /// The screen on show's theme (its own, else the document's).
    private var theme: PaywallDoc.Theme { doc.theme(for: currentScreen) }
    private var radius: CGFloat { CGFloat(min(max(theme.radius, 0), 32)) }
    private var textColor: Color { Color(paywallHex: theme.text) ?? .primary }
    private var mutedColor: Color { Color(paywallHex: theme.muted) ?? .secondary }
    private var surfaceColor: Color { Color(paywallHex: theme.surface) ?? Color.gray.opacity(0.12) }
    /// Cards sitting on a surface-coloured box (a sheet, a custom box) take
    /// the page colour instead, or they would vanish into it.
    private func cardColor(_ onSurface: Bool) -> Color {
        onSurface ? (Color(paywallHex: theme.background) ?? .white) : surfaceColor
    }
    private var accentColor: Color { Color(paywallHex: theme.accent) ?? .accentColor }
    private var accentTextColor: Color { Color(paywallHex: theme.accentText) ?? .white }

    /// The theme for one block, `fill` depending on what it sits on.
    private func style(_ onSurface: Bool) -> PaywallStyle {
        PaywallStyle(text: textColor, muted: mutedColor, surface: surfaceColor,
                     background: Color(paywallHex: theme.background) ?? .white, accent: accentColor,
                     accentText: accentTextColor, fill: cardColor(onSurface), radius: radius, design: design)
    }

    private var design: Font.Design {
        switch theme.font {
        case "rounded": return .rounded
        case "serif": return .serif
        case "mono": return .monospaced
        default: return .default
        }
    }

    private var currentID: String? {
        PaywallPlans.initialSelection(selected: selected, highlight: doc.allBlocks.first { $0.type == "packages" }?.highlight,
                                      cards: PaywallPlans.cards(in: doc.flow.flatMap(\.blocks)), available: packages.map(\.id))
    }

    private var current: PaywallPackageView? { packages.first { $0.id == currentID } }

    private func resolve(_ text: String?) -> String {
        PaywallText.resolve(text ?? "", appName: appName,
                            package: scopePackage)
    }

    /// The screen on show: the pinned one, else where the flow has got to.
    private var currentScreen: PaywallDoc.Screen {
        let all = doc.flow
        let id = screen ?? screenID ?? doc.initialScreenID
        return all.first { $0.id == id } ?? all.first ?? PaywallDoc.Screen(id: "paywall", name: "Paywall", background: nil,
            backgroundEnd: nil, paddingX: nil, paddingY: nil, spacing: nil, justify: nil, align: nil, blocks: [])
    }

    private func go(_ id: String?) {
        guard screen == nil, let id, doc.flow.contains(where: { $0.id == id }) else { return }
        let from = currentScreen.id
        withAnimation(.easeInOut(duration: 0.3)) {
            if from != id { history.append(from) }
            screenID = id
        }
        onNavigate?(id)
    }

    /// Back to the previous screen in the history; nothing when there is none.
    private func back() {
        guard screen == nil, let id = history.last else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            history.removeLast()
            screenID = id
        }
        onNavigate?(id)
    }

    /// The screen's background video (live only) or image, and the overlay
    /// over it: over the background colour, under the effect and blocks.
    @ViewBuilder
    private func screenMedia(_ s: PaywallDoc.Screen) -> some View {
        let video = PaywallURL.safe(s.backgroundVideo)
        let image = PaywallURL.safe(s.backgroundImage)
        Group {
            if let video, scrolls {
                PaywallFillVideo(url: video)
            } else if let image {
                Color.clear.overlay(
                    AsyncImage(url: image) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                )
                .clipped()
            }
            if let overlay = s.backgroundOverlay.flatMap({ Color(paywallHex: $0) }) {
                overlay
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A screen's own background overrides the theme's.
    private func background(_ s: PaywallDoc.Screen) -> AnyView {
        let topHex = s.background ?? theme.background
        let endHex = s.background != nil ? s.backgroundEnd : theme.backgroundEnd
        let top = Color(paywallHex: topHex) ?? .white
        if let endHex, let end = Color(paywallHex: endHex) {
            return AnyView(LinearGradient(colors: [top, end], startPoint: .top, endPoint: .bottom))
        }
        return AnyView(top)
    }

    public var body: some View {
        let s = currentScreen
        return ZStack(alignment: .topTrailing) {
            background(s).ignoresSafeArea()
            screenMedia(s)
            if let effect = s.effect, !effect.isEmpty {
                PaywallEffect(kind: effect, accent: accentColor, text: textColor, animates: animates)
                    .ignoresSafeArea()
                    .id("\(s.id)/\(effect)")
                    .zIndex(0)
            }
            if doc.isSupported {
                Group {
                    if scrolls {
                        GeometryReader { geo in
                            ScrollView { screenBody(s).frame(minHeight: geo.size.height) }
                        }
                    } else {
                        screenBody(s).frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                    }
                }
                .onAppear { entered.insert(s.id) }
                .onDisappear { entered.remove(s.id) }
                .id(s.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                // Always over the effect, including while screens swap.
                .zIndex(1)
            } else {
                Text("Update the app to see this offer.")
                    .foregroundColor(mutedColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(mutedColor)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(surfaceColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .padding(12)
                .zIndex(2)
            }
        }
        .font(.system(size: 15, design: design))
        .foregroundColor(textColor)
    }

    /// A screen: its blocks, then any bottom sheet pinned under them, edge
    /// to edge.
    private func screenBody(_ s: PaywallDoc.Screen) -> some View {
        let sheets = s.blocks.filter { $0.type == "sheet" }
        return VStack(spacing: 0) {
            stack(s, blocks: s.blocks.filter { $0.type != "sheet" }, bottomPadding: sheets.isEmpty ? nil : CGFloat(s.spacing ?? 14))
            let top = s.blocks.count - sheets.count
            ForEach(Array(sheets.enumerated()), id: \.element.id) { i, b in
                sheetBlock(b, in: s)
                    .modifier(PaywallBox(look: b.look, align: .center))
                    .transformEnvironment(\.paywallType) { $0 = $0.merged(b.look) }
                    .modifier(entrance(s, index: top + i))
            }
        }
    }

    /// A screen's blocks, laid out as the screen says: padding, spacing and
    /// where they sit vertically.
    private func stack(_ s: PaywallDoc.Screen, blocks: [PaywallDoc.Block], bottomPadding: CGFloat?) -> some View {
        let spacing = CGFloat(s.spacing ?? 14)
        let justify = s.justify ?? "start"
        let py = CGFloat(s.paddingY ?? 28)
        let px = CGFloat(s.paddingX ?? 22)
        let top = onClose == nil ? py : (blocks.first?.type == "header" ? 12 : max(52, py))
        return VStack(alignment: .leading, spacing: justify == "space_between" ? 0 : spacing) {
            if justify == "center" || justify == "end" { Spacer(minLength: 0) }
            ForEach(Array(blocks.filter(isVisible).enumerated()), id: \.element.id) { i, b in
                if justify == "space_between" && i > 0 { Spacer(minLength: spacing) }
                // Hero media bleeds to the screen's edges, and to its top when first.
                let hero = ["image", "video", "art"].contains(b.type) && b.resolvedVariant != "inline"
                block(b, in: s)
                    .padding(.horizontal, hero ? -px : 0)
                    .padding(.top, hero && i == 0 ? -top : 0)
                    .modifier(entrance(s, index: i))
            }
            if justify != "end" && justify != "space_between" { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, px)
        // Clear of the close button when there is one (same as the web); a
        // header on top shares the close button's row instead.
        .padding(.top, top)
        .padding(.bottom, bottomPadding ?? CGFloat(s.paddingY ?? 20))
    }

    /// A top-level block's entrance: the index-th to come in, 0.07s apart
    /// (the sheet last). At rest when not animating.
    private func entrance(_ s: PaywallDoc.Screen, index: Int) -> PaywallEntrance {
        PaywallEntrance(kind: animates ? s.entrance : nil, shown: entered.contains(s.id), delay: 0.07 * Double(index))
    }

    private func alignment(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen) -> (HorizontalAlignment, TextAlignment, Alignment) {
        switch b.align ?? s.align {
        case "center": return (.center, .center, .center)
        case "right": return (.trailing, .trailing, .trailing)
        default: return (.leading, .leading, .leading)
        }
    }

    /// A block with its look: the box around it, and its type passed down to
    /// its text (and its children's).
    /// A plan card (a stack or custom box with a package) is a radio button
    /// that selects its package, drawn only when the offering has it; what
    /// is inside it speaks of its package.
    private func block(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen, onSurface: Bool = false) -> AnyView {
        guard isVisible(b) else { return AnyView(EmptyView()) }
        guard let pkg = b.package, !pkg.isEmpty, b.type == "stack" || b.type == "custom" else {
            return AnyView(styledBlock(b, in: s, onSurface: onSurface))
        }
        var card = self
        card.cardPackage = pkg
        let on = pkg == currentID
        return AnyView(
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { selected = pkg }
            } label: {
                card.styledBlock(b, in: s, onSurface: onSurface)
                    .contentShape(Rectangle())
                    // The badge straddles the card's top edge without taking room.
                    .overlay(alignment: .top) {
                        // Its centre on the card's top edge (the guide must sit outside the
                        // conditional content to reach the overlay).
                        card.badge(b).alignmentGuide(.top) { d in d[VerticalAlignment.center] }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        )
    }

    /// Whether a block is drawn at all: a plan card only when its package is
    /// offered; text about {{savings}} only when its package saves something.
    private func isVisible(_ b: PaywallDoc.Block) -> Bool {
        guard PaywallPlans.isShown(b, available: packages.map(\.id)) else { return false }
        if ["title", "text", "button"].contains(b.type) {
            return !PaywallText.hidesForSavings(b.text, package: scopePackage)
        }
        return true
    }

    /// The package text here speaks of (the card's inside a plan card).
    private var scopePackage: PaywallPackageView? {
        PaywallPlans.scope(card: cardPackage, selected: current, packages: packages)
    }

    /// A plan card's badge: an accent pill centred on its top border.
    @ViewBuilder
    private func badge(_ b: PaywallDoc.Block) -> some View {
        if let text = b.badge, !text.isEmpty, !PaywallText.hidesForSavings(text, package: scopePackage) {
            Text(resolve(text))
                .font(.system(size: 11, weight: .bold, design: design))
                .foregroundColor(accentTextColor)
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, 3).padding(.horizontal, 9)
                .background(Capsule().fill(accentColor))
        }
    }

    private func styledBlock(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen, onSurface: Bool) -> some View {
        let look = effectiveLook(b)
        return blockBody(b, in: s, onSurface: onSurface)
            .modifier(PaywallBox(look: look, align: alignment(b, in: s).2, places: !inRow))
            .transformEnvironment(\.paywallType) { $0 = $0.merged(look) }
    }

    /// `look`, with `look_selected` over it while this block's plan card is selected.
    private func effectiveLook(_ b: PaywallDoc.Block) -> PaywallDoc.Look? {
        var look = b.look
        if let top = b.lookSelected, let card = cardPackage, card == currentID {
            look = (look ?? PaywallDoc.Look()).overlaid(with: top)
        }
        // A custom box keeps its own corners unless the look sets some (as
        // on the web, where the look sits on the card's own box).
        if b.type == "custom", var l = look, l.radius == nil, l.corners == nil {
            l.radius = positive(b.radius) ?? Double(radius)
            look = l
        }
        return look
    }

    @ViewBuilder
    private func blockBody(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen, onSurface: Bool = false) -> some View {
        let (_, textAlign, frameAlign) = alignment(b, in: s)
        let card = cardColor(onSurface)
        switch b.type {
        case "icon":
            let fixed: CGFloat? = {
                if case .fixed(let w) = PaywallLookMath.size(b.look?.width, b.look?.widthPx) { return w }
                return nil
            }()
            let px = fixed ?? CGFloat(["s": 40, "m": 56, "l": 72, "xl": 96][b.size ?? "l"] ?? 72)
            PaywallIconView(symbol: PaywallIcons.symbol(b.icon ?? "star"), emoji: b.emoji, size: px, variant: b.resolvedVariant,
                            style: style(onSurface), accent2: Color(paywallHex: theme.accent, hueShift: 30) ?? accentColor,
                            animates: animates)
                .frame(maxWidth: greedy, alignment: frameAlign)
        case "button":
            buttonBlock(b, in: s, onSurface: onSurface)
        case "spacer":
            Color.clear.frame(height: ["s": 8, "m": 16, "l": 32, "xl": 48][b.size ?? "m"] ?? 16)
        case "image":
            if let url = PaywallURL.safe(b.url) {
                let hero = b.resolvedVariant != "inline"
                let h = CGFloat(min(positive(b.height) ?? (hero ? 260 : 180), 480))
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    card
                }
                .frame(maxWidth: .infinity)
                .frame(height: h)
                .clipShape(RoundedRectangle(cornerRadius: hero ? 0 : radius, style: .continuous))
                .overlay(alignment: .bottom) { heroFade(b, in: s, height: h) }
            }
        case "title":
            PaywallLabel(text: resolve(b.text), size: ["s": 20, "m": 24, "l": 30, "xl": 36][b.size ?? "l"] ?? 30,
                         weight: .bold, design: design)
                .multilineTextAlignment(textAlign)
                .frame(maxWidth: greedy, alignment: frameAlign)
                .fixedSize(horizontal: false, vertical: true)
        case "text":
            PaywallLabel(text: resolve(b.text), size: ["s": 13, "m": 15, "l": 17, "xl": 19][b.size ?? "m"] ?? 15,
                         design: design, color: mutedColor)
                .multilineTextAlignment(textAlign)
                .frame(maxWidth: greedy, alignment: frameAlign)
                .fixedSize(horizontal: false, vertical: true)
        case "features":
            PaywallFeatures(items: b.items ?? [], variant: b.resolvedVariant, style: style(onSurface), resolve: resolve)
        case "packages":
            packagesBlock(b, onSurface: onSurface)
        case "cta":
            VStack(spacing: 8) {
                Button {
                    if let current { onPurchase(current) }
                } label: {
                    ZStack {
                        PaywallLabel(text: resolve(b.text).isEmpty ? "Continue" : resolve(b.text), size: 17, weight: .bold,
                                     design: design, color: accentTextColor)
                            .opacity(isPurchasing ? 0 : 1)
                        if isPurchasing { ProgressView().tint(accentTextColor) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(RoundedRectangle(cornerRadius: max(radius, 10), style: .continuous).fill(accentColor))
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || current == nil)
                if let sub = b.subtext, !sub.isEmpty {
                    Text(resolve(sub))
                        .font(.system(size: 12, design: design))
                        .foregroundColor(mutedColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        case "testimonial":
            PaywallTestimonial(b: b, style: style(onSurface), resolve: resolve)
        case "footer":
            HStack(spacing: 16) {
                if b.restore == true {
                    Button(action: onRestore) { Text("Restore purchases").underline() }
                }
                if let url = PaywallURL.safe(b.termsURL) {
                    Button { openURL(url) } label: { Text("Terms").underline() }
                }
                if let url = PaywallURL.safe(b.privacyURL) {
                    Button { openURL(url) } label: { Text("Privacy").underline() }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, design: design))
            .foregroundColor(mutedColor)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        case "header":
            headerBlock(b, onSurface: onSurface)
        case "art":
            let hero = b.resolvedVariant != "inline"
            let h = CGFloat(min(positive(b.height) ?? (hero ? 260 : 220), 480))
            PaywallArtView(name: b.art ?? "", palette: artPalette(s), animates: animates)
                .frame(maxWidth: .infinity)
                .frame(height: h)
                .clipShape(RoundedRectangle(cornerRadius: hero ? 0 : radius, style: .continuous))
                .overlay(alignment: .bottom) { heroFade(b, in: s, height: h) }
        case "video":
            let hero = b.resolvedVariant != "inline"
            let h = CGFloat(min(positive(b.height) ?? (hero ? 260 : 200), 480))
            PaywallVideo(url: b.url, poster: b.poster, height: h, radius: hero ? 0 : radius, surface: card, muted: mutedColor,
                         plays: scrolls, fills: hero)
                .overlay(alignment: .bottom) { heroFade(b, in: s, height: h) }
        case "stack":
            containerStack(b, in: s, onSurface: onSurface)
        case "custom":
            // The look is the card's own style panel: what it sets replaces
            // the card's padding, fill and border (as on the web, where both
            // sit on the same box).
            let look = b.look
            let lookFill = color(look?.background) != nil || !(look?.backgroundImage ?? "").isEmpty
            let lookBorder = color(look?.borderColor) != nil && (look?.borderWidth ?? 0) > 0
            let pad = CGFloat(positive(b.padding) ?? 16)
            containerStack(b, in: s, onSurface: lookFill ? false : b.background.map { $0.isEmpty || $0.caseInsensitiveCompare(theme.surface) == .orderedSame } ?? true)
                .padding(.horizontal, look?.paddingX != nil ? 0 : pad)
                .padding(.vertical, look?.paddingY != nil ? 0 : pad)
                .frame(maxWidth: greedy, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: positive(b.radius).map { CGFloat($0) } ?? radius, style: .continuous)
                    .fill(lookFill ? Color.clear : color(b.background) ?? surfaceColor))
                .overlay {
                    if !lookBorder, let border = color(b.border) {
                        RoundedRectangle(cornerRadius: positive(b.radius).map { CGFloat($0) } ?? radius, style: .continuous)
                            .strokeBorder(border, lineWidth: 1)
                    }
                }
        case "sheet":
            // Only reached for a sheet that is not on the screen itself;
            // top-level sheets are pinned by `screenBody`.
            sheetBlock(b, in: s)
        case "tabs":
            tabsBlock(b, in: s, onSurface: onSurface)
        case "switch":
            switchBlock(b, onSurface: onSurface)
        case "carousel":
            let variant = b.resolvedVariant
            // A peek page is a fill card, so what is on it sits on the other colour.
            let pagesOnSurface = variant == "peek" ? !onSurface : onSurface
            PaywallCarousel(pages: b.children ?? [], height: CGFloat(b.height.map { $0 > 0 ? min($0, 480) : 260 } ?? 260),
                            interval: b.interval ?? 0, plays: scrolls, variant: variant, style: style(onSurface)) {
                child($0, in: s, onSurface: pagesOnSurface)
            }
        case "countdown":
            PaywallCountdownView(label: resolve(b.text), until: b.until, minutes: b.minutes, variant: b.resolvedVariant,
                                 style: style(onSurface))
        case "timeline":
            PaywallTimeline(items: b.items ?? [], variant: b.resolvedVariant, style: style(onSurface), resolve: resolve)
        case "social_proof":
            PaywallSocialProof(b: b, style: style(onSurface), resolve: resolve)
        case "award":
            PaywallAward(b: b, style: style(onSurface), resolve: resolve)
        default:
            EmptyView()
        }
    }

    /// The colours art tokens name: A, AT, T, B (the screen's background), S, M.
    private func artPalette(_ s: PaywallDoc.Screen) -> [String: String] {
        ["A": theme.accent, "AT": theme.accentText, "T": theme.text, "B": s.background ?? theme.background,
         "S": theme.surface, "M": theme.muted]
    }

    /// hero_fade: the bottom 45% melts into the screen's background colour.
    @ViewBuilder
    private func heroFade(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen, height: CGFloat) -> some View {
        if b.resolvedVariant == "hero_fade" {
            let bg = Color(paywallHex: s.background ?? theme.background) ?? .white
            LinearGradient(colors: [bg.opacity(0), bg], startPoint: .top, endPoint: .bottom)
                .frame(height: height * 0.45)
                .allowsHitTesting(false)
        }
    }

    /// A child of a container, drawn exactly as it would be on the screen.
    /// (Type-erased: `block` is recursive.)
    private func child(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen, onSurface: Bool, inRow: Bool = false) -> AnyView {
        var scoped = self
        scoped.inRow = inRow
        return AnyView(scoped.block(b, in: s, onSurface: onSurface))
    }

    private func positive(_ v: Double?) -> Double? {
        guard let v, v > 0 else { return nil }
        return v
    }

    private func color(_ hex: String?) -> Color? {
        guard let hex, !hex.isEmpty else { return nil }
        return Color(paywallHex: hex)
    }

    // MARK: - Containers

    /// A stack's (or custom box's) children, along its axis, spaced by gap and
    /// placed by justify. Its text is only a tab label and is not drawn.
    @ViewBuilder
    private func containerStack(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen, onSurface: Bool) -> some View {
        let children = (b.children ?? []).filter(isVisible)
        let gap = CGFloat(positive(b.gap) ?? 12)
        let justify = b.justify ?? "start"
        let between = justify == "space_between"
        let cross = b.cross ?? ""
        if b.axis == "layers" {
            // Children on top of each other, placed by justify (down) and cross (across).
            let across: HorizontalAlignment = ["center": .center, "end": .trailing][cross] ?? .leading
            let down: VerticalAlignment = ["center": .center, "end": .bottom][justify] ?? .top
            let place = Alignment(horizontal: across, vertical: down)
            let sized = PaywallLookMath.size(b.look?.height, b.look?.heightPx)
            let tall = sized == .fill || { if case .fixed = sized { return true } else { return false } }()
            ZStack(alignment: place) {
                ForEach(children) { c in
                    if cross == "stretch" {
                        child(c, in: s, onSurface: onSurface).frame(maxWidth: .infinity)
                    } else {
                        // At its own width, so cross can place it.
                        child(c, in: s, onSurface: onSurface).fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: tall ? .infinity : nil, alignment: place)
        } else if b.axis == "horizontal" {
            let down: VerticalAlignment = ["start": .top, "end": .bottom][cross] ?? .center
            HStack(alignment: down, spacing: between ? 0 : gap) {
                if justify == "center" || justify == "end" { Spacer(minLength: 0) }
                ForEach(Array(children.enumerated()), id: \.element.id) { i, c in
                    if between && i > 0 { Spacer(minLength: gap) }
                    // As the web's flex row: a child whose look fills shares
                    // the room; the rest take their natural width.
                    let fills = c.look?.width == "fill"
                    child(c, in: s, onSurface: onSurface, inRow: !fills)
                        .frame(maxWidth: fills ? .infinity : nil)
                        .frame(maxHeight: cross == "stretch" ? .infinity : nil)
                }
                if justify == "center" { Spacer(minLength: 0) }
            }
            .fixedSize(horizontal: false, vertical: cross == "stretch")
            .frame(maxWidth: greedy, alignment: .leading)
        } else {
            let across: HorizontalAlignment = ["center": .center, "end": .trailing][cross] ?? .leading
            VStack(alignment: across, spacing: between ? 0 : gap) {
                if justify == "center" || justify == "end" { Spacer(minLength: 0) }
                ForEach(Array(children.enumerated()), id: \.element.id) { i, c in
                    if between && i > 0 { Spacer(minLength: gap) }
                    if cross == "stretch" {
                        child(c, in: s, onSurface: onSurface).frame(maxWidth: .infinity)
                    } else {
                        child(c, in: s, onSurface: onSurface)
                    }
                }
                if justify == "center" { Spacer(minLength: 0) }
            }
            .frame(maxWidth: greedy, alignment: Alignment(horizontal: across, vertical: .center))
        }
    }

    /// The bottom sheet: edge to edge, top corners rounded, a grabber on top.
    private func sheetBlock(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen) -> some View {
        let r = CGFloat(positive(b.radius) ?? 28)
        let onSurface = b.background.map { $0.isEmpty || $0.caseInsensitiveCompare(theme.surface) == .orderedSame } ?? true
        let shape = PaywallCornerShape(topLeading: r, topTrailing: r)
        return VStack(alignment: .leading, spacing: CGFloat(positive(b.gap) ?? 12)) {
            Capsule()
                .fill(mutedColor.opacity(0.35))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, -10)
            ForEach((b.children ?? []).filter(isVisible)) { child($0, in: s, onSurface: onSurface) }
        }
        .padding(CGFloat(positive(b.padding) ?? 22))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(color(b.background) ?? surfaceColor).ignoresSafeArea(edges: .bottom))
    }

    /// Custom-drawn tabs (the same on every platform, like the web), then
    /// the selected tab's stack. pills | underline | outline
    private func tabsBlock(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen, onSurface: Bool) -> some View {
        let children = b.children ?? []
        let selectedTab = min(tabs[b.id] ?? 0, max(children.count - 1, 0))
        let variant = b.resolvedVariant
        let fill = cardColor(onSurface)
        return VStack(alignment: .leading, spacing: 14) {
            switch variant {
            case "underline":
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { i, c in
                            let on = i == selectedTab
                            tabButton(b, i, on: on) {
                                VStack(spacing: 8) {
                                    Text(resolve(c.text))
                                        .font(.system(size: 15, weight: .semibold, design: design))
                                        .lineLimit(1)
                                        .foregroundColor(on ? textColor : mutedColor)
                                    Capsule().fill(on ? accentColor : Color.clear).frame(height: 2.5)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    Rectangle().fill(mutedColor.opacity(0.25)).frame(height: 1)
                }
            case "outline":
                HStack(spacing: 8) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { i, c in
                        let on = i == selectedTab
                        tabButton(b, i, on: on) {
                            Text(resolve(c.text))
                                .font(.system(size: 14, weight: .semibold, design: design))
                                .lineLimit(1)
                                .foregroundColor(on ? accentColor : mutedColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(on ? accentColor.opacity(0.1) : Color.clear))
                                .overlay(Capsule().strokeBorder(on ? accentColor : mutedColor.opacity(0.35), lineWidth: 1.5))
                                .contentShape(Capsule())
                        }
                    }
                }
            default: // pills
                HStack(spacing: 4) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { i, c in
                        let on = i == selectedTab
                        tabButton(b, i, on: on) {
                            Text(resolve(c.text))
                                .font(.system(size: 14, weight: .semibold, design: design))
                                .lineLimit(1)
                                .foregroundColor(on ? accentTextColor : mutedColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(on ? accentColor : Color.clear))
                                .contentShape(Capsule())
                        }
                    }
                }
                .padding(4)
                .background(Capsule().fill(fill))
            }
            if children.indices.contains(selectedTab) {
                child(children[selectedTab], in: s, onSurface: onSurface)
            }
        }
    }

    private func tabButton<Label: View>(_ b: PaywallDoc.Block, _ i: Int, on: Bool, @ViewBuilder label: () -> Label) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                tabs[b.id] = i
                // Tiers: opening a tab of plan cards selects its first plan
                // unless the selection is already on it.
                if let tab = b.children?[safe: i],
                   let pick = PaywallPlans.tierSelection(tab: tab, selected: currentID, available: packages.map(\.id)) {
                    selected = pick
                }
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Blocks

    /// A title row. plain: back chevron, the title centred on the screen;
    /// large: the title big and left-aligned under the chevron; pill: the
    /// centred title in a capsule; brand: chevron, an accent icon tile, title.
    @ViewBuilder
    private func headerBlock(_ b: PaywallDoc.Block, onSurface: Bool) -> some View {
        let title = resolve(b.text)
        let fill = cardColor(onSurface)
        switch b.resolvedVariant {
        case "large":
            VStack(alignment: .leading, spacing: 8) {
                if b.back == true { backButton(fill) }
                if !title.isEmpty {
                    PaywallLabel(text: title, size: 28, weight: .bold, design: design, tracking: -0.56)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case "brand":
            HStack(spacing: 10) {
                if b.back == true { backButton(fill) }
                Image(systemName: PaywallIcons.symbol(b.icon ?? "sparkles"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accentTextColor)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accentColor))
                PaywallLabel(text: title, size: 17, weight: .bold, design: design).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 32)
        default: // plain, pill
            let pill = b.resolvedVariant == "pill"
            HStack(spacing: 8) {
                if b.back == true { backButton(fill) } else { Color.clear.frame(width: 32, height: 32) }
                Group {
                    if pill {
                        if !title.isEmpty {
                            PaywallLabel(text: title, size: 14, weight: .semibold, design: design)
                                .padding(.vertical, 6).padding(.horizontal, 14)
                                .background(Capsule().fill(fill))
                        }
                    } else {
                        PaywallLabel(text: title, size: 16, weight: .semibold, design: design)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                Color.clear.frame(width: 32, height: 32)
            }
        }
    }

    private func backButton(_ fill: Color) -> some View {
        Button(action: back) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    /// Flips between the switch's two packages; on when its "on" package is selected.
    private func switchBlock(_ b: PaywallDoc.Block, onSurface: Bool) -> some View {
        let isOn = Binding<Bool>(
            get: { PaywallSwitch.isOn(selected: currentID, packageOn: b.packageOn) },
            set: { on in
                if let id = PaywallSwitch.package(on: on, packageOn: b.packageOn, packageOff: b.packageOff) {
                    withAnimation(.easeInOut(duration: 0.2)) { selected = id }
                }
            }
        )
        let labels = VStack(alignment: .leading, spacing: 2) {
            Text(resolve(b.text)).font(.system(size: 15, weight: .semibold, design: design))
            if let sub = b.subtext, !sub.isEmpty {
                Text(resolve(sub)).font(.system(size: 13, design: design)).foregroundColor(mutedColor)
            }
        }
        let card = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch b.resolvedVariant {
        case "checkbox":
            return AnyView(
                Button {
                    isOn.wrappedValue.toggle()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            if isOn.wrappedValue {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accentColor)
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                            } else {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(mutedColor.opacity(0.45), lineWidth: 2)
                            }
                        }
                        .frame(width: 24, height: 24)
                        labels
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(card.fill(cardColor(onSurface)))
                    .contentShape(card)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
            )
        case "plain":
            return AnyView(
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        labels
                        Spacer(minLength: 0)
                        switchControl(isOn, label: resolve(b.text))
                    }
                    .padding(.vertical, 4)
                    Rectangle().fill(mutedColor.opacity(0.2)).frame(height: 1).padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        default: // card
            return AnyView(
                HStack(spacing: 12) {
                    labels
                    Spacer(minLength: 0)
                    switchControl(isOn, label: resolve(b.text))
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card.fill(cardColor(onSurface)))
            )
        }
    }

    @ViewBuilder
    private func switchControl(_ isOn: Binding<Bool>, label: String) -> some View {
        if scrolls {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .paywallSwitchStyle()
                .tint(accentColor)
                .accessibilityLabel(label)
        } else {
            // Static renders: ImageRenderer cannot draw the platform switch.
            Capsule()
                .fill(isOn.wrappedValue ? accentColor : mutedColor.opacity(0.3))
                .frame(width: 51, height: 31)
                .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                    Circle().fill(Color.white).padding(2).shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
        }
    }

    @ViewBuilder
    private func buttonBlock(_ b: PaywallDoc.Block, in s: PaywallDoc.Screen, onSurface: Bool) -> some View {
        let style = b.style ?? "primary"
        let label = resolve(b.text).isEmpty ? "Continue" : resolve(b.text)
        let press = {
            if let answer = PaywallAnswer(block: b, screen: s) { onAnswer?(answer) }
            switch b.action {
            case "next":
                let all = doc.flow
                if let i = all.firstIndex(where: { $0.id == s.id }), i + 1 < all.count { go(all[i + 1].id) }
            case "back": back()
            case "screen": go(b.target)
            case "close": onClose?()
            case "restore": onRestore()
            case "url":
                if let url = PaywallURL.safe(b.url) { openURL(url) }
            default: break
            }
        }
        if b.resolvedVariant == "option" {
            // A full-width choice row; the style does not apply.
            Button(action: press) {
                HStack(spacing: 14) {
                    if let emoji = b.emoji, !emoji.isEmpty {
                        Text(emoji).font(.system(size: 24))
                    } else if let icon = b.icon, !icon.isEmpty {
                        Image(systemName: PaywallIcons.symbol(icon))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(accentColor)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accentColor.opacity(0.12)))
                    }
                    PaywallLabel(text: label, size: 16, weight: .semibold, design: design, color: textColor)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(mutedColor)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(cardColor(onSurface)))
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .buttonStyle(PaywallPressStyle())
        } else if style == "link" {
            Button(action: press) { Text(label).underline() }
                .buttonStyle(.plain)
                .font(.system(size: 14, design: design))
                .foregroundColor(mutedColor)
                .padding(6)
                .frame(maxWidth: .infinity)
        } else {
            // The variant is the shape; the style the colours.
            let shape = RoundedRectangle(cornerRadius: ["pill": 999, "square": 4][b.resolvedVariant] ?? max(radius, 10), style: .continuous)
            let fill: Color = style == "primary" ? accentColor : style == "outline" ? .clear : cardColor(onSurface)
            Button(action: press) {
                PaywallLabel(text: label, size: 16, weight: .bold, design: design,
                             color: style == "primary" ? accentTextColor : style == "outline" ? accentColor : textColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    // Room either side when a look sizes it to fit.
                    .padding(.horizontal, 20)
                    .background(shape.fill(fill))
                    .overlay(shape.strokeBorder(style == "outline" ? accentColor : .clear, lineWidth: 1.5))
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func packagesBlock(_ b: PaywallDoc.Block, onSurface: Bool) -> some View {
        if packages.isEmpty {
            Text("No plans are available right now.").font(.system(size: 13)).foregroundColor(mutedColor)
        } else if b.layout == "cards" {
            // Up to three a row, wrapping (as the web's grid), every card the same width.
            VStack(spacing: 10) {
                ForEach(Array(stride(from: 0, to: packages.count, by: 3)), id: \.self) { start in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(start..<start + 3, id: \.self) { i in
                            if i < packages.count {
                                packageOption(packages[i], badge: b.badges?[packages[i].id], card: true, onSurface: onSurface)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        } else {
            VStack(spacing: 10) {
                ForEach(packages) { p in packageOption(p, badge: b.badges?[p.id], card: false, onSurface: onSurface) }
            }
            .padding(.vertical, 6)
        }
    }

    private func packageOption(_ p: PaywallPackageView, badge: String?, card: Bool, onSurface: Bool) -> some View {
        let on = p.id == currentID
        let price = p.period.isEmpty ? p.price : "\(p.price) / \(p.period)"
        return Button {
            selected = p.id
        } label: {
            Group {
                if card {
                    VStack(spacing: 4) {
                        Text(p.productName).font(.system(size: 15, weight: .semibold, design: design))
                        Text(price).font(.system(size: 14, design: design)).foregroundColor(mutedColor)
                    }
                    // Narrow cards wrap rather than truncate, as on the web.
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18).padding(.bottom, 14).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Text(p.productName).font(.system(size: 15, weight: .semibold, design: design))
                        Spacer()
                        Text(price).font(.system(size: 14, design: design)).foregroundColor(mutedColor)
                    }
                    .padding(.vertical, 14).padding(.horizontal, 16)
                }
            }
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(cardColor(onSurface)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(on ? accentColor : .clear, lineWidth: 2))
            .overlay(alignment: card ? .top : .topTrailing) {
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold, design: design))
                        .foregroundColor(accentTextColor)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(accentColor))
                        .offset(x: card ? 0 : -12, y: -9)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The closed icon set, as SF Symbols.
enum PaywallIcons {
    static let symbols: [String: String] = [
        "check": "checkmark", "star": "star.fill", "bolt": "bolt.fill", "lock": "lock.fill",
        "cloud": "cloud.fill", "heart": "heart.fill", "sparkles": "sparkles", "infinity": "infinity",
        "shield": "checkmark.shield.fill", "crown": "crown.fill", "gift": "gift.fill", "clock": "clock.fill",
        "chart": "chart.bar.fill", "bell": "bell.fill", "download": "arrow.down.circle.fill", "people": "person.2.fill",
        "mail": "envelope.fill", "target": "target", "trophy": "trophy.fill", "rocket": "paperplane.fill",
    ]

    static func symbol(_ name: String) -> String { symbols[name] ?? "checkmark" }
}

extension Color {
    /// "#RGB", "#RRGGBB" or "#RRGGBBAA"; nil for anything else.
    init?(paywallHex hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        var s = String(hex.dropFirst())
        guard [3, 6, 8].contains(s.count), s.allSatisfy(\.isHexDigit) else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        if s.count == 6 { s += "FF" }
        guard let v = UInt64(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 24) & 0xFF) / 255, green: Double((v >> 16) & 0xFF) / 255,
                  blue: Double((v >> 8) & 0xFF) / 255, opacity: Double(v & 0xFF) / 255)
    }
}

// MARK: - Block views with their own state

/// A muted, looping, autoplaying clip. When it cannot play (a bad URL, or a
/// static render) the poster, or a play symbol on the surface colour.
struct PaywallVideo: View {
    let url: String?
    let poster: String?
    let height: CGFloat
    let radius: CGFloat
    let surface: Color
    let muted: Color
    /// False in static renders: ImageRenderer cannot draw a player.
    let plays: Bool
    /// Hero: fill the box edge to edge (no letterboxing, no controls).
    var fills: Bool = false

    @State private var player: AVPlayer?

    private var videoURL: URL? {
        PaywallURL.safe(url)
    }

    var body: some View {
        Group {
            if plays, fills, let videoURL {
                PaywallFillVideo(url: videoURL)
            } else if plays, let videoURL {
                VideoPlayer(player: player)
                    .disabled(true)
                    .onAppear {
                        if player == nil {
                            let p = AVPlayer(url: videoURL)
                            p.isMuted = true
                            p.actionAtItemEnd = .none
                            player = p
                        }
                        player?.play()
                    }
                    .onDisappear { player?.pause() }
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
                        guard let player, let item = note.object as? AVPlayerItem, item === player.currentItem else { return }
                        player.seek(to: .zero)
                        player.play()
                    }
            } else {
                still
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    @ViewBuilder
    private var still: some View {
        if let u = PaywallURL.safe(poster) {
            AsyncImage(url: u) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            surface
            Image(systemName: "play.circle").font(.system(size: 44, weight: .light)).foregroundColor(muted)
        }
    }
}

/// Pages that swipe (and advance on their own every `interval` seconds).
/// dots: dots underneath; bars: story-style progress bars above; peek: 84%
/// wide cards so the next page shows, dots underneath. A static render shows
/// the first page.
struct PaywallCarousel: View {
    let pages: [PaywallDoc.Block]
    let height: CGFloat
    let interval: Int
    let plays: Bool
    let variant: String
    let style: PaywallStyle
    let page: (PaywallDoc.Block) -> AnyView

    @State private var index = 0

    var body: some View {
        VStack(spacing: 10) {
            if variant == "bars" && pages.count > 1 { bars }
            Group {
                if variant == "peek" { peek } else { pager }
            }
            .frame(height: height)
            if variant != "bars" && pages.count > 1 { dots }
        }
        .task(id: plays ? interval : 0) {
            guard plays, interval > 0, pages.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.35)) { index = (index + 1) % pages.count }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { i in
                Button {
                    withAnimation { index = i }
                } label: {
                    Circle()
                        .fill(i == index ? style.accent : style.muted.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(i + 1)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bars: some View {
        HStack(spacing: 4) {
            ForEach(pages.indices, id: \.self) { i in
                Button {
                    withAnimation { index = i }
                } label: {
                    Capsule()
                        .fill(i == index ? style.accent : style.muted.opacity(0.3))
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(i + 1)")
            }
        }
        .padding(.vertical, -4)
    }

    @ViewBuilder
    private var pager: some View {
        #if os(macOS)
        // No paging TabView on macOS: the current page, moved by the dots.
        current
        #else
        if plays {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, p in
                    pageView(p).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        } else {
            current
        }
        #endif
    }

    /// Cards 84% of the width in a row, slid to the current one.
    private var peek: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.84
            let gap: CGFloat = 12
            HStack(spacing: gap) {
                ForEach(pages) { p in
                    page(p)
                        .padding(16)
                        .frame(width: width, height: geo.size.height)
                        .background(style.card().fill(style.fill))
                        .clipShape(style.card())
                }
            }
            .offset(x: -CGFloat(index) * (width + gap))
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .paywallSwipe(enabled: plays) { forward in
                withAnimation(.easeInOut(duration: 0.3)) {
                    index = forward ? min(index + 1, pages.count - 1) : max(index - 1, 0)
                }
            }
        }
        .clipped()
    }

    @ViewBuilder
    private var current: some View {
        if pages.indices.contains(index) { pageView(pages[index]) }
    }

    private func pageView(_ p: PaywallDoc.Block) -> some View {
        page(p).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

extension View {
    /// A horizontal swipe (not on tvOS, which has no drag gestures): true
    /// for forward (right to left).
    @ViewBuilder
    func paywallSwipe(enabled: Bool, _ action: @escaping (Bool) -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        if enabled {
            gesture(DragGesture(minimumDistance: 20).onEnded { g in
                if abs(g.translation.width) > 40 { action(g.translation.width < 0) }
            })
        } else {
            self
        }
        #endif
    }

    /// A switch where the platform has one (tvOS has only its button toggle).
    @ViewBuilder
    func paywallSwitchStyle() -> some View {
        #if os(tvOS)
        self
        #else
        self.toggleStyle(.switch)
        #endif
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
