import SwiftUI
import Charts

struct WeightJourneyView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss
    let result: TrendEngine.Result?

    private var raw: [MetricSample] { store.series["weight"] ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.lg) {
                    if let r = result {
                        heroCard(r)
                        chartCard(r)
                        explainerCard(r)
                    } else {
                        EmptyStateView(
                            icon: "scalemass",
                            title: "Kilo verisi yok",
                            guidance: "Tartı verisi Apple Health'e geldikçe trend burada hesaplanacak."
                        )
                        .cardSurface()
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xxl)
            }
            .background(DS.Surface.background)
            .navigationTitle("Kilo Yolculuğu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }

    // MARK: Üst istatistik

    private func heroCard(_ r: TrendEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            BigStat(
                value: DS.decimal(r.smoothedNow),
                unit: "kg",
                caption: "EMA düzleştirilmiş (\(Int(profileStore.settings.emaHalfLifeDays)) gün yarı ömür) · ham: \(DS.decimal(r.rawNow)) kg",
                confidence: .high
            )

            Divider().overlay(DS.Surface.divider)

            HStack(spacing: 0) {
                statColumn(
                    title: "Hız",
                    value: "\(r.ratePerWeek >= 0 ? "+" : "−")\(DS.decimal(abs(r.ratePerWeek), fraction: 2)) kg/hafta",
                    // Hedef yönünde ilerleme sakin yeşil — kutlama değil, onay
                    valueColor: r.onTrack ? DS.Status.positive : DS.Text.primary
                )
                columnDivider
                statColumn(title: "Hedefe",
                           value: r.progressPct.map { DS.percent(Int($0.rounded())) } ?? "—")
                columnDivider
                statColumn(title: "Kalan", value: "\(DS.decimal(abs(r.remainingKg))) kg")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(DS.Surface.divider)
            .frame(width: 0.5, height: DS.Space.xxl)
    }

    private func statColumn(title: String, value: String, valueColor: Color = DS.Text.primary) -> some View {
        VStack(spacing: DS.Space.xs) {
            Text(title)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)
            Text(value)
                .font(DS.Font.numericCaption)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Grafik — ham noktalar + EMA + kesikli projeksiyon + belirsizlik konisi

    private func chartCard(_ r: TrendEngine.Result) -> some View {
        // Projeksiyon ufku: varış tahminine +2 hafta pay, 4–12 hafta arasına sıkıştırılır
        let horizon = min(84, max(28, Int((r.weeksRemaining ?? 6) * 7) + 14))
        let projection = TrendEngine.projection(from: r, horizonDays: horizon)
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            Chart {
                // Hedef çizgisi — kesikli, üçüncül
                RuleMark(y: .value("Hedef", profileStore.profile.targetWeightKg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(DS.Text.tertiary)
                    .annotation(position: .bottomLeading) {
                        Text("Hedef: \(DS.decimal(profileStore.profile.targetWeightKg)) kg")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Text.tertiary)
                    }

                // Ham tartımlar — soluk noktalar
                ForEach(raw) { s in
                    PointMark(x: .value("Tarih", s.date, unit: .day), y: .value("Ham", s.value))
                        .foregroundStyle(DS.Text.tertiary.opacity(0.45))
                        .symbolSize(14)
                }

                // EMA — düz, tam ağırlıklı çizgi (yüksek güven)
                ForEach(r.smoothed) { s in
                    LineMark(x: .value("Tarih", s.date, unit: .day), y: .value("EMA", s.value),
                             series: .value("Seri", "EMA"))
                        .foregroundStyle(DS.Surface.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }

                // Belirsizlik konisi — genişleyen soluk alan
                ForEach(Array(projection.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("Tarih", p.date),
                             yStart: .value("Alt", p.low),
                             yEnd: .value("Üst", p.high))
                        .foregroundStyle(DS.Surface.accent.opacity(0.10))
                }

                // Projeksiyon — kesikli ince çizgi (düşük güven)
                ForEach(Array(projection.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Tarih", p.date), y: .value("Beklenen", p.expected),
                             series: .value("Seri", "Projeksiyon"))
                        .foregroundStyle(DS.Surface.accent.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                }

                // Tahmini varış noktası — içi boş
                if let last = projection.last {
                    PointMark(x: .value("Tarih", last.date), y: .value("Beklenen", last.expected))
                        .symbol {
                            Circle()
                                .strokeBorder(DS.Surface.accent, lineWidth: 2)
                                .frame(width: 10, height: 10)
                                .background(Circle().fill(DS.Surface.card))
                        }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(DS.Surface.divider)
                    AxisValueLabel()
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                }
            }
            .chartXAxis {
                AxisMarks {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(DS.locale))
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                }
            }
            .frame(height: 240)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Kilo grafiği: ham tartımlar, düzleştirilmiş eğri ve projeksiyon")
            .accessibilityValue("Düzleştirilmiş \(DS.decimal(r.smoothedNow)) kilogram, hız haftada \(DS.decimal(abs(r.ratePerWeek), fraction: 2)) kilogram \(r.ratePerWeek < 0 ? "kayıp" : "artış"), hedef \(DS.decimal(profileStore.profile.targetWeightKg)) kilogram")

            // Tahmini varış bir kestirimdir — düşük güven dilbilgisi
            if let e = r.etaDate, let w = r.weeksRemaining {
                HStack(spacing: DS.Space.xs) {
                    Text("Tahmini varış:")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                    ConfidenceText(text: "\(DS.shortDate(e)) (~\(DS.integer(Int(w.rounded()))) hafta)",
                                   confidence: .low,
                                   font: DS.Font.caption,
                                   color: DS.Text.secondary)
                }
            } else {
                Text("Mevcut hızla varış tahmini üretilemiyor (hız çok düşük veya ters yönde).")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
            }

            HStack(spacing: DS.Space.lg) {
                legend(symbol: .dot, label: "Ham tartım")
                legend(symbol: .line, label: "EMA")
                legend(symbol: .dashed, label: "Projeksiyon")
            }
        }
        .cardSurface()
    }

    private enum LegendSymbol { case dot, line, dashed }

    private func legend(symbol: LegendSymbol, label: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            switch symbol {
            case .dot:
                Circle().fill(DS.Text.tertiary.opacity(0.45)).frame(width: 6, height: 6)
            case .line:
                Capsule().fill(DS.Surface.accent).frame(width: 14, height: 2.5)
            case .dashed:
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(DS.Surface.accent.opacity(0.7)).frame(width: 4, height: 1.5)
                    }
                }
            }
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)
        }
    }

    // MARK: Açıklama

    private func explainerCard(_ r: TrendEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Bu ne anlama geliyor?")
                .font(DS.Font.heading)
                .foregroundStyle(DS.Text.primary)
            Text("Günlük tartı tuz, su ve glikojenle oynar; karar için düzleştirilmiş (EMA) değere bak.")
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.secondary)
            Text("Hız, son \(r.rateWindowDays) günün EMA eğiminden hesaplanır. Projeksiyon konisi veri gürültüsünden türeyen belirsizliği gösterir.")
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.secondary)
            infoRow("Hedef hız", "−\(DS.decimal(profileStore.profile.targetRateKgPerWeek, fraction: 2)) kg/hafta")
            infoRow("Başlangıçtan değişim", "\(r.totalChange >= 0 ? "+" : "−")\(DS.decimal(abs(r.totalChange))) kg")
            if !r.onTrack {
                Text("Hedef hızının altındasın — bu kendi başına sorun değil; sürdürülebilirlik hızdan önemli.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func infoRow(_ l: String, _ v: String) -> some View {
        HStack {
            Text(l).font(DS.Font.secondary).foregroundStyle(DS.Text.secondary)
            Spacer()
            Text(v).font(DS.Font.numericCaption).foregroundStyle(DS.Text.primary)
        }
    }
}
