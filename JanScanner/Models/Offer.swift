import Foundation

/// 1つのショップでの販売情報
struct Offer: Identifiable, Hashable, Sendable {
    enum Source: String, Codable, CaseIterable, Sendable, Identifiable {
        case yahoo
        case rakuten

        var id: String { rawValue }

        var label: String {
            switch self {
            case .yahoo: return "Yahoo!ショッピング"
            case .rakuten: return "楽天市場"
            }
        }

        var shortLabel: String {
            switch self {
            case .yahoo: return "Yahoo!"
            case .rakuten: return "楽天"
            }
        }
    }

    enum Shipping: Hashable, Sendable {
        case free
        case conditionalFree
        case extra
        case unknown

        var label: String {
            switch self {
            case .free: return "送料無料"
            case .conditionalFree: return "条件付き送料無料"
            case .extra: return "送料別"
            case .unknown: return "送料不明"
            }
        }

        var isFree: Bool { self == .free }
    }

    let id: String
    let source: Source
    let title: String
    let price: Int
    let shopName: String
    let url: URL
    let imageURL: URL?
    let shipping: Shipping
    let pointRate: Int?
    let reviewAverage: Double?
    let reviewCount: Int?
}

/// 検索結果全体
struct SearchOutcome: Sendable {
    var jan: String
    var offers: [Offer]
    var errors: [Offer.Source: String]
    var searchedSources: [Offer.Source]

    var sortedOffers: [Offer] { offers.sorted { $0.price < $1.price } }
    var best: Offer? { sortedOffers.first }
    var highest: Int? { offers.map(\.price).max() }

    var median: Int? {
        let prices = offers.map(\.price).sorted()
        guard !prices.isEmpty else { return nil }
        let mid = prices.count / 2
        return prices.count % 2 == 0 ? (prices[mid - 1] + prices[mid]) / 2 : prices[mid]
    }

    /// 商品名（一番よく使われていそうなもの＝画像付きの最初の結果）
    var productName: String? {
        let candidates = sortedOffers
        return (candidates.first(where: { $0.source == .yahoo }) ?? candidates.first)?.title
    }

    var productImage: URL? {
        sortedOffers.first(where: { $0.imageURL != nil })?.imageURL
    }
}
