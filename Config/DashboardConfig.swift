import Foundation
import SwiftUI

/// Kullanıcının dashboard'da görmek istediği metrikleri kalıcı saklar (özelleştirme).
@MainActor
final class DashboardConfig: ObservableObject {
    @Published private(set) var enabledIds: [String]

    /// Geriye dönük veri çekim penceresi (gün) — Whoop + HealthKit'e birlikte uygulanır.
    /// Ayarlar → Veri kaynakları'ndan değiştirilir; dashboard'daki 7/30/90 seçici yalnız görünümü daraltır.
    @Published private(set) var fetchWindowDays: Int

    private let key = "dashboard_enabled_metrics_v1"
    private let fetchKey = "fetch_window_days_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            enabledIds = ids
        } else {
            enabledIds = HealthMetricCatalog.defaultEnabled
        }
        let stored = UserDefaults.standard.integer(forKey: fetchKey)
        fetchWindowDays = stored > 0 ? stored : 90
    }

    func setFetchWindow(_ days: Int) {
        fetchWindowDays = days
        UserDefaults.standard.set(days, forKey: fetchKey)
    }

    var enabledMetrics: [MetricDef] {
        enabledIds.compactMap { HealthMetricCatalog.byId($0) }
    }

    func isEnabled(_ id: String) -> Bool { enabledIds.contains(id) }

    func toggle(_ id: String) {
        if let idx = enabledIds.firstIndex(of: id) { enabledIds.remove(at: idx) }
        else { enabledIds.append(id) }
        persist()
    }

    /// Dashboard'daki sırayı değiştir (sürükle-bırak)
    func move(from source: IndexSet, to destination: Int) {
        enabledIds.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func resetToDefault() {
        enabledIds = HealthMetricCatalog.defaultEnabled
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(enabledIds) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
