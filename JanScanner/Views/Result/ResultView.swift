import SwiftData
import SwiftUI

struct ResultView: View {
    let jan: String

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var matching: [ScanRecord]

    @State private var outcome: SearchOutcome?
    @State private var isLoading = true
    @State private var sourceFilter: Offer.Source?
    @State private var freeShippingOnly = false
    @State private var browser: BrowserItem?
    @State private var copiedTick = 0

    init(jan: String) {
        self.jan = jan
        let code = jan
        _matching = Query(filter: #Predicate<ScanRecord> { $0.jan == code })
    }

    private var record: ScanRecord? { matching.first }

    private var visibleOffers: [Offer] {
        (outcome?.sortedOffers ?? []).filter { offer in
            (sourceFilter == nil || offer.source == sourceFilter)
                && (!freeShippingOnly || offer.shipping.isFree)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                productHeader
                content
                OtherSitesSection(jan: jan) { url in browser = BrowserItem(url: url) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(outcome?.productName == nil ? "検索結果" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { toolbarContent }
        .refreshable { await load() }
        .task {
            if outcome == nil { await load() }
        }
        .browserSheet($browser)
        .sensoryFeedback(.success, trigger: copiedTick)
    }

    // MARK: - 中身

    @ViewBuilder
    private var content: some View {
        if isLoading && outcome == nil {
            LoadingPlaceholder()
        } else if let outcome {
            if outcome.searchedSources.isEmpty {
                notConfiguredView
            } else if outcome.offers.isEmpty {
                emptyView(outcome)
            } else {
                if let best = outcome.best {
                    BestPriceCard(best: best, median: outcome.median, count: outcome.offers.count) {
                        browser = BrowserItem(url: best.url)
                    }
                }
                PriceDistributionCard(outcome: outcome)
                filterBar(outcome)
                offerList(outcome)
            }
            ForEach(outcome.errors.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { source in
                ErrorBanner(source: source, message: outcome.errors[source] ?? "")
            }
        }
    }

    private var productHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ProductThumbnail(url: outcome?.productImage ?? record?.imageURL, size: 92, corner: 16)
            VStack(alignment: .leading, spacing: 8) {
                if let name = outcome?.productName ?? record?.title, !(isLoading && outcome == nil && record == nil) {
                    Text(name)
                        .font(.headline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.18)).frame(height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.18)).frame(width: 140, height: 14)
                    }
                    .shimmering()
                }
                Button {
                    UIPasteboard.general.string = jan
                    copiedTick += 1
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "barcode")
                        Text(JAN.formatted(jan))
                            .font(.system(.footnote, design: .monospaced).weight(.medium))
                        Image(systemName: copiedTick > 0 ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("JANコードをコピー")
                if JAN.isBook(jan) {
                    Label("書籍（ISBN）", systemImage: "book.closed")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func filterBar(_ outcome: SearchOutcome) -> some View {
        let sources = Offer.Source.allCases.filter { source in outcome.offers.contains { $0.source == source } }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "すべて", count: outcome.offers.count, isOn: sourceFilter == nil) {
                    sourceFilter = nil
                }
                ForEach(sources) { source in
                    FilterChip(title: source.shortLabel,
                               count: outcome.offers.filter { $0.source == source }.count,
                               isOn: sourceFilter == source) {
                        sourceFilter = sourceFilter == source ? nil : source
                    }
                }
                Divider().frame(height: 20)
                FilterChip(title: "送料無料", systemImage: "shippingbox", isOn: freeShippingOnly) {
                    freeShippingOnly.toggle()
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .animation(.snappy, value: sourceFilter)
        .animation(.snappy, value: freeShippingOnly)
    }

    @ViewBuilder
    private func offerList(_ outcome: SearchOutcome) -> some View {
        let offers = visibleOffers
        let minimum = outcome.best?.price ?? 0
        if offers.isEmpty {
            Text("条件に合うショップがありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(offers.enumerated()), id: \.element.id) { index, offer in
                    Button {
                        browser = BrowserItem(url: offer.url)
                    } label: {
                        OfferRow(offer: offer, rank: index + 1, difference: offer.price - minimum)
                    }
                    .buttonStyle(RowButtonStyle())
                    .contextMenu {
                        Button {
                            UIPasteboard.general.url = offer.url
                        } label: {
                            Label("リンクをコピー", systemImage: "link")
                        }
                        ShareLink(item: offer.url) {
                            Label("共有", systemImage: "square.and.arrow.up")
                        }
                        Link(destination: offer.url) {
                            Label("Safariで開く", systemImage: "safari")
                        }
                    }
                    if index < offers.count - 1 {
                        Divider().padding(.leading, 108)
                    }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var notConfiguredView: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)
            Text("検索先が設定されていません")
                .font(.headline)
            Text("設定でYahoo!ショッピングか楽天市場のAPIキーを登録すると、最安値を表示できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("設定を開く") { router.tab = .settings }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func emptyView(_ outcome: SearchOutcome) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("販売中のショップが見つかりませんでした")
                .font(.headline)
            Text(outcome.errors.isEmpty
                 ? "取り扱いがないか、在庫切れの可能性があります。下のサイトでも探してみてください。"
                 : "一部の検索に失敗しました。下のメッセージを確認してください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let record {
                Button {
                    record.isFavorite.toggle()
                    try? context.save()
                } label: {
                    Image(systemName: record.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(record.isFavorite ? Color.yellow : Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel("お気に入り")
            }
            if let best = outcome?.best {
                ShareLink(item: best.url,
                          subject: Text(outcome?.productName ?? jan),
                          message: Text("最安値 \(best.price.yen)（\(best.shopName)）")) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - 読み込み

    private func load() async {
        isLoading = true
        let result = await PriceService.search(jan: jan)
        withAnimation(.snappy) {
            outcome = result
            isLoading = false
        }
        save(result)
    }

    private func save(_ result: SearchOutcome) {
        guard !result.offers.isEmpty else { return }
        let target: ScanRecord
        if let record {
            target = record
        } else {
            target = ScanRecord(jan: jan, title: result.productName ?? jan)
            context.insert(target)
        }
        target.update(with: result)
        try? context.save()
    }
}

// MARK: - 部品

struct BestPriceCard: View {
    let best: Offer
    let median: Int?
    let count: Int
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("最安値", systemImage: "crown.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent, in: Capsule())
                Spacer()
                Text("\(count)件中")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(best.price.yen)
                .font(.price(48, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(best.price)))

            HStack(spacing: 10) {
                ShippingBadge(shipping: best.shipping)
                if let rate = best.pointRate, rate > 1 {
                    Label("ポイント\(rate)倍", systemImage: "p.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if let median, median > best.price {
                    Label("相場より\((median - best.price).yen)安い", systemImage: "arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.saving)
                }
            }

            HStack(spacing: 8) {
                SourceBadge(source: best.source, compact: false)
                Text(best.shopName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Button(action: onOpen) {
                HStack {
                    Text("このショップで見る")
                    Image(systemName: "arrow.up.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .padding(.top, 2)
        }
        .padding(20)
        .background(
            ZStack(alignment: .topTrailing) {
                Theme.card
                Image(systemName: "tag.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(Theme.accent.opacity(0.06))
                    .rotationEffect(.degrees(-20))
                    .offset(x: 30, y: -20)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Theme.accent.opacity(0.12), radius: 18, y: 8)
    }
}

/// 価格の散らばり具合
struct PriceDistributionCard: View {
    let outcome: SearchOutcome

    var body: some View {
        let prices = outcome.offers.map(\.price).sorted()
        let low = prices.first ?? 0
        let high = prices.last ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("価格の分布")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let median = outcome.median {
                    Text("中央値 \(median.yen)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.saving.opacity(0.35), Color.gray.opacity(0.18)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    ForEach(Array(prices.enumerated()), id: \.offset) { index, price in
                        let ratio = high == low ? 0.5 : CGFloat(price - low) / CGFloat(high - low)
                        Circle()
                            .fill(index == 0 ? Theme.accent : Color.primary.opacity(0.35))
                            .frame(width: index == 0 ? 14 : 7, height: index == 0 ? 14 : 7)
                            .overlay(Circle().strokeBorder(.white, lineWidth: index == 0 ? 2 : 0))
                            .offset(x: ratio * (width - 14) + (index == 0 ? 0 : 3.5))
                            .zIndex(index == 0 ? 1 : 0)
                    }
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("最安").font(.caption2).foregroundStyle(.secondary)
                    Text(low.yen).font(.price(14, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("最高").font(.caption2).foregroundStyle(.secondary)
                    Text(high.yen).font(.price(14, weight: .semibold))
                }
            }
            if high > low {
                Text("最高値との差 \((high - low).yen)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct OfferRow: View {
    let offer: Offer
    let rank: Int
    let difference: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(rank)")
                .font(.price(15, weight: .heavy))
                .foregroundStyle(rank == 1 ? Theme.accent : Color.secondary)
                .frame(width: 24)
            ProductThumbnail(url: offer.imageURL, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SourceBadge(source: offer.source)
                    Text(offer.shopName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(offer.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    ShippingBadge(shipping: offer.shipping)
                    if let average = offer.reviewAverage, average > 0 {
                        Label(String(format: "%.1f", average), systemImage: "star.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(offer.price.yen)
                    .font(.price(18))
                    .foregroundStyle(rank == 1 ? Theme.accent : Color.primary)
                if difference > 0 {
                    Text(difference.signedYen)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
    }
}

struct FilterChip: View {
    let title: String
    var count: Int? = nil
    var systemImage: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption.weight(.semibold))
                }
                Text(title).font(.subheadline.weight(.semibold))
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .opacity(0.7)
                }
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ErrorBanner: View {
    let source: Offer.Source
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(source.label)の検索に失敗")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct LoadingPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.card)
                .frame(height: 230)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 14) {
                        Capsule().fill(Color.gray.opacity(0.2)).frame(width: 70, height: 22)
                        RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(width: 190, height: 46)
                        RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15)).frame(width: 140, height: 14)
                        Spacer()
                        RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.15)).frame(height: 48)
                    }
                    .padding(20)
                }
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.18)).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.18)).frame(width: 120, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)).frame(height: 10)
                    }
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.18)).frame(width: 60, height: 16)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text("各ショップの価格を確認しています…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .shimmering()
    }
}

/// APIのない大手サイトを検索ページで開く
struct OtherSitesSection: View {
    let jan: String
    var open: (URL) -> Void

    private struct Site: Identifiable {
        let name: String
        let icon: String
        let url: String
        var id: String { name }
    }

    private var sites: [Site] {
        [
            Site(name: "Amazon", icon: "cart", url: "https://www.amazon.co.jp/s?k=\(jan)"),
            Site(name: "価格.com", icon: "chart.bar", url: "https://search.kakaku.com/\(jan)/"),
            Site(name: "ヨドバシ", icon: "bag", url: "https://www.yodobashi.com/?word=\(jan)"),
            Site(name: "メルカリ", icon: "arrow.2.squarepath", url: "https://jp.mercari.com/search?keyword=\(jan)"),
            Site(name: "Google", icon: "magnifyingglass", url: "https://www.google.com/search?tbm=shop&q=\(jan)")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ほかのサイトでも探す")
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(sites) { site in
                    Button {
                        if let url = URL(string: site.url) { open(url) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: site.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text(site.name)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }
}
