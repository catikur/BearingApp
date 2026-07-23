//
//  MetricDetailView.swift
//  SaglikDashboard
//
//  "Metrik Detay" ekranı — tasarım görseli 03 karşılığı.
//  Swift Charts ile: kişisel baseline bandı, az-veri segmenti (kesikli + içi boş
//  noktalar) ve korelasyon kartları. Güven dilbilgisi grafiklerde de geçerli.
//

import SwiftUI
import Charts

// MARK: - Sunum modelleri

struct MetricPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    /// Az veri / düşük güven segmenti mi?
    var isLowConfidence: Bool = false
}

struct CorrelationPair: Identifiable {
    let id = UUID()
    let title: String
    let r: Double
    let n: Int
    var points: [CGPoint] = []

    /// n < 10 → düşük güven (eşik EngineSettings'ten gelir; burada örnek).
    var confidence: ConfidenceLevel { n < 10 ? .low : .high }

    var strengthLabel: String {
        let a = abs(r)
        let strength = a < 0.3 ? "zayıf" : (a < 0.6 ? "orta" : "güçlü")
        let direction = r >= 0 ? "pozitif" : "negatif"
        return "\(strength) \(direction)"
    }
}

// MARK: - MetricDetailView

struct MetricDetailView: View {
    let metricName: String
    @State private var selectedRange = "30G"
    private let ranges = ["7G", "30G", "90G", "1Y"]

    // Örnek veri — gerçekte HealthKitManager + Engines'ten gelir.
    private let points = MetricPoint.sampleHRV
    private let baselineLow = 46.0
    private let baselineHigh = 56.0

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.lg) {
                headerCard
                rangePicker
                chartCard
                SectionHeader(title: "Korelasyon", actionTitle: nil, action: nil)
                correlationCard
                scanButton
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.xxl)
        }
        .background(DS.Surface.background)
        .navigationTitle(metricName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Üst istatistik

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .top) {
                BigStat(value: DS.integer(48), unit: "ms", confidence: .high)
                Spacer()
                // Rutin sapma NÖTR gösterilir — kırmızı değil.
                StatusChip(text: "z-skor: −\(DS.decimal(0.4)) · normal aralık")
            }
            Text("30 günlük ortalama: \(DS.integer(51)) ms")
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var rangePicker: some View {
        Picker("Aralık", selection: $selectedRange) {
            ForEach(ranges, id: \.self) { Text($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Grafik

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Chart {
                // Kişisel baseline bandı — soluk teal alan
                RectangleMark(
                    xStart: .value("Başlangıç", points.first?.date ?? .now),
                    xEnd: .value("Bitiş", points.last?.date ?? .now),
                    yStart: .value("Alt", baselineLow),
                    yEnd: .value("Üst", baselineHigh)
                )
                .foregroundStyle(DS.Surface.accent.opacity(0.10))

                // Yüksek güvenli segment: düz çizgi
                ForEach(points.filter { !$0.isLowConfidence }) { p in
                    LineMark(
                        x: .value("Tarih", p.date),
                        y: .value(metricName, p.value)
                    )
                    .foregroundStyle(DS.Surface.accent)
                    .interpolationMethod(.catmullRom)
                }

                // Az-veri segmenti: kesikli çizgi + içi boş noktalar
                ForEach(points.filter(\.isLowConfidence)) { p in
                    LineMark(
                        x: .value("Tarih", p.date),
                        y: .value(metricName, p.value),
                        series: .value("Seri", "az veri")
                    )
                    .foregroundStyle(DS.Surface.accent.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    PointMark(
                        x: .value("Tarih", p.date),
                        y: .value(metricName, p.value)
                    )
                    .symbol {
                        Circle()
                            .strokeBorder(DS.Surface.accent, lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                            .background(Circle().fill(DS.Surface.card))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) {
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
            .frame(height: 220)

            HStack(spacing: DS.Space.lg) {
                legendItem(color: DS.Surface.accent.opacity(0.10), label: "Kişisel baseline bandı", filled: true)
                legendItem(color: DS.Surface.accent, label: "az veri (kesikli)", filled: false)
            }
        }
        .cardSurface()
    }

    private func legendItem(color: Color, label: String, filled: Bool) -> some View {
        HStack(spacing: DS.Space.xs) {
            if filled {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 10)
            } else {
                Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 10, height: 10)
            }
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)
        }
    }

    // MARK: Korelasyon

    private var correlationCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            CorrelationRow(pair: CorrelationPair(
                title: "HRV ←→ Uyku Süresi", r: 0.42, n: 28,
                points: CorrelationPair.samplePoints
            ), showsScatter: true)

            Divider().overlay(DS.Surface.divider)

            CorrelationRow(pair: CorrelationPair(
                title: "HRV ←→ Alkol", r: -0.38, n: 8
            ), showsScatter: false)
        }
        .cardSurface()
    }

    private var scanButton: some View {
        Button("Tüm korelasyonları tara") {}
            .font(DS.Font.heading)
            .frame(maxWidth: .infinity, minHeight: DS.Touch.minTarget)
            .buttonStyle(.bordered)
            .tint(DS.Surface.accent)
    }
}

// MARK: - Korelasyon satırı

struct CorrelationRow: View {
    let pair: CorrelationPair
    var showsScatter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text(pair.title)
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                ConfidenceText(
                    text: "r = \(rFormatted)",
                    confidence: pair.confidence,
                    font: DS.Font.numericCaption,
                    color: DS.Text.primary
                )
            }

            if showsScatter, !pair.points.isEmpty {
                Chart {
                    ForEach(Array(pair.points.enumerated()), id: \.offset) { _, p in
                        PointMark(x: .value("x", p.x), y: .value("y", p.y))
                            .foregroundStyle(DS.Surface.accent.opacity(0.7))
                            .symbolSize(30)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 90)
            }

            if pair.confidence == .low {
                Text("n < 10 · düşük güven")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
            } else {
                Text("r = \(rFormatted) · \(pair.strengthLabel) · n = \(DS.integer(pair.n)) gün")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
            }
        }
    }

    private var rFormatted: String {
        let sign = pair.r < 0 ? "−" : ""
        return sign + DS.decimal(abs(pair.r), fraction: 2)
    }
}

// MARK: - Örnek veri

extension MetricPoint {
    static let sampleHRV: [MetricPoint] = {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: -29, to: .now)!
        let values: [Double] = [
            50, 52, 49, 47, 51, 53, 50, 48, 46, 49,
            52, 54, 51, 49, 47, 50, 53, 51, 48, 50,
            52, 49, 47, 45, 48, 50, 47,
            // Son 3 gün: az veri
            46, 48, 48,
        ]
        return values.enumerated().map { i, v in
            MetricPoint(
                date: cal.date(byAdding: .day, value: i, to: base)!,
                value: v,
                isLowConfidence: i >= values.count - 3
            )
        }
    }()
}

extension CorrelationPair {
    static let samplePoints: [CGPoint] = [
        .init(x: 6.2, y: 42), .init(x: 6.5, y: 44), .init(x: 6.8, y: 43),
        .init(x: 7.0, y: 47), .init(x: 7.1, y: 46), .init(x: 7.3, y: 49),
        .init(x: 7.5, y: 50), .init(x: 7.6, y: 48), .init(x: 7.8, y: 52),
        .init(x: 8.0, y: 51), .init(x: 8.2, y: 54), .init(x: 6.9, y: 45),
        .init(x: 7.2, y: 50), .init(x: 7.4, y: 47), .init(x: 7.7, y: 53),
    ]
}

// MARK: - Previews

#Preview("Metrik Detay — Light") {
    NavigationStack {
        MetricDetailView(metricName: "HRV")
    }
}

#Preview("Metrik Detay — Dark") {
    NavigationStack {
        MetricDetailView(metricName: "HRV")
    }
    .preferredColorScheme(.dark)
}
