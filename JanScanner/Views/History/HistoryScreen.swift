import SwiftData
import SwiftUI

struct HistoryScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanRecord.scannedAt, order: .reverse) private var records: [ScanRecord]
    @State private var searchText = ""
    @State private var favoritesOnly = false

    private var filtered: [ScanRecord] {
        records.filter { record in
            (!favoritesOnly || record.isFavorite)
                && (searchText.isEmpty
                    || record.title.localizedCaseInsensitiveContains(searchText)
                    || record.jan.contains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("まだ履歴がありません", systemImage: "barcode.viewfinder")
                    } description: {
                        Text("商品をスキャンすると、ここに最安値と一緒に記録されます。")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("履歴")
            .navigationDestination(for: String.self) { jan in
                ResultView(jan: jan)
            }
            .toolbar {
                if !records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.snappy) { favoritesOnly.toggle() }
                        } label: {
                            Image(systemName: favoritesOnly ? "star.fill" : "star")
                        }
                        .accessibilityLabel("お気に入りだけ表示")
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            if favoritesOnly && filtered.isEmpty {
                Text("お気に入りはまだありません")
                    .foregroundStyle(.secondary)
            }
            ForEach(groupedSections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items) { record in
                        NavigationLink(value: record.jan) {
                            HistoryRow(record: record)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                record.isFavorite.toggle()
                                try? context.save()
                            } label: {
                                Label("お気に入り", systemImage: record.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                context.delete(record)
                                try? context.save()
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "商品名・JANで検索")
    }

    private struct DaySection {
        let title: String
        let items: [ScanRecord]
    }

    private var groupedSections: [DaySection] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [ScanRecord]] = [:]
        for record in filtered {
            let title: String
            if calendar.isDateInToday(record.scannedAt) {
                title = "今日"
            } else if calendar.isDateInYesterday(record.scannedAt) {
                title = "昨日"
            } else if let days = calendar.dateComponents([.day], from: record.scannedAt, to: .now).day, days < 7 {
                title = "この1週間"
            } else {
                title = record.scannedAt.formatted(.dateTime.year().month())
            }
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(record)
        }
        return order.map { DaySection(title: $0, items: buckets[$0] ?? []) }
    }
}

struct HistoryRow: View {
    let record: ScanRecord

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(url: record.imageURL, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if record.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(record.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let source = record.lowestSource {
                        SourceBadge(source: source)
                    }
                    Text(record.lowestShop ?? record.jan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(record.lowestPrice?.yen ?? "—")
                    .font(.price(17))
                if let change = record.priceChange {
                    Text(change < 0 ? "▼\((-change).yen)" : "▲\(change.yen)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(change < 0 ? Theme.saving : Color.red)
                } else {
                    Text(record.scannedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
