import SwiftUI

struct RootView: View {
    @EnvironmentObject var plan: PlanStore
    @EnvironmentObject var notifier: NotificationManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Tab bar camını iOS 26 sistemi çizer; içerik kartlarına cam uygulanmaz (DESIGN.md).
        TabView {
            TodayView()
                .tabItem { Label("Bugün", systemImage: "sun.max") }
            DashboardView()
                .tabItem { Label("Panel", systemImage: "chart.xyaxis.line") }
        }
        .tint(DS.Surface.accent)
        .task { await bootstrap() }
        .onChange(of: plan.scheduleDirty) { _, _ in
            Task { await scheduleNotifications() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Uygulama öne geldiğinde yuvarlanan pencereyi yeniden doldur
            if phase == .active { Task { await scheduleNotifications() } }
        }
    }

    private func bootstrap() async {
        notifier.registerCategories()
        await notifier.refreshStatus()
        if !notifier.authorized && plan.notifSettings.enabled {
            await notifier.requestAuthorization()
        }
        await scheduleNotifications()
    }

    private func scheduleNotifications() async {
        await notifier.reschedule(items: plan.items,
                                  settings: plan.notifSettings,
                                  unlockedPhase: plan.unlockedPhase,
                                  phaseEnabled: plan.phaseSettings.enabled)
    }
}
