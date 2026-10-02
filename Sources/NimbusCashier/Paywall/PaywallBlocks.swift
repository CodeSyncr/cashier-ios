import SwiftUI

/// The theme as one block sees it: colours, radius, font design, and `fill`
/// (the surface, or the page colour when the block sits on a
/// surface-coloured sheet or card).
struct PaywallStyle {
    let text: Color
    let muted: Color
    let surface: Color
    let background: Color
    let accent: Color
    let accentText: Color
    let fill: Color
    let radius: CGFloat
    let design: Font.Design

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    func card(_ r: CGFloat? = nil) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: r ?? radius, style: .continuous)
    }
}

/// `count` accent stars.
struct PaywallStars: View {
    let count: Int
    let size: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: size * 0.15) {
            ForEach(0..<min(max(count, 0), 5), id: \.self) { _ in
                Image(systemName: "star.fill").font(.system(size: size)).foregroundColor(color)
            }
        }
    }
}

/// Overlapping avatar circles: up to five images, or four accent-tinted
/// placeholders.
struct PaywallAvatars: View {
    let images: [String]
    let size: CGFloat
    /// The colour behind the avatars, drawn as a ring between them.
    let ring: Color
    let style: PaywallStyle

    var body: some View {
        let urls = images.prefix(5).compactMap(PaywallURL.safe)
        HStack(spacing: -size * 0.28) {
            if urls.isEmpty {
                ForEach(0..<4, id: \.self) { i in
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundColor(style.accentText)
                        .frame(width: size, height: size)
                        .background(Circle().fill(style.accent.opacity([1, 0.8, 0.6, 0.4][i])))
                        .overlay(Circle().stroke(ring, lineWidth: 2))
                }
            } else {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        style.surface
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ring, lineWidth: 2))
                }
            }
        }
    }
}

// MARK: - features: list | checks | grid | cards

struct PaywallFeatures: View {
    let items: [PaywallDoc.Item]
    let variant: String
    let style: PaywallStyle
    let resolve: (String?) -> String

    var body: some View {
        switch variant {
        case "checks":
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(style.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(resolve(item.title)).font(style.font(15))
                            detail(item)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case "grid":
            VStack(spacing: 10) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        tile(items[i])
                        if i + 1 < items.count { tile(items[i + 1]) } else { Color.clear.frame(maxWidth: .infinity) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        case "cards":
            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    row(item, tile: style.accent.opacity(0.12))
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(style.card().fill(style.fill))
                }
            }
        default: // list
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in row(item, tile: style.fill) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func row(_ item: PaywallDoc.Item, tile: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: PaywallIcons.symbol(item.icon))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(style.accent)
                .frame(width: 34, height: 34)
                .background(style.card(min(style.radius, 12)).fill(tile))
            VStack(alignment: .leading, spacing: 2) {
                Text(resolve(item.title)).font(style.font(15, .semibold))
                detail(item)
            }
            .padding(.top, 2)
        }
    }

    private func tile(_ item: PaywallDoc.Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: PaywallIcons.symbol(item.icon))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(style.accent)
            Text(resolve(item.title)).font(style.font(14, .semibold))
            if let t = item.text, !t.isEmpty {
                Text(resolve(t)).font(style.font(12)).foregroundColor(style.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.card().fill(style.fill))
    }

    @ViewBuilder
    private func detail(_ item: PaywallDoc.Item) -> some View {
        if let t = item.text, !t.isEmpty {
            Text(resolve(t)).font(style.font(13)).foregroundColor(style.muted)
        }
    }
}

// MARK: - testimonial: card | quote | bubble

struct PaywallTestimonial: View {
    let b: PaywallDoc.Block
    let style: PaywallStyle
    let resolve: (String?) -> String

    private var author: String { resolve(b.author) }
    private var rating: Int { b.rating ?? 0 }

    var body: some View {
        switch b.resolvedVariant {
        case "quote":
            VStack(spacing: 4) {
                if rating > 0 { PaywallStars(count: rating, size: 14, color: style.accent) }
                Text("\u{201C}")
                    .font(.system(size: 48, weight: .bold, design: .serif))
                    .foregroundColor(style.accent)
                    .frame(height: 34, alignment: .top)
                    .padding(.top, 4)
                Text(resolve(b.text))
                    .font(style.font(18))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !author.isEmpty {
                    Text("— " + author).font(style.font(13)).foregroundColor(style.muted).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        case "bubble":
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    if rating > 0 { PaywallStars(count: rating, size: 13, color: style.accent) }
                    Text(resolve(b.text)).font(style.font(15)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PaywallCornerShape(topLeading: style.radius, topTrailing: style.radius,
                                               bottomTrailing: style.radius, bottomLeading: 4).fill(style.fill))
                if !author.isEmpty {
                    HStack(spacing: 8) {
                        Text(String(author.prefix(1)).uppercased())
                            .font(style.font(13, .bold))
                            .foregroundColor(style.accentText)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(style.accent))
                        Text(author).font(style.font(13)).foregroundColor(style.muted)
                    }
                }
            }
        default: // card
            VStack(alignment: .leading, spacing: 6) {
                if rating > 0 {
                    Text(String(repeating: "★", count: min(rating, 5))).foregroundColor(style.accent)
                }
                Text(resolve(b.text)).font(style.font(15))
                if !author.isEmpty {
                    Text("— " + author).font(style.font(13)).foregroundColor(style.muted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.card().fill(style.fill))
        }
    }
}

// MARK: - timeline: line | cards | horizontal

struct PaywallTimeline: View {
    let items: [PaywallDoc.Item]
    let variant: String
    let style: PaywallStyle
    let resolve: (String?) -> String

    var body: some View {
        switch variant {
        case "cards":
            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .center, spacing: 12) {
                        icon(item, size: 32, background: style.accent.opacity(0.15))
                        text(item, titleSize: 15, textSize: 13, center: false)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(style.card().fill(style.fill))
                }
            }
        case "horizontal":
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    VStack(spacing: 8) {
                        ZStack {
                            // The rail runs through the circle centres, and not
                            // beyond the first or last.
                            HStack(spacing: 0) {
                                rail.opacity(i == 0 ? 0 : 1)
                                rail.opacity(i == items.count - 1 ? 0 : 1)
                            }
                            icon(item, size: 32, background: style.fill)
                        }
                        text(item, titleSize: 13, textSize: 11, center: true).padding(.horizontal, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        default: // line
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    let last = i == items.count - 1
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            icon(item, size: 28, background: style.accent.opacity(0.15))
                            if !last {
                                Rectangle()
                                    .fill(style.muted.opacity(0.3))
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        text(item, titleSize: 15, textSize: 13, center: false)
                            .padding(.top, 4)
                            .padding(.bottom, last ? 0 : 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var rail: some View {
        Rectangle().fill(style.muted.opacity(0.3)).frame(height: 2).frame(maxWidth: .infinity)
    }

    private func icon(_ item: PaywallDoc.Item, size: CGFloat, background: Color) -> some View {
        Image(systemName: PaywallIcons.symbol(item.icon))
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundColor(style.accent)
            .frame(width: size, height: size)
            .background(Circle().fill(background))
    }

    private func text(_ item: PaywallDoc.Item, titleSize: CGFloat, textSize: CGFloat, center: Bool) -> some View {
        VStack(alignment: center ? .center : .leading, spacing: 2) {
            Text(resolve(item.title)).font(style.font(titleSize, .semibold))
            if let t = item.text, !t.isEmpty {
                Text(resolve(t)).font(style.font(textSize)).foregroundColor(style.muted)
            }
        }
        .multilineTextAlignment(center ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - social_proof: avatars | rating | badge

struct PaywallSocialProof: View {
    let b: PaywallDoc.Block
    let style: PaywallStyle
    let resolve: (String?) -> String

    var body: some View {
        let left = b.align == "left", right = b.align == "right"
        let textAlign: TextAlignment = left ? .leading : right ? .trailing : .center
        let across: HorizontalAlignment = left ? .leading : right ? .trailing : .center
        let subtext = resolve(b.subtext)
        let rating = b.rating ?? 0
        Group {
            switch b.resolvedVariant {
            case "rating":
                VStack(alignment: across, spacing: 6) {
                    if rating > 0 { PaywallStars(count: rating, size: 22, color: style.accent) }
                    Text(resolve(b.text)).font(style.font(17, .bold)).multilineTextAlignment(textAlign)
                    if !subtext.isEmpty {
                        Text(subtext).font(style.font(13)).foregroundColor(style.muted).multilineTextAlignment(textAlign)
                    }
                }
            case "badge":
                HStack(spacing: 8) {
                    PaywallAvatars(images: b.images ?? [], size: 24, ring: style.fill, style: style)
                    Text(resolve(b.text)).font(style.font(13, .semibold)).lineLimit(2)
                }
                .padding(.vertical, 6).padding(.leading, 6).padding(.trailing, 14)
                .background(Capsule().fill(style.fill))
            default: // avatars
                VStack(alignment: across, spacing: 6) {
                    PaywallAvatars(images: b.images ?? [], size: 36, ring: style.background, style: style)
                        .padding(.bottom, 2)
                    if rating > 0 { PaywallStars(count: rating, size: 13, color: style.accent) }
                    Text(resolve(b.text)).font(style.font(15, .semibold)).multilineTextAlignment(textAlign)
                    if !subtext.isEmpty {
                        Text(subtext).font(style.font(13)).foregroundColor(style.muted).multilineTextAlignment(textAlign)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: across, vertical: .center))
    }
}

// MARK: - award: laurel | badge | ribbon

struct PaywallAward: View {
    let b: PaywallDoc.Block
    let style: PaywallStyle
    let resolve: (String?) -> String

    var body: some View {
        let subtext = resolve(b.subtext)
        Group {
            switch b.resolvedVariant {
            case "badge":
                VStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 28))
                        .foregroundColor(style.accent)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(style.accent.opacity(0.15)))
                    Text(resolve(b.text)).font(style.font(17, .bold)).multilineTextAlignment(.center)
                    if !subtext.isEmpty {
                        Text(subtext).font(style.font(12)).foregroundColor(style.muted).multilineTextAlignment(.center)
                    }
                }
            case "ribbon":
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").font(.system(size: 16)).foregroundColor(style.accentText)
                    (Text(resolve(b.text)).font(style.font(14, .bold)).foregroundColor(style.accentText)
                        + Text(subtext.isEmpty ? "" : " · " + subtext).font(style.font(13)).foregroundColor(style.accentText.opacity(0.8)))
                        .lineLimit(1)
                }
                .padding(.vertical, 8).padding(.horizontal, 16)
                .background(Capsule().fill(style.accent))
            default: // laurel
                HStack(spacing: 10) {
                    PaywallLaurel(leading: true).foregroundColor(style.text.opacity(0.7))
                    VStack(spacing: 2) {
                        Text(resolve(b.text)).font(style.font(17, .semibold)).multilineTextAlignment(.center)
                        if !subtext.isEmpty {
                            Text(subtext).font(style.font(12)).foregroundColor(style.muted).multilineTextAlignment(.center)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    PaywallLaurel(leading: false).foregroundColor(style.text.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: ["left": .leading, "right": .trailing][b.align ?? ""] ?? .center)
    }
}

// MARK: - countdown: boxes | labeled | inline | banner

/// HH : MM : SS to a moment, ticking every second.
struct PaywallCountdownView: View {
    let label: String
    let until: String?
    let minutes: Int?
    let variant: String
    let style: PaywallStyle

    /// When the countdown was first shown: "minutes" count from here.
    @State private var start = Date()

    var body: some View {
        let target = PaywallCountdown.target(until: until, minutes: minutes, start: start)
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            content(PaywallCountdown.remaining(to: target, now: context.date))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(_ left: (hours: Int, minutes: Int, seconds: Int)) -> some View {
        let time = String(format: "%02d:%02d:%02d", left.hours, left.minutes, left.seconds)
        switch variant {
        case "inline":
            HStack(spacing: 8) {
                Image(systemName: "clock").font(.system(size: 16, weight: .semibold)).foregroundColor(style.accent)
                if !label.isEmpty { Text(label).font(style.font(13)).foregroundColor(style.muted) }
                Text(time).font(style.font(15, .bold).monospacedDigit()).foregroundColor(style.text)
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(Capsule().fill(style.fill))
            .frame(maxWidth: .infinity)
        case "banner":
            HStack(spacing: 12) {
                Text(label).font(style.font(13, .semibold)).foregroundColor(style.accentText)
                Spacer(minLength: 0)
                Text(time).font(style.font(20, .bold).monospacedDigit()).foregroundColor(style.accentText)
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(style.card().fill(style.accent))
        default: // boxes, labeled
            let units = variant == "labeled"
            VStack(spacing: 8) {
                if !label.isEmpty {
                    Text(label.uppercased())
                        .font(style.font(12, .semibold))
                        .tracking(0.6)
                        .foregroundColor(style.muted)
                }
                HStack(spacing: 6) {
                    digits(left.hours, unit: units ? "hours" : nil)
                    colon
                    digits(left.minutes, unit: units ? "min" : nil)
                    colon
                    digits(left.seconds, unit: units ? "sec" : nil)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var colon: some View {
        Text(":").font(style.font(22, .bold)).foregroundColor(style.muted)
    }

    private func digits(_ n: Int, unit: String?) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%02d", n))
                .font(style.font(24, .bold).monospacedDigit())
                .foregroundColor(style.text)
            if let unit {
                Text(unit).font(style.font(10)).foregroundColor(style.muted)
            }
        }
        .frame(minWidth: 52)
        .padding(.vertical, unit == nil ? 10 : 8)
        .background(style.card(min(style.radius, 12)).fill(style.fill))
    }
}

/// One side of a laurel wreath: the SF Symbol where it exists, else a leaf.
struct PaywallLaurel: View {
    let leading: Bool

    var body: some View {
        if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) {
            Image(systemName: leading ? "laurel.leading" : "laurel.trailing")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 34)
        } else {
            Image(systemName: "leaf.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 30)
                .rotationEffect(.degrees(leading ? -30 : 30))
                .scaleEffect(x: leading ? 1 : -1, y: 1)
                .frame(height: 34)
        }
    }
}

/// A rectangle with its own radius at each corner (iOS 15 has no
/// UnevenRoundedRectangle).
struct PaywallCornerShape: InsettableShape {
    var topLeading: CGFloat = 0
    var topTrailing: CGFloat = 0
    var bottomTrailing: CGFloat = 0
    var bottomLeading: CGFloat = 0
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> PaywallCornerShape {
        var s = self
        s.inset += amount
        return s
    }

    func path(in full: CGRect) -> Path {
        let rect = full.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let limit = min(rect.width, rect.height) / 2
        let tl = min(max(topLeading - inset, 0), limit), tr = min(max(topTrailing - inset, 0), limit)
        let br = min(max(bottomTrailing - inset, 0), limit), bl = min(max(bottomLeading - inset, 0), limit)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}
