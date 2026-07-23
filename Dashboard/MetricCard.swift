import SwiftUI

// Saf sunum bileşeni MetricCard, Shared/DesignComponents.swift'te.
// Buradaki MetricGridCard, DataStore'daki gerçek seriyi o bileşene bağlar.

/// Izgara kartı: katalog tanımından değer + mini eğri üretir.
///
/// Kümülatif metriklerde (kalori, protein… `.sum`) büyük sayı BUGÜNÜN toplamıdır ve
/// renk aynı bugünkü değerin çözümlenmiş hedefe göre durumundan gelir (yön dahil) —
/// sayı ile renk artık aynı zaman aralığından. 7 günlük ortalama ikincil satırda kalır.
/// Kümülatif olmayan metriklerde (nabız, HRV, kilo…) "bugünün toplamı" anlamsız
/// olduğundan mevcut nötr davranış korunur (son ölçüm, durum rengi yok).
struct MetricGridCard: View {
    @EnvironmentObject var store: DataStore
    let def: MetricDef
    let days: Int
    /// Parent (DashboardView) TargetEngine ile bir kez çözer, karta geçirir.
    var target: TargetEngine.ResolvedTarget? = nil

    var body: some View {
        let spark = Series.window(store.series[def.id] ?? [], days: min(days, 30)).map { $0.value }
        let sparkline = spark.count > 1 ? spark : []

        if def.aggregation == .sum {
            let dp = ProgressEngine.compute(metricId: def.id,
                                            series: store.series[def.id] ?? [],
                                            target: target,
                                            aggregation: .sum)
            let avg7 = store.average(def.id, lastN: 7)
            MetricCard(name: def.title,
                       value: format(dp.today),
                       unit: def.unit,
                       sparkline: sparkline,
                       valueColor: color(for: dp.state),
                       secondary: avg7.map { "7g ort \(format($0)) \(def.unit)" })
        } else {
            let latest = store.latest(def.id)
            MetricCard(name: def.title,
                       value: latest.map { format($0) } ?? "—",
                       unit: def.unit,
                       sparkline: sparkline)
        }
    }

    /// Renk yalnızca bir TAVAN aşıldığında (overTarget) görünür — turuncu/dikkat.
    /// "Henüz hedefe ulaşılmadı" (atLeast, gün ortası) bir sorun değildir; nötr kalır,
    /// yoksa çoğu beslenme kartı gün boyu yanlış alarm verirdi. Kırmızı YOK (DESIGN.md).
    private func color(for state: ProgressState) -> Color {
        state == .overTarget ? DS.Status.attention : DS.Text.primary
    }

    private func format(_ v: Double) -> String {
        switch def.aggregation {
        case .sum where def.unit == "kcal" || def.unit == "adım" || def.unit == "mg" || def.unit == "µg":
            return DS.integer(Int(v.rounded()))
        case .sum: return v < 10 ? DS.decimal(v) : DS.integer(Int(v.rounded()))
        default: return v < 10 ? DS.decimal(v) : DS.integer(Int(v.rounded()))
        }
    }
}

/// İçgörü kartı: başlık rengi kimlik taşır, kabuk sakin kart yüzeyidir.
struct InsightCard<Content: View>: View {
    let color: Color
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title).font(DS.Font.caption.weight(.semibold)).foregroundStyle(color)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: DS.Space.lg)
    }
}
