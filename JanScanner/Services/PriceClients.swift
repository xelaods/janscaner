import Foundation

enum PriceError: LocalizedError {
    case notConfigured
    case http(Int, String?)
    case decoding
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "APIキーが未設定です"
        case .http(let code, let message):
            switch code {
            case 400: return message ?? "リクエストが不正です（400）"
            case 401, 403: return "認証エラー：APIキーやURL設定を確認してください（\(code)）"
            case 429: return "アクセスが集中しています。少し待って再度お試しください"
            default: return message ?? "サーバーエラー（\(code)）"
            }
        case .decoding: return "応答の読み取りに失敗しました"
        case .network(let message): return message
        }
    }
}

/// 数値でも文字列でも読める値
struct FlexibleNumber: Decodable, Sendable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }

    var int: Int? { value.map { Int($0.rounded()) } }
}

protocol PriceClient: Sendable {
    var source: Offer.Source { get }
    func search(jan: String) async throws -> [Offer]
}

private let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 12
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config)
}()

private func perform(_ request: URLRequest) async throws -> Data {
    do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PriceError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw PriceError.http(http.statusCode, extractMessage(from: data))
        }
        return data
    } catch let error as PriceError {
        throw error
    } catch let error as URLError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            throw PriceError.network("インターネットに接続されていません")
        case .timedOut:
            throw PriceError.network("タイムアウトしました")
        default:
            throw PriceError.network(error.localizedDescription)
        }
    }
}

private func extractMessage(from data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    if let error = object["Error"] as? [String: Any], let message = error["Message"] as? String { return message }
    if let message = object["error_description"] as? String { return message }
    if let errors = object["errors"] as? [String: Any], let message = errors["errorMessage"] as? String { return message }
    return nil
}

// MARK: - Yahoo!ショッピング

struct YahooClient: PriceClient {
    let source: Offer.Source = .yahoo
    let clientID: String

    private struct Response: Decodable {
        let hits: [Hit]?
    }

    private struct Hit: Decodable {
        struct Image: Decodable { let small: String?; let medium: String? }
        struct Store: Decodable { let name: String? }
        struct Shipping: Decodable { let code: FlexibleNumber?; let name: String? }
        struct Review: Decodable { let rate: FlexibleNumber?; let count: FlexibleNumber? }
        struct Point: Decodable { let times: FlexibleNumber? }

        let index: FlexibleNumber?
        let name: String?
        let code: String?
        let url: String?
        let price: FlexibleNumber?
        let inStock: Bool?
        let image: Image?
        let store: Store?
        let shipping: Shipping?
        let review: Review?
        let point: Point?
    }

    func search(jan: String) async throws -> [Offer] {
        guard !clientID.isEmpty else { throw PriceError.notConfigured }
        var components = URLComponents(string: "https://shopping.yahooapis.jp/ShoppingWebService/V3/itemSearch")!
        components.queryItems = [
            URLQueryItem(name: "appid", value: clientID),
            URLQueryItem(name: "jan_code", value: jan),
            URLQueryItem(name: "results", value: "50"),
            URLQueryItem(name: "in_stock", value: "true"),
            URLQueryItem(name: "sort", value: "+price")
        ]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await perform(request)
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw PriceError.decoding }

        return (decoded.hits ?? []).enumerated().compactMap { index, hit in
            guard let price = hit.price?.int, price > 0,
                  let urlString = hit.url, let url = URL(string: urlString) else { return nil }
            if hit.inStock == false { return nil }
            let shipping: Offer.Shipping
            switch hit.shipping?.code?.int {
            case 2: shipping = .free
            case 3: shipping = .conditionalFree
            case 1: shipping = .extra
            default: shipping = .unknown
            }
            return Offer(
                id: "yahoo-\(hit.code ?? String(index))",
                source: .yahoo,
                title: hit.name ?? "名称不明",
                price: price,
                shopName: hit.store?.name ?? "ストア",
                url: url,
                imageURL: (hit.image?.medium ?? hit.image?.small).flatMap(URL.init(string:)),
                shipping: shipping,
                pointRate: nil,
                reviewAverage: hit.review?.rate?.value,
                reviewCount: hit.review?.count?.int
            )
        }
    }
}

// MARK: - 楽天市場

struct RakutenClient: PriceClient {
    let source: Offer.Source = .rakuten
    let applicationID: String
    let accessKey: String
    let affiliateID: String
    let referer: String

    private struct Response: Decodable {
        let Items: [Item]?
    }

    private struct Item: Decodable {
        let itemName: String?
        let itemPrice: FlexibleNumber?
        let itemUrl: String?
        let affiliateUrl: String?
        let itemCode: String?
        let shopName: String?
        let mediumImageUrls: [ImageURL]?
        let postageFlag: FlexibleNumber?
        let pointRate: FlexibleNumber?
        let reviewAverage: FlexibleNumber?
        let reviewCount: FlexibleNumber?
        let availability: FlexibleNumber?
    }

    /// formatVersion=2 では文字列、1 では {"imageUrl": ...} の形になる
    private struct ImageURL: Decodable {
        let url: String?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                url = text
            } else if let object = try? container.decode([String: String].self) {
                url = object["imageUrl"]
            } else {
                url = nil
            }
        }
    }

    func search(jan: String) async throws -> [Offer] {
        guard !applicationID.isEmpty, !accessKey.isEmpty else { throw PriceError.notConfigured }
        var components = URLComponents(string: "https://openapi.rakuten.co.jp/ichibams/api/IchibaItem/Search/20220601")!
        var items = [
            URLQueryItem(name: "applicationId", value: applicationID),
            URLQueryItem(name: "accessKey", value: accessKey),
            URLQueryItem(name: "keyword", value: jan),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatVersion", value: "2"),
            URLQueryItem(name: "hits", value: "30"),
            URLQueryItem(name: "availability", value: "1"),
            URLQueryItem(name: "sort", value: "+itemPrice")
        ]
        if !affiliateID.isEmpty { items.append(URLQueryItem(name: "affiliateId", value: affiliateID)) }
        components.queryItems = items
        // "+" はそのままだと空白扱いになるのでエンコードする
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
            if let url = URL(string: referer), let scheme = url.scheme, let host = url.host {
                request.setValue("\(scheme)://\(host)", forHTTPHeaderField: "Origin")
            }
        }
        let data = try await perform(request)
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw PriceError.decoding }

        return (decoded.Items ?? []).enumerated().compactMap { index, item in
            guard let price = item.itemPrice?.int, price > 0 else { return nil }
            let link = (item.affiliateUrl?.isEmpty == false ? item.affiliateUrl : item.itemUrl) ?? ""
            guard let url = URL(string: link) else { return nil }
            let image = item.mediumImageUrls?.first?.url.map {
                $0.replacingOccurrences(of: "_ex=128x128", with: "_ex=300x300")
            }
            return Offer(
                id: "rakuten-\(item.itemCode ?? String(index))",
                source: .rakuten,
                title: item.itemName ?? "名称不明",
                price: price,
                shopName: item.shopName ?? "ショップ",
                url: url,
                imageURL: image.flatMap(URL.init(string:)),
                shipping: item.postageFlag?.int == 0 ? .free : (item.postageFlag?.int == 1 ? .extra : .unknown),
                pointRate: item.pointRate?.int,
                reviewAverage: item.reviewAverage?.value,
                reviewCount: item.reviewCount?.int
            )
        }
    }
}

// MARK: - まとめて検索

enum PriceService {
    static func clients(_ store: CredentialStore = .shared) -> [any PriceClient] {
        var list: [any PriceClient] = []
        if store.isYahooReady {
            list.append(YahooClient(clientID: store.yahooClientID.trimmed))
        }
        if store.isRakutenReady {
            list.append(RakutenClient(
                applicationID: store.rakutenApplicationID.trimmed,
                accessKey: store.rakutenAccessKey.trimmed,
                affiliateID: store.rakutenAffiliateID.trimmed,
                referer: store.rakutenReferer.trimmed
            ))
        }
        return list
    }

    static func search(jan: String) async -> SearchOutcome {
        let clients = clients()
        var outcome = SearchOutcome(jan: jan, offers: [], errors: [:], searchedSources: clients.map(\.source))
        await withTaskGroup(of: (Offer.Source, Result<[Offer], Error>).self) { group in
            for client in clients {
                group.addTask {
                    do { return (client.source, .success(try await client.search(jan: jan))) }
                    catch { return (client.source, .failure(error)) }
                }
            }
            for await (source, result) in group {
                switch result {
                case .success(let offers): outcome.offers.append(contentsOf: offers)
                case .failure(let error): outcome.errors[source] = error.localizedDescription
                }
            }
        }
        // 同じURLの重複を除く
        var seen = Set<URL>()
        outcome.offers = outcome.offers.filter { seen.insert($0.url).inserted }
        return outcome
    }

    /// 設定画面の接続テスト
    static func test(_ source: Offer.Source) async -> Result<Int, Error> {
        guard let client = clients().first(where: { $0.source == source }) else {
            return .failure(PriceError.notConfigured)
        }
        do { return .success(try await client.search(jan: "4902102072618").count) }
        catch { return .failure(error) }
    }
}
