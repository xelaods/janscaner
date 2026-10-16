import SwiftUI

enum Theme {
    /// 値札のような朱色
    static let accent = Color("AccentColor")
    static let saving = Color(red: 0.13, green: 0.62, blue: 0.38)
    static let card = Color(.secondarySystemGroupedBackground)
    static let background = Color(.systemGroupedBackground)

    static func color(for source: Offer.Source) -> Color {
        switch source {
        case .yahoo: return Color(red: 1.0, green: 0.0, blue: 0.2)
        case .rakuten: return Color(red: 0.75, green: 0.0, blue: 0.0)
        }
    }
}

extension Int {
    var yen: String { "¥" + formatted(.number.grouping(.automatic)) }

    /// 差額表示（+¥120 / −¥80）
    var signedYen: String {
        if self > 0 { return "+" + yen }
        if self < 0 { return "−" + (-self).yen }
        return "±¥0"
    }
}

/// 価格用の数字フォント
extension Font {
    static func price(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// ショップの出どころを示す小さなラベル
struct SourceBadge: View {
    let source: Offer.Source
    var compact = true

    var body: some View {
        Text(compact ? source.shortLabel : source.label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Theme.color(for: source), in: Capsule())
    }
}

struct ShippingBadge: View {
    let shipping: Offer.Shipping

    var body: some View {
        Label(shipping.label, systemImage: shipping.isFree ? "shippingbox.fill" : "shippingbox")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(shipping.isFree ? Theme.saving : .secondary)
    }
}

/// 商品画像（読み込み中はプレースホルダー）
struct ProductThumbnail: View {
    let url: URL?
    var size: CGFloat = 56
    var corner: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white)
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().padding(size * 0.06)
                case .failure:
                    placeholder
                default:
                    if url == nil { placeholder } else { ProgressView().controlSize(.small) }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        Image(systemName: "barcode")
            .font(.system(size: size * 0.32, weight: .light))
            .foregroundStyle(Color.gray.opacity(0.6))
    }
}

/// 読み込み中のきらめき
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.45), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.6)
                    .offset(x: phase * proxy.size.width * 1.6)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// SafariViewController で開くためのURL
struct BrowserItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
