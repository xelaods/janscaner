import SwiftData
import SwiftUI

@main
struct JanScannerApp: App {
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(CredentialStore.shared)
                .tint(Theme.accent)
        }
        .modelContainer(for: ScanRecord.self)
    }
}

@Observable
final class AppRouter {
    enum Tab: Hashable { case scan, history, settings }
    var tab: Tab = .scan
}

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ScanScreen()
                .tabItem { Label("スキャン", systemImage: "barcode.viewfinder") }
                .tag(AppRouter.Tab.scan)
            HistoryScreen()
                .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
                .tag(AppRouter.Tab.history)
            SettingsScreen()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
    }
}
