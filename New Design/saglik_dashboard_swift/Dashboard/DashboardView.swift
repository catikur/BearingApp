//
//  DashboardView.swift
//  SaglikDashboard
//
//  "Panel" ekranı — tasarım görseli 02 karşılığı.
//  Dört motor kartı tarama sırasına göre ve FARKLI görsel ağırlıkta dizilir:
//  bugün en önemli olan en üstte ve en büyük.
//
//  Tüm sayılar Engines.swift'ten gelir; burada örnek sunum verisi kullanılmıştır.
//

import SwiftUI

struct DashboardView: View {
    private let columns = [
        GridItem(.flexible(), spacing: DS.Space.md),
        GridItem(.flexible(), spacing: DS.Space.md),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.lg) {
                    tdeeCard          // Hero: bugün en önemli motor
                    weightCard
                    HStack(alignment: .top, spacing: DS.Space.md) {
                        baselineCard
                        guardrailCard
                    }

                    SectionHeader(title: "Metrikler", actionTitle: "Düzenle", action: {})
                    metricGrid
                    correlationLink
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xxl)
            }
            .background(DS.Surface.background)
            .navigationTitle("Panel")
            .navigationSubtitle(DS.shortDate(.now))
        }
    }

    // MARK: Ölçülmüş Metabolizma — hero, düşük güven örneği

    private var tdeeCard: some View {
        NavigationLink {
            // TDEEDetailView()
            Text("TDEE Detay")
        } label: {
            EngineCard(icon: "flame", title: "Ölçülmüş Metabolizma") {
                BigStat(
                    value: DS.integer(2410),
                    unit: "kcal",
                    confidence: .low   // ince ağırlık + kesikli alt çizgi
                )
                ConfidenceCaption(confidence: .low, detail: "9 günlük veri")
                SparklineView(values: [2350, 2380, 2360, 2420, 2400, 2440, 2410])
                    .frame(height: 36)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Kilo Yolculuğu — yüksek güven örneği

    private var weightCard: some View {
        NavigationLink {
            // WeightJourneyView()
            Text("Kilo Yolculuğu")
        } label: {
            EngineCard(icon: "scalemass", title: "Kilo Yolculuğu") {
                BigStat(
                    value: DS.decimal(82.4),
                    unit: "kg",
                    caption: "−\(DS.decimal(0.35, fraction: 2)) kg/hafta · hedefe \(DS.percent(64))",
                    confidence: .high
                )
                ThinBar(progress: 0.64)
                // Tahmini tarih bir kestirimdir — düşük güven dilbilgisiyle işaretlenir.
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
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Baseline & Sapma — nötr durum

    private var baselineCard: some View {
        NavigationLink {
            // BaselineView()
            Text("Baseline")
        } label: {
            EngineCard(icon: "waveform.path.ecg", title: "Baseline", badge: {
                StatusChip(text: "nötr")
            }) {
                Text("Tüm metrikler normal aralıkta")
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Text.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                // Metrik durum noktaları: nötr — durum rengi taşımaz.
                HStack(spacing: DS.Space.xs) {
                    ForEach(0..<8, id: \.self) { _ in
                        Circle()
                            .fill(DS.Status.neutral.opacity(0.45))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Guardrail Uyumu — tek "dikkat" durumu

    private var guardrailCard: some View {
        NavigationLink {
            // GuardrailsView()
            Text("Guardrails")
        } label: {
            EngineCard(icon: "checklist", title: "Guardrail") {
                BigStat(value: DS.percent(86), unit: "", confidence: .high)
                ThinBar(progress: 0.86)
                Text("6 kuraldan 5 uyumlu")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
                // Ekrandaki TEK durum rengi: eylem gerektiren ama acil olmayan.
                HStack(spacing: DS.Space.xs) {
                    Circle()
                        .fill(DS.Status.attention)
                        .frame(width: 6, height: 6)
                    Text("Sodyum: dikkat")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Status.attention)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Metrik ızgarası

    private var metricGrid: some View {
        LazyVGrid(columns: columns, spacing: DS.Space.md) {
            MetricCard(name: "HRV", value: DS.integer(48), unit: "ms",
                       sparkline: [44, 47, 43, 50, 46, 52, 48])
            MetricCard(name: "Dinlenik Nabız", value: DS.integer(56), unit: "atım/dk",
                       sparkline: [58, 57, 58, 56, 55, 57, 56])
            MetricCard(name: "Uyku Süresi", value: "7 sa 12 dk", unit: "",
                       sparkline: [6.8, 7.4, 6.9, 7.5, 7.0, 7.3, 7.2])
            MetricCard(name: "Adım", value: DS.integer(8430), unit: "",
                       sparkline: [7200, 9100, 6800, 8800, 7900, 9400, 8430])
        }
    }

    // MARK: Korelasyon keşfi girişi

    private var correlationLink: some View {
        NavigationLink {
            // CorrelationView()
            Text("Korelasyon Keşfi")
        } label: {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "chart.dots.scatter")
                    .foregroundStyle(DS.Surface.accent)
                Text("Korelasyon Keşfi")
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Surface.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
            }
            .frame(minHeight: DS.Touch.minTarget)
            .cardSurface(padding: DS.Space.lg)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Panel — Light") {
    DashboardView()
}

#Preview("Panel — Dark") {
    DashboardView()
        .preferredColorScheme(.dark)
}
