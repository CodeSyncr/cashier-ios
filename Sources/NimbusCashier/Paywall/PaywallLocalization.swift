import Foundation

// Paywall translations. The document's block texts are written in
// `default_locale`; `strings[locale]` overrides them key by key. Resolution
// is the same in every Cashier SDK (web, iOS, Android, Flutter).

extension PaywallDoc {
    /// A copy of this document with the texts of the locale best matching
    /// `locale` (a BCP-47 tag such as "pt-BR"; `_` is read as `-`). nil
    /// asks for the device's first preferred language.
    ///
    /// 1. An exact (case-insensitive) match in `locales`; else the first of
    ///    `locales` with the same language (`pt-BR` → `pt`); else none.
    /// 2. With no exact match, a request in `default_locale`'s language
    ///    keeps the default texts.
    /// 3. Every non-empty translation replaces its field; missing keys keep
    ///    the default text. `{{variables}}` in a translation are filled in
    ///    when drawn, as for default text.
    ///
    /// `PaywallView` does this itself before drawing; call it to draw a
    /// `PaywallContent` in a given language.
    public func localized(to locale: String?) -> PaywallDoc {
        guard let tag = locale ?? Locale.preferredLanguages.first,
              let chosen = PaywallLocalization.match(requested: tag, locales: locales ?? [], defaultLocale: defaultLocale),
              let table = strings?[chosen], !table.isEmpty else { return self }
        var doc = self
        let t = table.filter { !$0.value.isEmpty }
        doc.screens = screens?.map { PaywallLocalization.apply(t, to: $0) }
        doc.blocks = blocks?.map { PaywallLocalization.apply(t, to: $0) }
        return doc
    }

    /// `localized(to:)` for a `Locale`; nil is the device's first preferred language.
    public func localized(for locale: Locale?) -> PaywallDoc {
        localized(to: locale.map(PaywallLocalization.tag))
    }
}

enum PaywallLocalization {
    /// A Locale as a BCP-47-ish tag: "pt_BR" → "pt-BR", keywords dropped.
    static func tag(_ locale: Locale) -> String {
        normalize(locale.identifier)
    }

    static func normalize(_ tag: String) -> String {
        let bare = tag.split(separator: "@", maxSplits: 1).first.map(String.init) ?? tag
        return bare.replacingOccurrences(of: "_", with: "-").trimmingCharacters(in: .whitespaces)
    }

    static func language(_ tag: String) -> String {
        String(normalize(tag).split(separator: "-", maxSplits: 1).first ?? "").lowercased()
    }

    /// Which of `locales` to draw for `requested`; nil keeps the default texts.
    static func match(requested: String, locales: [String], defaultLocale: String?) -> String? {
        let want = normalize(requested).lowercased()
        guard !want.isEmpty else { return nil }
        if let exact = locales.first(where: { normalize($0).lowercased() == want }) { return exact }
        let lang = language(want)
        let base = (defaultLocale ?? "").isEmpty ? "en" : defaultLocale!
        if lang == language(base) { return nil }
        return locales.first { language($0) == lang }
    }

    static func apply(_ t: [String: String], to screen: PaywallDoc.Screen) -> PaywallDoc.Screen {
        var s = screen
        if let q = t[screen.id + ".question"] { s.question = q }
        s.blocks = screen.blocks.map { apply(t, to: $0) }
        return s
    }

    static func apply(_ t: [String: String], to block: PaywallDoc.Block) -> PaywallDoc.Block {
        var b = block
        let id = block.id
        if let v = t[id + ".text"] { b.text = v }
        if let v = t[id + ".subtext"] { b.subtext = v }
        if let v = t[id + ".author"] { b.author = v }
        if let v = t[id + ".badge"] { b.badge = v }
        if let v = t[id + ".answer"] { b.answer = v }
        if let items = block.items {
            b.items = items.enumerated().map { i, item in
                var it = item
                if let v = t["\(id).items.\(i).title"] { it.title = v }
                if let v = t["\(id).items.\(i).text"] { it.text = v }
                return it
            }
        }
        if let badges = block.badges {
            var out = badges
            for key in badges.keys { if let v = t["\(id).badges.\(key)"] { out[key] = v } }
            b.badges = out
        }
        b.children = block.children?.map { apply(t, to: $0) }
        return b
    }
}
