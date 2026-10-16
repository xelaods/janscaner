import AVFoundation
import SwiftData
import SwiftUI

struct ScanScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(CredentialStore.self) private var credentials
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ScanRecord.scannedAt, order: .reverse) private var records: [ScanRecord]

    @State private var path: [String] = []
    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var showManualEntry = false
    @State private var torchOn = false
    @State private var successTick = 0
    @State private var errorTick = 0
    @State private var toast: String?
    @State private var flash = false

    private var isScanning: Bool {
        path.isEmpty && router.tab == .scan && !showManualEntry
            && authorization == .authorized && scenePhase == .active
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()
                cameraLayer
                overlay
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { jan in
                ResultView(jan: jan)
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.error, trigger: errorTick)
        .sheet(isPresented: $showManualEntry) {
            ManualEntrySheet { jan in
                showManualEntry = false
                open(jan)
            }
            .presentationDetents([.height(320)])
            .presentationCornerRadius(28)
        }
        .task { await requestCameraIfNeeded() }
        .onChange(of: isScanning) { _, scanning in
            if !scanning { setTorch(false) }
        }
    }

    // MARK: - カメラ

    @ViewBuilder
    private var cameraLayer: some View {
        switch authorization {
        case .authorized:
            if BarcodeScannerView.isSupported {
                BarcodeScannerView(isActive: isScanning) { code in
                    handle(code)
                }
                .ignoresSafeArea()
            } else {
                unavailableView(
                    icon: "camera.metering.unknown",
                    title: "この端末ではスキャンできません",
                    message: "下の「番号を入力」からJANコードを入力して検索できます。"
                )
            }
        case .notDetermined:
            Color.black
        default:
            unavailableView(
                icon: "camera.fill",
                title: "カメラへのアクセスが必要です",
                message: "バーコードを読み取るために、設定アプリでカメラを許可してください。",
                action: ("設定を開く", {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })
            )
        }
    }

    private func unavailableView(icon: String, title: String, message: String,
                                 action: (String, () -> Void)? = nil) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(40)
    }

    // MARK: - 重ねる表示

    private var overlay: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            ScanReticle(isScanning: isScanning, flash: flash)
                .frame(width: 290, height: 170)
            Text(toast ?? "バーコードを枠に合わせてください")
                .font(.footnote.weight(.medium))
                .foregroundStyle(toast == nil ? Color.white.opacity(0.85) : Color.yellow)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .padding(.top, 22)
                .animation(.snappy, value: toast)
            Spacer(minLength: 0)
            bottomPanel
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("最安スキャン")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                Text(sourceSummary)
                    .font(.caption.weight(.medium))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            Spacer()
            if authorization == .authorized && BarcodeScannerView.isSupported {
                Button {
                    setTorch(!torchOn)
                } label: {
                    Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(torchOn ? Color.black : Color.white)
                        .frame(width: 44, height: 44)
                        .background(torchOn ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
                }
                .environment(\.colorScheme, .dark)
                .accessibilityLabel("ライト")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 30)
        .background(
            LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var sourceSummary: String {
        let sources = credentials.readySources
        if sources.isEmpty { return "検索先が未設定です" }
        return sources.map(\.shortLabel).joined(separator: "・") + " から最安値を探します"
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            if !credentials.hasAnySource {
                Button {
                    router.tab = .settings
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 36, height: 36)
                            .background(Theme.accent.opacity(0.18), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("まずはAPIキーを設定")
                                .font(.subheadline.weight(.semibold))
                            Text("Yahoo!・楽天のキーで価格を取得します")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .environment(\.colorScheme, .dark)
            }

            if !records.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(records.prefix(8)) { record in
                            Button {
                                open(record.jan)
                            } label: {
                                RecentChip(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollClipDisabled()
            }

            Button {
                showManualEntry = true
            } label: {
                Label("番号を入力", systemImage: "keyboard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .environment(\.colorScheme, .dark)
        }
        .padding(.bottom, 18)
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - 動作

    private func handle(_ code: String) {
        guard path.isEmpty else { return }
        guard let jan = JAN.normalize(code) else {
            errorTick += 1
            showToast("JANコードとして読み取れませんでした")
            return
        }
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            flash = false
            open(jan)
        }
        successTick += 1
    }

    private func open(_ jan: String) {
        guard path.isEmpty else { return }
        path.append(jan)
    }

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toast == text { toast = nil }
        }
    }

    private func requestCameraIfNeeded() async {
        if authorization == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            torchOn = false
            return
        }
        guard (device.torchMode == .on) != on else {
            torchOn = on
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
    }
}

// MARK: - 枠

struct ScanReticle: View {
    var isScanning: Bool
    var flash: Bool
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(flash ? Theme.accent.opacity(0.25) : Color.clear)

                CornerBrackets(length: 30, radius: 22)
                    .stroke(flash ? Theme.accent : .white,
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.35), radius: 6)

                if isScanning && !flash {
                    Rectangle()
                        .fill(
                            LinearGradient(colors: [Theme.accent.opacity(0), Theme.accent, Theme.accent.opacity(0)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(height: 2)
                        .shadow(color: Theme.accent.opacity(0.9), radius: 6)
                        .padding(.horizontal, 18)
                        .offset(y: sweep ? proxy.size.height / 2 - 18 : -proxy.size.height / 2 + 18)
                        .onAppear {
                            sweep = false
                            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                                sweep = true
                            }
                        }
                }
            }
        }
        .scaleEffect(flash ? 0.96 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: flash)
        .allowsHitTesting(false)
    }
}

/// 四隅だけの枠線
struct CornerBrackets: Shape {
    var length: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, length)
        // 左上
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        // 右上
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        // 右下
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        // 左下
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

/// 最近スキャンした商品
struct RecentChip: View {
    let record: ScanRecord

    var body: some View {
        HStack(spacing: 8) {
            ProductThumbnail(url: record.imageURL, size: 34, corner: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
                Text(record.lowestPrice?.yen ?? "—")
                    .font(.price(13))
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - 手入力

struct ManualEntrySheet: View {
    var onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var normalized: String? { JAN.normalize(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("JANコードを入力")
                .font(.title3.weight(.bold))
            Text("バーコードの下にある8桁または13桁の数字です。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "barcode")
                    .foregroundStyle(.secondary)
                TextField("4901234567894", text: $text)
                    .keyboardType(.numberPad)
                    .font(.price(22, weight: .semibold))
                    .focused($focused)
                    .onChange(of: text) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(13))
                        if digits != value { text = digits }
                    }
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                if !text.isEmpty && normalized == nil && (text.count == 8 || text.count >= 12) {
                    Label("チェックディジットが一致しません", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text("\(text.count)桁")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                if let normalized { onSubmit(normalized) }
            } label: {
                Text("最安値を探す")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .disabled(normalized == nil)
        }
        .padding(24)
        .onAppear { focused = true }
    }
}
