//
//  RootView.swift
//  SaglikDashboard
//
//  Kök gezinme — tasarım görseli 07'deki ekran haritası karşılığı.
//  İki sekme: Bugün (varsayılan açılış) ve Panel.
//  Tab bar iOS 26'da sistem tarafından Liquid Glass ile çizilir —
//  içerik kartlarına cam uygulanmaz, yalnızca bu işlevsel katmana.
//

import SwiftUI

struct RootView: View {
    @State private var selectedTab: Tab = .today

    enum Tab: Hashable {
        case today
        case dashboard
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Bugün", systemImage: "sun.max", value: Tab.today) {
                TodayView()
            }
            Tab("Panel", systemImage: "chart.xyaxis.line", value: Tab.dashboard) {
                DashboardView()
            }
        }
        .tint(DS.Surface.accent)
    }
}

// MARK: - App giriş noktası (örnek)

/*
@main
struct SaglikDashboardApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
*/

// MARK: - Previews

#Preview("Kök — Light") {
    RootView()
}

#Preview("Kök — Dark") {
    RootView()
        .preferredColorScheme(.dark)
}
