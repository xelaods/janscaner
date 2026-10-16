import SwiftData
import SwiftUI

struct SettingsScreen: View {
    @Environment(CredentialStore.self) private var credentials
    @Environment(\.modelContext) private var context
    @Query private var records: [ScanRecord]

    @State private var browser: BrowserItem?
    @State private var testResults: [Offer.Source: TestState] = [:]
    @State private var confirmClear = false

    enum TestState: Equatable {
        case running
        case success(Int)
        case failure(String)
    }

    var body: some View {
        @Bindable var credentials = credentials
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "tag.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("検索先")
                                .font(.headline)
                            Text("APIキーを登録したサイトから、同じJANの商品を一度に検索します。キーは端末内（キーチェーン）にだけ保存されます。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Yahoo
                Section {
                    statusRow(.yahoo, ready: credentials.isYahooReady)
                    KeyField(title: "Client ID", text: $credentials.yahooClientID)
                    testButton(.yahoo, enabled: credentials.isYahooReady)
                } header: {
                    Text("Yahoo!ショッピング")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Yahoo!デベロッパーネットワークでアプリケーションを登録し、Client IDを入力してください。")
                        linkButton("Client IDを取得する", "https://e.developer.yahoo.co.jp/register")
                    }
                }

                // 楽天
                Section {
                    statusRow(.rakuten, ready: credentials.isRakutenReady)
                    KeyField(title: "アプリID", text: $credentials.rakutenApplicationID)
                    KeyField(title: "アクセスキー", text: $credentials.rakutenAccessKey)
                    KeyField(title: "登録したURL", text: $credentials.rakutenReferer, secure: false,
                             placeholder: "https://example.com/")
                    KeyField(title: "アフィリエイトID（任意）", text: $credentials.rakutenAffiliateID)
                    testButton(.rakuten, enabled: credentials.isRakutenReady)
                } header: {
                    Text("楽天市場")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("楽天ウェブサービスでアプリを登録し、アプリIDとアクセスキーを入力してください。「登録したURL」には、アプリ登録時に入力したURLを同じ形で入れます（Refererとして送信します）。")
                        linkButton("アプリIDを取得する", "https://webservice.rakuten.co.jp/")
                    }
                }

                Section("データ") {
                    LabeledContent("スキャン履歴", value: "\(records.count)件")
                    Button("履歴をすべて削除", role: .destructive) {
                        confirmClear = true
                    }
                    .disabled(records.isEmpty)
                }

                Section {
                    LabeledContent("バージョン", value: appVersion)
                } footer: {
                    Text("価格は各サイトのAPIから取得した時点のものです。送料・ポイント・在庫は購入前に各ショップでご確認ください。")
                }
            }
            .navigationTitle("設定")
            .scrollDismissesKeyboard(.interactively)
            .browserSheet($browser)
            .confirmationDialog("履歴をすべて削除しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    for record in records { context.delete(record) }
                    try? context.save()
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }

    private func statusRow(_ source: Offer.Source, ready: Bool) -> some View {
        HStack {
            SourceBadge(source: source, compact: false)
            Spacer()
            Label(ready ? "有効" : "未設定", systemImage: ready ? "checkmark.circle.fill" : "circle.dashed")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ready ? Theme.saving : Color.secondary)
        }
    }

    private func testButton(_ source: Offer.Source, enabled: Bool) -> some View {
        Button {
            testResults[source] = .running
            Task {
                let result = await PriceService.test(source)
                switch result {
                case .success(let count): testResults[source] = .success(count)
                case .failure(let error): testResults[source] = .failure(error.localizedDescription)
                }
            }
        } label: {
            HStack {
                Text("接続テスト")
                Spacer()
                switch testResults[source] {
                case .running:
                    ProgressView()
                case .success:
                    Label("接続OK", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.saving)
                        .font(.subheadline)
                case .failure(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                case nil:
                    EmptyView()
                }
            }
        }
        .disabled(!enabled || testResults[source] == .running)
    }

    private func linkButton(_ title: String, _ url: String) -> some View {
        Button {
            if let url = URL(string: url) { browser = BrowserItem(url: url) }
        } label: {
            Label(title, systemImage: "arrow.up.right.square")
                .font(.footnote.weight(.semibold))
        }
    }
}

/// キー入力欄（目のアイコンで表示切替）
struct KeyField: View {
    let title: String
    @Binding var text: String
    var secure = true
    var placeholder = "未入力"
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Group {
                    if secure && !revealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(secure ? .asciiCapable : .URL)
                if secure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
