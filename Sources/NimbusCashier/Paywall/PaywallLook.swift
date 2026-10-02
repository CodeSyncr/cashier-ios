import SwiftUI

// MARK: - Type

/// The type part of a look, as it flows down to a block's text: a
/// container's type is the default its children's text inherits.
struct PaywallType: Equatable, Sendable {
    var font: String?
    var weight: String?
    var size: Double?
    var color: String?
    var italic: Bool?

    /// This type with `look`'s type fields laid over it.
    func merged(_ look: PaywallDoc.Look?) -> PaywallType {
        guard let look else { return self }
        var t = self
        if let f = look.font, PaywallLookMath.design(f) != nil { t.font = f }
        if let w = look.weight, PaywallLookMath.weight(w) != nil { t.weight = w }
        if let s = look.fontSize, s > 0 { t.size = s }
        if let c = look.color, Color(paywallHex: c) != nil { t.color = c }
        if look.italic == true { t.italic = true }
        return t
    }
}

private struct PaywallTypeKey: EnvironmentKey {
    static let defaultValue = PaywallType()
}

extension EnvironmentValues {
    var paywallType: PaywallType {
        get { self[PaywallTypeKey.self] }
        set { self[PaywallTypeKey.self] = newValue }
    }
}

/// The look's arithmetic, kept pure so it can be tested.
enum PaywallLookMath {
    static func weight(_ name: String) -> Font.Weight? {
        ["regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy][name]
    }

    static func design(_ name: String) -> Font.Design? {
        ["system": .default, "rounded": .rounded, "serif": .serif, "mono": .monospaced][name]
    }

    /// A text's font: the block's design defaults, with the look's type over them.
    static func font(size: CGFloat, weight: Font.Weight, design: Font.Design, type: PaywallType)
        -> (size: CGFloat, weight: Font.Weight, design: Font.Design, italic: Bool) {
        (type.size.map { CGFloat(min(max($0, 8), 96)) } ?? size,
         type.weight.flatMap(weight(_:)) ?? weight,
         type.font.flatMap(design(_:)) ?? design,
         type.italic == true)
    }

    /// The four corner radii: `corners` (top-left, top-right, bottom-right,
    /// bottom-left) when it has four, else `radius` all round.
    static func corners(_ look: PaywallDoc.Look) -> [CGFloat] {
        if let c = look.corners, c.count == 4 { return c.map { CGFloat(min(max($0, 0), 200)) } }
        return Array(repeating: CGFloat(min(max(look.radius ?? 0, 0), 200)), count: 4)
    }

    /// What a width or height mode does: nil (unchanged), fit, fill, or a fixed size.
    enum Size: Equatable { case fit, fill, fixed(CGFloat) }

    static func size(_ mode: String?, _ px: Double?) -> Size? {
        switch mode {
        case "fit": return .fit
        case "fill": return .fill
        case "fixed":
            guard let px, px > 0 else { return nil }
            return .fixed(CGFloat(min(px, 1000)))
        default: return nil
        }
    }
}

/// A run of text drawn with the block's defaults and the inherited look type.
struct PaywallLabel: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .regular
    let design: Font.Design
    /// nil: the colour it inherits.
    var color: Color? = nil
    var tracking: CGFloat = 0

    @Environment(\.paywallType) private var type

    var body: some View {
        let f = PaywallLookMath.font(size: size, weight: weight, design: design, type: type)
        let font = Font.system(size: f.size, weight: f.weight, design: f.design)
        let text = Text(text).font(f.italic ? font.italic() : font).tracking(tracking)
        if let c = type.color.flatMap({ Color(paywallHex: $0) }) ?? color {
            text.foregroundColor(c)
        } else {
            text
        }
    }
}

// MARK: - Box

/// A look's box, applied around a block after its own rendering: padding →
/// size → fill → corners → border → shadow → opacity → (placement) → margin.
struct PaywallBox: ViewModifier {
    let look: PaywallDoc.Look?
    /// Where a block that does not fill sits across its container.
    let align: Alignment
    /// False in a row, where the row places its children (a placement frame
    /// would make a fixed or fit block greedy there).
    var places = true

    func body(content: Content) -> some View {
        if let look {
            styled(content, look)
        } else {
            content
        }
    }

    private func styled(_ content: Content, _ look: PaywallDoc.Look) -> some View {
        let c = PaywallLookMath.corners(look)
        let shape = PaywallCornerShape(topLeading: c[0], topTrailing: c[1], bottomTrailing: c[2], bottomLeading: c[3])
        let width = PaywallLookMath.size(look.width, look.widthPx)
        let height = PaywallLookMath.size(look.height, look.heightPx)
        let padded = content
            .padding(.horizontal, CGFloat(max(look.paddingX ?? 0, 0)))
            .padding(.vertical, CGFloat(max(look.paddingY ?? 0, 0)))
        let hasFill = color(look.background) != nil || url(look.backgroundImage) != nil
        let shadow = color(look.shadowColor)
        let opacity = look.opacity.map { $0 >= 1 && $0 <= 100 ? $0 / 100 : 1 } ?? 1
        return sized(padded, width: width, height: height)
            .background(fill(look, shape, shadow: hasFill ? shadow : nil))
            .overlay {
                if let border = color(look.borderColor), let w = look.borderWidth, w > 0 {
                    shape.strokeBorder(border, lineWidth: CGFloat(w))
                }
            }
            .modifier(ContentShadow(color: hasFill ? nil : shadow, look: look))
            .opacity(opacity)
            .modifier(Placement(width: places ? width : nil, align: align))
            .padding(.horizontal, CGFloat(look.marginX ?? 0))
            // Negative margins pull the neighbours closer (SwiftUI allows
            // negative padding: the block keeps drawing, its slot shrinks).
            .padding(.vertical, CGFloat(look.marginY ?? 0))
    }

    private func sized<V: View>(_ v: V, width: PaywallLookMath.Size?, height: PaywallLookMath.Size?) -> AnyView {
        var out = AnyView(v)
        switch width {
        case .fit: out = AnyView(out.fixedSize(horizontal: true, vertical: false))
        case .fill: out = AnyView(out.frame(maxWidth: .infinity))
        case .fixed(let w): out = AnyView(out.frame(width: w))
        case nil: break
        }
        switch height {
        case .fit: out = AnyView(out.fixedSize(horizontal: false, vertical: true))
        case .fill: out = AnyView(out.frame(maxHeight: .infinity))
        case .fixed(let h): out = AnyView(out.frame(height: h))
        case nil: break
        }
        return out
    }

    /// The colour, gradient and image, clipped to the shape (the content is
    /// not clipped), with the shadow cast by that shape.
    @ViewBuilder
    private func fill(_ look: PaywallDoc.Look, _ shape: PaywallCornerShape, shadow: Color?) -> some View {
        let top = color(look.background)
        ZStack {
            if let top {
                if let end = color(look.backgroundEnd) {
                    LinearGradient(colors: [top, end], startPoint: .top, endPoint: .bottom)
                } else {
                    top
                }
            }
            if let image = url(look.backgroundImage) {
                AsyncImage(url: image) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
            }
        }
        .clipShape(shape)
        .shadow(color: shadow ?? .clear, radius: CGFloat(look.shadowBlur ?? 0) / 2,
                x: CGFloat(look.shadowX ?? 0), y: CGFloat(look.shadowY ?? 0))
    }

    /// With no fill of its own the block's drawn content casts the shadow.
    private struct ContentShadow: ViewModifier {
        let color: Color?
        let look: PaywallDoc.Look

        func body(content: Content) -> some View {
            if let color {
                content
                    .compositingGroup()
                    .shadow(color: color, radius: CGFloat(look.shadowBlur ?? 0) / 2,
                            x: CGFloat(look.shadowX ?? 0), y: CGFloat(look.shadowY ?? 0))
            } else {
                content
            }
        }
    }

    /// A fit or fixed width block placed per its align in the full width.
    private struct Placement: ViewModifier {
        let width: PaywallLookMath.Size?
        let align: Alignment

        func body(content: Content) -> some View {
            switch width {
            case .fit, .fixed: content.frame(maxWidth: .infinity, alignment: align)
            default: content
            }
        }
    }

    private func color(_ hex: String?) -> Color? {
        guard let hex, !hex.isEmpty else { return nil }
        return Color(paywallHex: hex)
    }

    private func url(_ raw: String?) -> URL? {
        PaywallURL.safe(raw)
    }
}
