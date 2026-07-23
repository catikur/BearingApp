import SwiftUI

// EngineCard / BigStat / ThinBar tanımları Shared/DesignComponents.swift'e taşındı.
// Bu dosya yalnızca dört motorun kart GÖVDELERİNİ içerir — sayılar motorlardan gelir,
// görsel dil DESIGN.md'deki güven dilbilgisine uyar.

// MARK: - Kart içerikleri

struct TDEECardBody: View {
    let r: TDEEEngine.Result?
    var body: some View {
        if let r {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                BigStat(value: DS.integer(Int(r.tdee.rounded())), unit: "kcal/gün",
                        caption: "alım \(DS.integer(Int(r.meanIntake.rounded()))) · açık \(DS.integer(Int(r.currentDeficit.rounded()))) kcal",
                        confidence: r.confidence.designLevel)
                ConfidenceCaption(confidence: r.confidence.designLevel,
                                  detail: "\(r.intakeDays)/\(r.windowDays) gün loglanmış")
                Text("Hedef hız için öneri: \(DS.integer(Int(r.recommendedIntake.rounded()))) kcal")
                    .font(DS.Font.caption).foregroundStyle(DS.Surface.accent)
            }
        } else {
            Text("Kalori ve kilo verisi biriktikçe hesaplanacak.")
                .font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
        }
    }
}

struct WeightCardBody: View {
    let r: TrendEngine.Result?
    let target: Double
    var body: some View {
        if let r {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                BigStat(value: DS.decimal(r.smoothedNow), unit: "kg",
                        caption: "\(r.ratePerWeek >= 0 ? "+" : "−")\(DS.decimal(abs(r.ratePerWeek), fraction: 2)) kg/hafta · hedefe \(DS.decimal(abs(r.remainingKg))) kg",
                        confidence: .high)
                if let p = r.progressPct {
                    ThinBar(progress: p / 100)
                    HStack(spacing: DS.Space.xs) {
                        Text("\(DS.percent(Int(p.rounded()))) tamamlandı")
                            .font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
                        Spacer()
                        if let e = r.etaDate {
                            // Tahmini varış bir kestirimdir — düşük güven dilbilgisi
                            Text("Tahmini varış:")
                                .font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
                            ConfidenceText(text: DS.shortDate(e), confidence: .low,
                                           font: DS.Font.caption, color: DS.Text.secondary)
                        }
                    }
                }
            }
        } else {
            Text("Kilo verisi bekleniyor.")
                .font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
        }
    }
}

struct BaselineCardBody: View {
    let devs: [BaselineEngine.Deviation]
    let composite: BaselineEngine.Composite
    var body: some View {
        let bad = devs.filter { $0.concerning }
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if composite.triggered {
                // Kritik renk İZİNLİ bağlam: bileşik sapma sinyali (DESIGN.md kuralı)
                Text("\(composite.firing.count) metrik birlikte sapmış")
                    .font(DS.Font.secondary.weight(.semibold))
                    .foregroundStyle(DS.Status.critical)
                StatusChip(text: "bileşik sinyal", status: DS.Status.critical)
            } else if bad.isEmpty {
                Text("Tüm metrikler normal aralıkta")
                    .font(DS.Font.secondary).foregroundStyle(DS.Text.secondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            } else {
                let worst = bad[0]
                Text("\(bad.count) sapma")
                    .font(DS.Font.secondary.weight(.semibold)).foregroundStyle(DS.Text.primary)
                // Rutin sapma NÖTR gösterilir — kırmızı değil
                StatusChip(text: "\(HealthMetricCatalog.byId(worst.metricId)?.title ?? worst.metricId) · z=\(DS.decimal(worst.z))")
            }
            // Metrik durum noktaları: sapan taraf vurgusuz, sadece sayım hissi verir
            HStack(spacing: DS.Space.xs) {
                ForEach(Array(devs.prefix(8).enumerated()), id: \.offset) { _, d in
                    Circle()
                        .fill(d.concerning ? DS.Status.neutral : DS.Status.neutral.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}

struct GuardrailCardBody: View {
    let summary: GuardrailEngine.Summary
    let goodScore: Double
    var body: some View {
        let worst = summary.results.filter { $0.hasData }.min { $0.compliancePct < $1.compliancePct }
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            BigStat(value: DS.percent(Int(summary.score.rounded())), unit: "",
                    caption: summary.rulesWithData > 0
                        ? "\(summary.rulesWithData) kural · son \(summary.windowDays) gün"
                        : "Kurallar için veri bekleniyor",
                    confidence: summary.rulesWithData > 0 ? .high : .low)
            if summary.rulesWithData > 0 {
                // Rutin ilerleme teal kalır — skora göre kırmızıya DÖNMEZ (DESIGN.md)
                ThinBar(progress: summary.score / 100)
                if let w = worst, w.compliancePct < goodScore {
                    // Eylem gerektiren ama acil olmayan: ekrandaki tek durum rengi adayı
                    HStack(spacing: DS.Space.xs) {
                        Circle().fill(DS.Status.attention).frame(width: 6, height: 6)
                        Text("\(w.rule.name): dikkat (%\(DS.integer(Int(w.compliancePct.rounded()))))")
                            .font(DS.Font.caption).foregroundStyle(DS.Status.attention)
                    }
                }
            }
        }
    }
}
