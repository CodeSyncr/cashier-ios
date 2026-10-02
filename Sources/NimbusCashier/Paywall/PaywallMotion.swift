import SwiftUI

// MARK: - Colour

extension Color {
    /// A "#RRGGBB" colour with its hue turned by `degrees` (HSB), for the
    /// accent-to-shifted-accent gradients. nil for anything unreadable.
    init?(paywallHex hex: String, hueShift degrees: Double) {
        guard hex.hasPrefix("#") else { return nil }
        var s = String(hex.dropFirst())
        guard [3, 6, 8].contains(s.count), s.allSatisfy(\.isHexDigit) else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        if s.count == 6 { s += "FF" }
        guard let v = UInt64(s, radix: 16) else { return nil }
        let r = Double((v >> 24) & 0xFF) / 255, g = Double((v >> 16) & 0xFF) / 255, b = Double((v >> 8) & 0xFF) / 255
        let a = Double(v & 0xFF) / 255
        let hsb = PaywallHue.hsb(r: r, g: g, b: b)
        var h = (hsb.h + degrees / 360).truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        self.init(hue: h, saturation: hsb.s, brightness: hsb.b, opacity: a)
    }
}

enum PaywallHue {
    /// RGB (0…1) to hue (0…1), saturation, brightness.
    static func hsb(r: Double, g: Double, b: Double) -> (h: Double, s: Double, b: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
}

// MARK: - Screen effects

/// An animated background drawn from the accent, behind a screen's blocks.
/// Never takes part in layout or touches; `animates` false draws it at rest.
struct PaywallEffect: View {
    let kind: String
    let accent: Color
    let text: Color
    let animates: Bool

    @State private var phase = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                switch kind {
                case "glow": glow(w)
                case "aurora": aurora(w, h)
                case "orbs": orbs(w, h)
                case "grid": grid(w, h)
                case "rays": rays(w, h)
                default: EmptyView()
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if animates { phase = true } }
    }

    private func repeating(_ duration: Double, delay: Double = 0, autoreverses: Bool = true, linear: Bool = false) -> Animation? {
        guard animates else { return nil }
        let base: Animation = linear ? .linear(duration: duration) : .easeInOut(duration: duration)
        return base.repeatForever(autoreverses: autoreverses).delay(delay)
    }

    /// A radial accent glow from the top centre that breathes.
    private func glow(_ w: CGFloat) -> some View {
        RadialGradient(colors: [accent.opacity(0.38), accent.opacity(0)], center: UnitPoint(x: 0.5, y: 0),
                       startRadius: 0, endRadius: w * 0.85)
            .scaleEffect(phase ? 1.08 : 1, anchor: .top)
            .opacity(phase ? 0.75 : 1)
            .animation(repeating(6), value: phase)
    }

    /// Three big blurred accent blobs, two hue-shifted, drifting.
    private func aurora(_ w: CGFloat, _ h: CGFloat) -> some View {
        let d = w * 0.75
        let blobs: [(x: CGFloat, y: CGFloat, hue: Double, dx: CGFloat, dy: CGFloat, t: Double)] = [
            (0.15, 0.08, 0, 0.10, 0.06, 14), (0.85, 0.22, 40, -0.12, 0.08, 17), (0.35, 0.48, -35, 0.08, -0.10, 12),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(blobs.indices, id: \.self) { i in
                let b = blobs[i]
                Circle()
                    .fill(accent.opacity(0.4))
                    .frame(width: d, height: d)
                    .hueRotation(.degrees(b.hue))
                    .blur(radius: 60)
                    .position(x: w * b.x, y: h * b.y)
                    .offset(x: phase ? w * b.dx : 0, y: phase ? w * b.dy : 0)
                    .animation(repeating(b.t), value: phase)
            }
        }
    }

    static let orbs: [(x: CGFloat, y: CGFloat, d: CGFloat, o: Double, t: Double, delay: Double)] = [
        (0.12, 0.14, 18, 0.35, 4, 0), (0.82, 0.10, 26, 0.25, 5.5, 0.6), (0.68, 0.34, 10, 0.5, 4.5, 1.2),
        (0.22, 0.46, 14, 0.3, 6, 0.3), (0.90, 0.58, 20, 0.22, 5, 0.9), (0.08, 0.72, 8, 0.45, 4.2, 1.5),
        (0.60, 0.82, 16, 0.28, 6.5, 0.4),
    ]

    /// Small accent circles floating up and back.
    private func orbs(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.orbs.indices, id: \.self) { i in
                let o = Self.orbs[i]
                Circle()
                    .fill(accent.opacity(o.o))
                    .frame(width: o.d, height: o.d)
                    .position(x: w * o.x, y: h * o.y)
                    .offset(y: phase ? -10 : 0)
                    .animation(repeating(o.t, delay: o.delay), value: phase)
            }
        }
    }

    /// A 24pt grid in faint text colour, fading out by 60% down.
    private func grid(_ w: CGFloat, _ h: CGFloat) -> some View {
        Path { p in
            var x: CGFloat = 0
            while x <= w { p.move(to: CGPoint(x: x + 0.5, y: 0)); p.addLine(to: CGPoint(x: x + 0.5, y: h)); x += 24 }
            var y: CGFloat = 0
            while y <= h { p.move(to: CGPoint(x: 0, y: y + 0.5)); p.addLine(to: CGPoint(x: w, y: y + 0.5)); y += 24 }
        }
        .stroke(text.opacity(0.07), lineWidth: 1)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.6)],
                             startPoint: .top, endPoint: .bottom))
    }

    /// Sixteen accent rays from just above the top centre, slowly turning,
    /// fading out with distance.
    private func rays(_ w: CGFloat, _ h: CGFloat) -> some View {
        let side = max(w, h) * 2.6
        let wedge = 1.0 / 32
        var stops: [Gradient.Stop] = []
        for i in 0..<16 {
            let start = Double(i) * 2 * wedge
            stops += [.init(color: accent.opacity(0.12), location: start), .init(color: accent.opacity(0.12), location: start + wedge),
                      .init(color: .clear, location: start + wedge), .init(color: .clear, location: start + 2 * wedge)]
        }
        return AngularGradient(gradient: Gradient(stops: stops), center: .center)
            .frame(width: side, height: side)
            .rotationEffect(.degrees(phase ? 360 : 0))
            .animation(repeating(60, autoreverses: false, linear: true), value: phase)
            .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 0, endRadius: w * 1.1))
            .position(x: w * 0.5, y: -h * 0.1)
    }
}

// MARK: - Entrance

/// Brings a top-level block in: from transparent (and lower, or smaller) to
/// rest, after `delay`.
struct PaywallEntrance: ViewModifier {
    let kind: String?
    let shown: Bool
    let delay: Double

    func body(content: Content) -> some View {
        switch kind {
        case "rise", "fade", "zoom":
            content
                .opacity(shown ? 1 : 0)
                .offset(y: kind == "rise" && !shown ? 18 : 0)
                .scaleEffect(kind == "zoom" && !shown ? 0.92 : 1)
                .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay), value: shown)
        default:
            content
        }
    }
}

// MARK: - Icon block

/// The icon block: tile | glow | rings | gradient | plain. An emoji, when
/// set, takes the glyph's place.
struct PaywallIconView: View {
    let symbol: String
    let emoji: String?
    let size: CGFloat
    let variant: String
    let style: PaywallStyle
    /// The accent with its hue turned 30°, for the gradients.
    let accent2: Color
    let animates: Bool

    @State private var phase = false
    /// A look's colour recolours the glyph.
    @Environment(\.paywallType) private var type

    private var hasEmoji: Bool { !(emoji ?? "").isEmpty }

    var body: some View {
        content
            .frame(width: size, height: size)
            .onAppear { if animates { phase = true } }
    }

    @ViewBuilder
    private func glyph(_ color: Color, scale: CGFloat = 0.5, emojiScale: CGFloat = 0.55) -> some View {
        if hasEmoji {
            Text(emoji ?? "").font(.system(size: size * emojiScale))
        } else {
            Image(systemName: symbol).font(.system(size: size * scale, weight: .semibold))
                .foregroundColor(type.color.flatMap { Color(paywallHex: $0) } ?? color)
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [style.accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func forever(_ duration: Double, delay: Double = 0, autoreverses: Bool = true, easeOut: Bool = false) -> Animation? {
        guard animates else { return nil }
        let base: Animation = easeOut ? .easeOut(duration: duration) : .easeInOut(duration: duration)
        return base.repeatForever(autoreverses: autoreverses).delay(delay)
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case "glow":
            glyph(style.accentText)
                .frame(width: size, height: size)
                .background(Circle().fill(gradient))
                .shadow(color: style.accent.opacity(0.55), radius: 24, y: 10)
                .scaleEffect(phase ? 1.06 : 1)
                .animation(forever(2.4), value: phase)
        case "rings":
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    // At rest (static renders, reduced motion) one ring shows
                    // half-way out, so the variant still reads.
                    let restScale: CGFloat = i == 0 ? 1.45 : 1
                    let restOpacity: Double = i == 0 ? 0.3 : 0
                    Circle()
                        .stroke(style.accent.opacity(0.5), lineWidth: 2)
                        .scaleEffect(animates ? (phase ? 1.9 : 1) : restScale)
                        .opacity(animates ? (phase ? 0 : 0.6) : restOpacity)
                        .animation(forever(2.4, delay: Double(i) * 1.2, autoreverses: false, easeOut: true), value: phase)
                }
                glyph(style.accent)
                    .frame(width: size, height: size)
                    .background(Circle().fill(style.fill))
            }
        case "gradient":
            glyph(style.accentText)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(gradient))
                .shadow(color: style.accent.opacity(0.35), radius: 18, y: 8)
                .offset(y: phase ? -6 : 0)
                .rotationEffect(.degrees(animates ? (phase ? 3 : -3) : 0))
                .animation(forever(3.2), value: phase)
        case "plain":
            glyph(style.accent, scale: 0.6, emojiScale: 0.8)
        default: // tile
            glyph(style.accent)
                .frame(width: size, height: size)
                .background(Circle().fill(style.fill))
        }
    }
}

// MARK: - Buttons

/// Shrinks a little while pressed (the option button).
struct PaywallPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
