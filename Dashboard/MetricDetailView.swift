import SwiftUI
import Charts

struct MetricDetailView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var labels: LabelStore
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss
    let def: MetricDef
    let days: Int

    /// Grafikte işaretlenecek etiketli gün noktası
    private struct TaggedPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let color: Color
        let emoji: String
    }

    private var series: [MetricSample] { store.series[def.id] ?? [] }
    private var windowed: [MetricSample] { Series.window(series, days: days) }

    /// Kişisel baseline — sayılar BaselineEngine'den gelir, burada hesap yapılmaz
    private var baseline: BaselineEngine.Deviation? {
        BaselineEngine.deviation(for: def.id, series: series, settings: profileStore.settings)
    }

    private var taggedPoints: [TaggedPoint] {
        let labeled = labels.labeledDays()
        let cal = Calendar.current
        return windowed.compactMap { s in
            let day = cal.startOfDay(for: s.date)
            guard let tags = labeled[day], let first = tags.first, let tag = TagCatalog.tag(first) else { return nil }
            return TaggedPoint(date: s.date, value: s.value, color: tag.color, emoji: tag.emoji)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    if windowed.isEmpty {
                        EmptyStateView(
                            icon: "chart.line.downtrend.xyaxis",
                            title: "Veri yok",
                            guidance: "\(def.source.rawValue) → Apple Health bağlantısını kontrol et."
                        )
                        .cardSurface()
                    } else {
                        headerCard
                        chartCard
                        statsCard
                        tagImpactSection
                        Text("Kaynak: \(def.source.rawValue) · Son \(days) gün")
                            .font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xxl)
            }
            .background(DS.Surface.background)
            .navigationTitle(def.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }

    // MARK: Üst istatistik

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .top) {
                BigStat(value: windowed.last.map { format($0.value) } ?? "—",
                        unit: def.unit,
                        confidence: .high)
                Spacer()
                // Rutin sapma NÖTR gösterilir — kırmızı yok (DESIGN.md)
                if let b = baseline {
                    StatusChip(text: "z: \(b.z < 0 ? "−" : "")\(DS.decimal(abs(b.z))) · \(abs(b.z) >= profileStore.settings.baselineZThreshold ? "baseline dışı" : "normal aralık")")
                }
            }
            if let t = def.target {
                Text("Hedef: \(format(t)) \(def.unit) (\(def.higherIsBetter ? "yüksek iyi" : "düşük iyi"))")
                    .font(DS.Font.secondary).foregroundStyle(DS.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: Grafik — kişisel baseline bandı + etiketli gün işaretçileri

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Chart {
                // Kişisel baseline bandı — soluk teal alan (mean ± z eşiği × SD)
                if let b = baseline, let first = windowed.first?.date, let last = windowed.last?.date {
                    RectangleMark(
                        xStart: .value("Başlangıç", first),
                        xEnd: .value("Bitiş", last),
                        yStart: .value("Alt", b.mean - b.sd * profileStore.settings.baselineZThreshold),
                        yEnd: .value("Üst", b.mean + b.sd * profileStore.settings.baselineZThreshold)
                    )
                    .foregroundStyle(DS.Surface.accent.opacity(0.10))
                }

                ForEach(windowed) { s in
                    LineMark(x: .value("Gün", s.date, unit: .day), y: .value(def.title, s.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(DS.Surface.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                if let t = def.target {
                    RuleMark(y: .value("Hedef", t))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(DS.Text.tertiary)
                }

                ForEach(taggedPoints) { tp in
                    PointMark(x: .value("Gün", tp.date, unit: .day), y: .value(def.title, tp.value))
                        .foregroundStyle(tp.color)
                        .symbolSize(140)
                        .annotation(position: .top, spacing: 1) { Text(tp.emoji).font(.caption2) }
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
                if baseline != nil {
                    HStack(spacing: DS.Space.xs) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.Surface.accent.opacity(0.10))
                            .frame(width: 14, height: 10)
                        Text("Kişisel baseline bandı")
                            .font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
                    }
                }
                if def.target != nil {
                    HStack(spacing: DS.Space.xs) {
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule().fill(DS.Text.tertiary).frame(width: 4, height: 1.5)
                            }
                        }
                        Text("Hedef").font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
                    }
                }
            }

            let present = presentTags()
            if !present.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.md) {
                        ForEach(present) { tag in
                            HStack(spacing: DS.Space.xs) {
                                Circle().fill(tag.color).frame(width: 8, height: 8)
                                Text("\(tag.emoji) \(tag.title)")
                                    .font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
                            }
                        }
                    }
                }
            }
        }
        .cardSurface()
    }

    private func presentTags() -> [DayTag] {
        let cal = Calendar.current
        let labeled = labels.labeledDays()
        var ids = Set<String>()
        for s in windowed {
            if let tags = labeled[cal.startOfDay(for: s.date)] { tags.forEach { ids.insert($0) } }
        }
        return TagCatalog.all.filter { ids.contains($0.id) }
    }

    // MARK: İstatistikler

    private var statsCard: some View {
        let vals = windowed.map { $0.value }
        let avg = vals.reduce(0, +) / Double(max(vals.count, 1))
        return HStack(spacing: 0) {
            statColumn("Son", windowed.last.map { format($0.value) } ?? "—")
            columnDivider
            statColumn("Ortalama", format(avg))
            columnDivider
            statColumn("Min", vals.min().map(format) ?? "—")
            columnDivider
            statColumn("Max", vals.max().map(format) ?? "—")
        }
        .cardSurface(padding: DS.Space.md)
    }

    private var columnDivider: some View {
        Rectangle().fill(DS.Surface.divider).frame(width: 0.5, height: DS.Space.xl)
    }

    private func statColumn(_ l: String, _ v: String) -> some View {
        VStack(spacing: DS.Space.xs) {
            Text(v).font(DS.Font.numericCaption).foregroundStyle(DS.Text.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(l).font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Etiketli gün etkisi (bu metrik için on-tag vs off-tag ortalama)

    private struct TagImpact: Identifiable {
        let tag: DayTag; let on: Double; let off: Double; let n: Int
        var id: String { tag.id }
    }

    private func tagImpact() -> [TagImpact] {
        guard !windowed.isEmpty else { return [] }
        let cal = Calendar.current
        var out: [TagImpact] = []
        for tag in TagCatalog.all {
            let tagged = labels.dates(withTag: tag.id)
            guard !tagged.isEmpty else { continue }
            var on: [Double] = [], off: [Double] = []
            for s in windowed {
                if tagged.contains(cal.startOfDay(for: s.date)) { on.append(s.value) }
                else { off.append(s.value) }
            }
            guard !on.isEmpty, !off.isEmpty else { continue }
            out.append(TagImpact(tag: tag, on: on.reduce(0,+)/Double(on.count),
                                 off: off.reduce(0,+)/Double(off.count), n: on.count))
        }
        return out
    }

    @ViewBuilder private var tagImpactSection: some View {
        let impact = tagImpact()
        if !impact.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Etiketli günlerin etkisi")
                    .font(DS.Font.heading).foregroundStyle(DS.Text.primary)
                ForEach(impact) { row in
                    let diff = row.on - row.off
                    // Düşük örneklem = düşük güven dilbilgisi (n < keşif eşiği)
                    let lowN = row.n < profileStore.settings.discoveryMinN
                    HStack {
                        Text("\(row.tag.emoji) \(row.tag.title)")
                            .font(DS.Font.secondary).foregroundStyle(DS.Text.primary)
                        Spacer()
                        Text("etiketli \(format(row.on)) (n\(row.n)) · diğer \(format(row.off))")
                            .font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
                        ConfidenceText(text: "\(diff >= 0 ? "+" : "−")\(DS.decimal(abs(diff)))",
                                       confidence: lowN ? .low : .medium,
                                       font: DS.Font.numericCaption,
                                       color: DS.Text.primary)
                    }
                    .padding(.vertical, DS.Space.xs)
                    if row.id != impact.last?.id {
                        Divider().overlay(DS.Surface.divider)
                    }
                }
                Text("Etiketli gün ortalaması ile diğer günlerin ortalaması. Düşük örneklemde (n küçük) yalnızca fikir verir — nedensellik değil.")
                    .font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func format(_ v: Double) -> String {
        v < 10 ? DS.decimal(v) : DS.integer(Int(v.rounded()))
    }
}
