import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Market", systemImage: "chart.xyaxis.line") }
            NavigationStack { AIDecisionView() }
                .tabItem { Label("AI Decision", systemImage: "brain.head.profile") }
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(AppTheme.accent)
        .background(AppTheme.background.ignoresSafeArea())
        .task {
            await store.start()
#if PUSH_NOTIFICATIONS
            if let token = await PushNotificationCoordinator.shared.requestDeviceToken() {
                await store.registerPushDevice(
                    token: token,
                    environment: PushNotificationCoordinator.environment
                )
            }
#endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.start() } }
            else { store.stop() }
        }
        .alert("Seqra Quant", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let notice = store.notice {
                Text(notice)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        store.notice = nil
                    }
            }
        }
    }
}
