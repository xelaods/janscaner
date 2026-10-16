import Foundation
import Observation
import Security

/// APIキーをキーチェーンに保存する
enum Keychain {
    private static let service = "com.xelaods.janscanner.credentials"

    static func read(_ key: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func write(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// 各サイトのAPI設定
@Observable
final class CredentialStore {
    static let shared = CredentialStore()

    var yahooClientID: String { didSet { Keychain.write(yahooClientID.trimmed, for: "yahooClientID") } }
    var rakutenApplicationID: String { didSet { Keychain.write(rakutenApplicationID.trimmed, for: "rakutenApplicationID") } }
    var rakutenAccessKey: String { didSet { Keychain.write(rakutenAccessKey.trimmed, for: "rakutenAccessKey") } }
    var rakutenAffiliateID: String { didSet { Keychain.write(rakutenAffiliateID.trimmed, for: "rakutenAffiliateID") } }
    var rakutenReferer: String { didSet { UserDefaults.standard.set(rakutenReferer.trimmed, forKey: "rakutenReferer") } }

    private init() {
        yahooClientID = Keychain.read("yahooClientID")
        rakutenApplicationID = Keychain.read("rakutenApplicationID")
        rakutenAccessKey = Keychain.read("rakutenAccessKey")
        rakutenAffiliateID = Keychain.read("rakutenAffiliateID")
        rakutenReferer = UserDefaults.standard.string(forKey: "rakutenReferer") ?? ""
    }

    // 自分で入力したキーを優先し、空ならアプリに内蔵されたキーを使う
    var effectiveYahooClientID: String { yahooClientID.trimmed.isEmpty ? BuiltInKeys.yahooClientID : yahooClientID.trimmed }
    var effectiveRakutenApplicationID: String { rakutenApplicationID.trimmed.isEmpty ? BuiltInKeys.rakutenApplicationID : rakutenApplicationID.trimmed }
    var effectiveRakutenAccessKey: String { rakutenAccessKey.trimmed.isEmpty ? BuiltInKeys.rakutenAccessKey : rakutenAccessKey.trimmed }
    var effectiveRakutenReferer: String { rakutenReferer.trimmed.isEmpty ? BuiltInKeys.rakutenReferer : rakutenReferer.trimmed }

    var usesBuiltInYahoo: Bool { yahooClientID.trimmed.isEmpty && !BuiltInKeys.yahooClientID.isEmpty }
    var usesBuiltInRakuten: Bool { rakutenApplicationID.trimmed.isEmpty && !BuiltInKeys.rakutenApplicationID.isEmpty }

    var isYahooReady: Bool { !effectiveYahooClientID.isEmpty }
    var isRakutenReady: Bool {
        !effectiveRakutenApplicationID.isEmpty && !effectiveRakutenAccessKey.isEmpty && !effectiveRakutenReferer.isEmpty
    }
    var hasAnySource: Bool { isYahooReady || isRakutenReady }

    var readySources: [Offer.Source] {
        var list: [Offer.Source] = []
        if isYahooReady { list.append(.yahoo) }
        if isRakutenReady { list.append(.rakuten) }
        return list
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
