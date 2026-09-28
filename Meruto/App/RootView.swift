import SwiftUI

struct RootView: View {
    let monitor: DeviceMonitor
    let meter: WiFiMeter
    let surveys: SurveyStore
    let quota: AgentQuotaStore
    let recorder: SurveyRecorder
    @State private var tab: Tab = .dashboard
    @Environment(\.scenePhase) private var scenePhase

    enum Tab: String {
        case dashboard, wifi, ai, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            screen { DashboardView(monitor: monitor, quotaStore: quota, onOpenWiFi: { tab = .wifi }, onOpenAI: { tab = .ai }) }
                .tabItem { Label("モニター", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(Tab.dashboard)
            screen { WiFiScreen(meter: meter, store: surveys, recorder: recorder) }
                .tabItem { Label("Wi-Fi", systemImage: "wifi") }
                .tag(Tab.wifi)
            screen { AIQuotaScreen(store: quota, onOpenSettings: { tab = .settings }) }
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(Tab.ai)
            SettingsView(quotaStore: quota)
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Theme.cyan)
        .onChange(of: scenePhase, initial: true) { _, phase in
            monitor.setActive(phase == .active)
        }
        .onOpenURL { url in
            // meruto://wifi のようなウィジェットからのリンク。
            if let target = Tab(rawValue: url.host() ?? "") { tab = target }
        }
    }

    private func screen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(InstrumentBackground())
            .toolbarBackground(Theme.background.opacity(0.92), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}
