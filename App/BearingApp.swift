import SwiftUI
import UserNotifications

@main
struct BearingApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var config = DashboardConfig()
    @StateObject private var labels = LabelStore()
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var planStore = PlanStore()
    @StateObject private var notifier = NotificationManager.shared
    @StateObject private var aiConfig = AIConfig()
    @StateObject private var aiMemory = AIMemory()
    @StateObject private var aiClient = OpenRouterClient()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(config)
                .environmentObject(labels)
                .environmentObject(profileStore)
                .environmentObject(planStore)
                .environmentObject(notifier)
                .environmentObject(aiConfig)
                .environmentObject(aiMemory)
                .environmentObject(aiClient)
                .onAppear {
                    // Bildirim aksiyonları → plan kaydı (uygulama kapalıyken de gelir)
                    NotificationDelegate.shared.onAction = { key, action in
                        Task { @MainActor in planStore.applyNotificationAction(occurrenceKey: key, actionId: action) }
                    }
                    NotificationDelegate.shared.onSnooze = { key, title, body in
                        Task { await NotificationManager.shared.snooze(occurrenceKey: key, title: title, body: body) }
                    }
                }
        }
    }
}

/// HealthKit + Whoop verilerini birleştiren merkezi depo.
@MainActor
final class DataStore: ObservableObject {
    let health = HealthKitManager()
    let whoop = WhoopStore()

    @Published var series: [String: [MetricSample]] = [:]   // metrik id -> günlük değerler
    @Published var loading = false
    @Published var lastUpdated: Date?

    /// Tüm etkin metrikleri (veya hepsini) çek
    func refresh(days: Int = 30, ids: [String]) async {
        loading = true
        defer { loading = false }

        // HealthKit
        if !health.authorized { await health.requestAuthorization() }
        for def in HealthMetricCatalog.all where def.source == .healthKit {
            guard ids.contains(def.id) else { continue }
            series[def.id] = await health.fetch(def, days: days)
        }

        // Whoop (bağlıysa)
        if WhoopAuth.shared.isConnected {
            let whoopSeries = await whoop.fetchAll(days: days)
            for (k, v) in whoopSeries { series[k] = v }
        }

        lastUpdated = Date()
    }

    /// Tek bir metriği talep üzerine yükle (korelasyon explorer'da seçilen metrik etkin değilse)
    func ensureLoaded(_ id: String, days: Int) async {
        if let s = series[id], !s.isEmpty { return }
        guard let def = HealthMetricCatalog.byId(id) else { return }
        guard def.source == .healthKit else { return }   // Whoop serileri toplu geliyor
        if !health.authorized { await health.requestAuthorization() }
        series[id] = await health.fetch(def, days: days)
    }

    /// Otomatik keşif için tüm HealthKit metriklerini çek (yavaş — kullanıcı tetikler)
    func loadAllHealthKit(days: Int) async {
        loading = true
        defer { loading = false }
        if !health.authorized { await health.requestAuthorization() }
        for def in HealthMetricCatalog.all where def.source == .healthKit {
            if let s = series[def.id], !s.isEmpty { continue }
            series[def.id] = await health.fetch(def, days: days)
        }
        lastUpdated = Date()
    }

    // Kartlar/içgörüler için yardımcılar
    func latest(_ id: String) -> Double? { series[id]?.last?.value }
    func average(_ id: String, lastN: Int = 7) -> Double? {
        guard let s = series[id], !s.isEmpty else { return nil }
        let slice = s.suffix(lastN); guard !slice.isEmpty else { return nil }
        return slice.map { $0.value }.reduce(0, +) / Double(slice.count)
    }
    func minMax(_ id: String) -> (Double, Double)? {
        guard let s = series[id], !s.isEmpty else { return nil }
        let vals = s.map { $0.value }
        return (vals.min()!, vals.max()!)
    }
}
