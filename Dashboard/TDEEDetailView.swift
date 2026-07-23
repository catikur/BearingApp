import SwiftUI
import Charts

struct TDEEDetailView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss
    let result: TDEEEngine.Result?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    if let r = result {
                        headline(r)
                        method(r)
                        inputs(r)
                        chart
                        recommendation(r)
                    } else {
                        EmptyStateView(
                            icon: "flame",
                            title: "Henüz hesaplanamıyor",
                            guidance: "En az birkaç günlük kalori (Cronometer → Apple Health) ve kilo verisi gerekiyor. Pencere ayarını Ayarlar'dan değiştirebilirsin."
                        )
                        .cardSurface()
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.lg)
            }
            .background(DS.Surface.background)
            .navigationTitle("Ölçülmüş Metabolizma")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }

    private func headline(_ r: TDEEEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // Değer güven dilbilgisiyle: düşük güven → ince + kesikli (DESIGN.md §2).
            BigStat(value: DS.integer(Int(r.tdee.rounded())),
                    unit: "kcal/gün",
                    confidence: r.confidence.designLevel)
            HStack(spacing: DS.Space.xs) {
                StatusChip(text: r.confidence.label,
                           status: r.confidence == .high ? DS.Status.positive : DS.Status.neutral)
                StatusChip(text: "son \(DS.integer(r.windowDays)) gün")
            }
            Text("Bu bir tahmin formülü değil: gerçekte ne yediğin ile kilonun gerçekte nasıl değiştiğinden geriye doğru hesaplandı.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func method(_ r: TDEEEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Nasıl hesaplandı")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Text.primary)
            Text("TDEE = ortalama alım − (kilo değişimi × kcal/kg)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(DS.Text.primary)
                .padding(DS.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Surface.divider.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            Text("\(DS.integer(Int(r.meanIntake.rounded()))) − (\(r.slopeKgPerDay.formatted(.number.precision(.fractionLength(3)).locale(DS.locale))) kg/gün × \(DS.integer(Int(profileStore.settings.kcalPerKg.rounded())))) = \(DS.integer(Int(r.tdee.rounded()))) kcal")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)
                .monospacedDigit()
            Text("Karşılaştırma: Mifflin-St Jeor bazal tahmini \(DS.integer(Int(r.bmrReference.rounded()))) kcal. O bir nüfus formülü; yukarıdaki senin ölçümün.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func inputs(_ r: TDEEEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Girdiler")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Text.primary)
            row("Ortalama alım", "\(DS.integer(Int(r.meanIntake.rounded()))) kcal")
            row("Kilo eğimi", "\((r.slopeKgPerDay * 7).formatted(.number.sign(strategy: .always()).precision(.fractionLength(2)).locale(DS.locale))) kg/hafta")
            row("Loglanan gün", "\(DS.integer(r.intakeDays))/\(DS.integer(r.windowDays)) (\(DS.percent(Int((r.intakeCoverage * 100).rounded()))))")
            row("Kilo ölçümü", "\(DS.integer(r.weightSamples)) gün")
            if r.intakeCoverage < profileStore.settings.tdeeMinIntakeCoverage {
                Label("Loglanmayan günler ortalamayı düşük gösterir ve TDEE'yi olduğundan yüksek çıkarır. Kapsama arttıkça sayı düzelir.",
                      systemImage: "exclamationmark.triangle")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Status.attention)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var chart: some View {
        let intake = Series.window(store.series["calories"] ?? [], days: profileStore.settings.tdeeWindowDays)
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Günlük alım")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Text.primary)
            if intake.isEmpty {
                Text("Kalori verisi yok.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
            } else {
                Chart {
                    ForEach(intake) { s in
                        BarMark(x: .value("Gün", s.date, unit: .day), y: .value("kcal", s.value))
                            .foregroundStyle(DS.Surface.accent.opacity(0.6))
                    }
                    if let r = result {
                        RuleMark(y: .value("TDEE", r.tdee))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(DS.Text.primary)
                            .annotation(position: .top, alignment: .leading) {
                                Text("TDEE")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Text.secondary)
                            }
                    }
                }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func recommendation(_ r: TDEEEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Hedefine göre")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Text.primary)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text("\(DS.integer(Int(r.recommendedIntake.rounded()))) kcal")
                    .font(DS.Font.stat())
                    .foregroundStyle(DS.Surface.accent)
                Spacer()
            }
            Text("\(DS.decimal(profileStore.profile.targetRateKgPerWeek)) kg/hafta hedefi için günlük alım")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)
            Text("Hedef hızını ve kcal/kg katsayısını Ayarlar → Profil ve Motor Parametreleri'nden değiştirebilirsin.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack {
            Text(l)
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.secondary)
            Spacer()
            Text(v)
                .font(DS.Font.secondary.weight(.semibold))
                .foregroundStyle(DS.Text.primary)
                .monospacedDigit()
        }
    }
}
