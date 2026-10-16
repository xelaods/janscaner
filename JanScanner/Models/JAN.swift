import Foundation

/// JAN（EAN-13 / EAN-8）コードの正規化とチェックディジット検証
enum JAN {
    /// 読み取った文字列を正しいJANに整える。不正なら nil
    static func normalize(_ raw: String) -> String? {
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        switch digits.count {
        case 13, 8:
            return isValid(digits) ? digits : nil
        case 12:
            // UPC-A は先頭に 0 を付けると EAN-13 になる
            let ean = "0" + digits
            return isValid(ean) ? ean : nil
        default:
            return nil
        }
    }

    static func isValid(_ code: String) -> Bool {
        let digits = code.compactMap { $0.wholeNumberValue }
        guard digits.count == code.count, digits.count == 13 || digits.count == 8,
              let check = digits.last else { return false }
        var sum = 0
        for (index, value) in digits.dropLast().reversed().enumerated() {
            sum += value * (index % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }

    /// 表示用に区切る（例: 4 901234 567894）
    static func formatted(_ code: String) -> String {
        guard code.count == 13 else { return code }
        let chars = Array(code)
        return "\(chars[0]) \(String(chars[1...6])) \(String(chars[7...12]))"
    }

    /// 書籍（ISBN）かどうか
    static func isBook(_ code: String) -> Bool {
        code.hasPrefix("978") || code.hasPrefix("979")
    }
}
