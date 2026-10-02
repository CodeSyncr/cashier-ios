import CryptoKit
import Foundation

/// App user ids and the StoreKit appAccountToken derived from them.
enum Identity {
    static let anonymousPrefix = "$anon:"
    private static let storageKey = "com.nimbus.cashier.anonymousAppUserID"

    static func isAnonymous(_ id: String) -> Bool { id.hasPrefix(anonymousPrefix) }

    /// The persisted anonymous id, minted on first use.
    static func anonymousID(_ defaults: UserDefaults) -> String {
        if let id = defaults.string(forKey: storageKey), isAnonymous(id) { return id }
        let id = anonymousPrefix + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        defaults.set(id, forKey: storageKey)
        return id
    }

    static func forgetAnonymousID(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: storageKey)
    }

    /// The UUID StoreKit attaches to a purchase as appAccountToken. Apple then
    /// signs it into every transaction and server notification, which is how
    /// Cashier attributes a renewal to the right user even before the app has
    /// uploaded that receipt. An app user id that is already a UUID is used
    /// as-is; any other id maps to a stable name-based (v5) UUID.
    static func appAccountToken(for appUserID: String) -> UUID {
        if let uuid = UUID(uuidString: appUserID) { return uuid }
        // RFC 4122 v5 over a fixed Cashier namespace.
        let namespace = UUID(uuidString: "6f1c1e56-7d2b-4c38-9a51-8f3e0b2a9c11")!
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(Data(appUserID.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
