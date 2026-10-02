# Changelog

## Unreleased

- **Experiments:** `offerings()` sends `?app_user_id=` for A/B test assignment. New `Offerings.experiment` and `Offering.experiment` (`PaywallExperiment(id:variant:)`, set on the offering the experiment chose) and `Offering.paywallID`.
- **Paywall analytics:** `PaywallView` posts a `view` event when a paywall is first shown and a `close` when it is dismissed without a purchase (`POST /paywalls/events`, fire-and-forget). Preview-token drafts send nothing.
- **Answer capture:** buttons with an `answer` (Feedback / Marketing Consent screens) call the new `onAnswer: ((PaywallAnswer) -> Void)?` on `PaywallView`, `PaywallContent` and `presentPaywallIfNeeded`, and are recorded with `POST /paywalls/responses`, before the button's action runs. New `Block.answer`, `Screen.question`, `Screen.answerQuestion`.
- **Localization:** paywall documents decode `default_locale`, `locales` and `strings`; `PaywallView` / `presentPaywallIfNeeded` take `locale: Locale?` (default `Locale.preferredLanguages.first`) and draw the best-matching translation (exact → same language → default). `PaywallDoc.localized(to:)` / `localized(for:)` for rendering `PaywallContent` in a given language.
- Existing initializers and call sites are unchanged; every new parameter has a default.
- **CocoaPods:** `NimbusCashier.podspec` (iOS 15, macOS 12, Swift 5.10; `paywall-art.json` ships in a `NimbusCashier` resource bundle, found by `PaywallArt` when SwiftPM's `Bundle.module` is not available). Tag releases with the bare version (`1.1.0`) — the podspec's `:tag` is `s.version`.

## 1.0.0

First release.

- StoreKit 2 purchases verified by your Nimbus Cashier app; entitlements, customer info (cached, streamed), log in / log out, restore and sync.
- Offerings and packages from the console.
- `PaywallView` and `.presentPaywallIfNeeded(requiredEntitlement:)`: paywalls designed in the Cashier editor drawn natively in SwiftUI — flows of screens, plan cards, tiers, art, media, effects and motion.
- `previewOffering(token:)` to check an unpublished paywall on a device.
