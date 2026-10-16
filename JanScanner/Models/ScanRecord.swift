import Foundation
import SwiftData

/// スキャン履歴
@Model
final class ScanRecord {
    @Attribute(.unique) var jan: String
    var title: String
    var imageURLString: String?
    var lowestPrice: Int?
    var lowestShop: String?
    var lowestSourceRaw: String?
    /// 初めて調べたときの最安値（値下がりの表示に使う）
    var firstLowestPrice: Int?
    var offerCount: Int
    var scannedAt: Date
    var isFavorite: Bool

    init(jan: String, title: String) {
        self.jan = jan
        self.title = title
        self.offerCount = 0
        self.scannedAt = .now
        self.isFavorite = false
    }

    var imageURL: URL? { imageURLString.flatMap(URL.init(string:)) }
    var lowestSource: Offer.Source? { lowestSourceRaw.flatMap(Offer.Source.init(rawValue:)) }

    /// 初回からの価格変化（マイナスなら値下がり）
    var priceChange: Int? {
        guard let now = lowestPrice, let first = firstLowestPrice, now != first else { return nil }
        return now - first
    }

    func update(with outcome: SearchOutcome) {
        if let name = outcome.productName { title = name }
        imageURLString = outcome.productImage?.absoluteString ?? imageURLString
        offerCount = outcome.offers.count
        scannedAt = .now
        if let best = outcome.best {
            lowestPrice = best.price
            lowestShop = best.shopName
            lowestSourceRaw = best.source.rawValue
            if firstLowestPrice == nil { firstLowestPrice = best.price }
        }
    }
}
