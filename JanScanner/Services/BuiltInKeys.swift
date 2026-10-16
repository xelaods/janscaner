import Foundation

/// ビルド時に GitHub Actions のシークレットから埋め込まれるキー。
/// リポジトリ上は空のままにしておく（公開リポジトリにキーを置かないため）。
enum BuiltInKeys {
    static let yahooClientID = ""
    static let rakutenApplicationID = ""
    static let rakutenAccessKey = ""
    static let rakutenReferer = ""
}
