//
//  WeightJourneyView.swift
//  SaglikDashboard
//
//  "Kilo Yolculuğu" ekranı — tasarım görseli 04 karşılığı.
//  Ham tartım noktaları + EMA çizgisi + kesikli projeksiyon ve belirsizlik konisi.
//  Tahmini varış tarihi düşük güven dilbilgisiyle işaretlenir.
//

import SwiftUI
import Charts

// MARK: - Sunum modelleri

struct WeightSample: Identifiable {
    let id = UUID()
    let date: Date
    let raw: Double?
    let ema: Double?
}

struct WeightProjection: Identifiable {
    let id = UUID()
    let date: Date
    let expected: Double
    let low: Double
    let high: Double
}

// MARK: - WeightJourneyView

struct WeightJourneyView: View {
    // Bu değerler Engines.swift'ten gelir — örnek sunum verisi.
    private let currentEMA = 82.4
    private let currentRaw = 82.7
    private let paceKgPerWeek = -0.35
    private let progressPercent = 64
    private let remainingKg = 2.1
    private let goalKg = 80.3
    private let samples = WeightSample.sample
    private let projection = WeightProjection.sample

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.lg) {
                heroCard
                chartCard
                explainerCard
                parametersLink
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.xxl)
        }
        .background(DS.Surface.background)
        .navigationTitle("Kilo Yolculuğu")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Üst istatistik

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            BigStat(
                value: DS.decimal(currentEMA),
                unit: "kg",
                caption: "EMA düzleştirilmiş · ham: \(DS.decimal(currentRaw)) kg",
                confidence: .high
            )

            Divider().overlay(DS.Surface.divider)

            HStack(spacing: 0) {
                statColumn(
                    title: "Hız",
                    value: "\(DS.decimal(paceKgPerWeek, fraction: 2)) kg/hafta",
                    // Onay, kutlama değil: hedef yönünde ilerleme sakin yeşille.
                    valueColor: DS.Status.positive
                )
                divider
                statColumn(title: "Hedefe", value: DS.percent(progressPercent))
                divider
                statColumn(title: "Kalan", value: "\(DS.decimal(remainingKg)) kg")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var divider: some View {
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

    // MARK: Grafik

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Chart {
                // Hedef çizgisi — kesikli, üçüncül
                RuleMark(y: .value("Hedef", goalKg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(DS.Text.tertiary)
                    .annotation(position: .bottomLeading) {
                        Text("Hedef: \(DS.decimal(goalKg)) kg")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Text.tertiary)
                    }

                // Ham tartımlar — soluk noktalar
                ForEach(samples.filter { $0.raw != nil }) { s in
                    PointMark(
                        x: .value("Tarih", s.date),
                        y: .value("Ham", s.raw!)
                    )
                    .foregroundStyle(DS.Text.tertiary.opacity(0.45))
                    .symbolSize(14)
                }

                // EMA — düz, tam ağırlıklı çizgi (yüksek güven)
                ForEach(samples.filter { $0.ema != nil }) { s in
                    LineMark(
                        x: .value("Tarih", s.date),
                        y: .value("EMA", s.ema!),
                        series: .value("Seri", "EMA")
                    )
                    .foregroundStyle(DS.Surface.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Belirsizlik konisi
                ForEach(projection) { p in
                    AreaMark(
                        x: .value("Tarih", p.date),
                        yStart: .value("Alt", p.low),
                        yEnd: .value("Üst", p.high)
                    )
                    .foregroundStyle(DS.Surface.accent.opacity(0.10))
                }

                // Projeksiyon — kesikli ince çizgi (düşük güven)
                ForEach(projection) { p in
                    LineMark(
                        x: .value("Tarih", p.date),
                        y: .value("Beklenen", p.expected),
                        series: .value("Seri", "Projeksiyon")
                    )
                    .foregroundStyle(DS.Surface.accent.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                }

                // Tahmini varış noktası — içi boş
                if let last = projection.last {
                    PointMark(
                        x: .value("Tarih", last.date),
                        y: .value("Beklenen", last.expected)
                    )
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
                AxisMarks(values: .stride(by: .month)) {
                    AxisValueLabel(format: .dateTime.month(.wide).locale(DS.locale))
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                }
            }
            .frame(height: 240)

            // Tahmini varış — kestirim olduğu için kesikli/ince dilbilgisi.
            HStack(spacing: DS.Space.xs) {
                Text("Tahmini varış:")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
                ConfidenceText(
                    text: "12 Eylül",
                    confidence: .low,
                    font: DS.Font.caption,
                    color: DS.Text.secondary
                )
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

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Bu ne anlama geliyor?")
                .font(DS.Font.heading)
                .foregroundStyle(DS.Text.primary)
            Text("Hız, son 21 günün eğiliminden hesaplanır.")
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.secondary)
            Text("Projeksiyon bandı, veri belirsizliğini gösterir.")
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var parametersLink: some View {
        NavigationLink {
            // SettingsView() → motor parametreleri
            Text("Motor parametreleri")
        } label: {
            HStack {
                Text("Motor parametreleri")
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Surface.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
            }
            .frame(minHeight: DS.Touch.minTarget)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Örnek veri

extension WeightSample {
    static let sample: [WeightSample] = {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: -89, to: .now)!
        var result: [WeightSample] = []
        var ema = 83.6
        for i in 0..<90 {
            let date = cal.date(byAdding: .day, value: i, to: base)!
            let trend = 83.6 - Double(i) * 0.0135
            let noise = Double.random(in: -0.4...0.4)
            let raw: Double? = i % 2 == 0 ? trend + noise : nil
            if let r = raw { ema = ema * 0.85 + r * 0.15 }
            result.append(WeightSample(date: date, raw: raw, ema: ema))
        }
        return result
    }()
}

extension WeightProjection {
    static let sample: [WeightProjection] = {
        let cal = Calendar.current
        var result: [WeightProjection] = []
        let start = 82.4
        for i in 0..<50 {
            let date = cal.date(byAdding: .day, value: i, to: .now)!
            let expected = start - Double(i) * 0.05
            let spread = 0.1 + Double(i) * 0.014   // koni genişler
            result.append(WeightProjection(
                date: date, expected: expected,
                low: expected - spread, high: expected + spread
            ))
        }
        return result
    }()
}

// MARK: - Previews

#Preview("Kilo Yolculuğu — Light") {
    NavigationStack { WeightJourneyView() }
}

#Preview("Kilo Yolculuğu — Dark") {
    NavigationStack { WeightJourneyView() }
        .preferredColorScheme(.dark)
}
