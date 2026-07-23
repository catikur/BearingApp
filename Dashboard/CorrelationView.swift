import SwiftUI
import Charts

struct CorrelationView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var labels: LabelStore
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss
    let days: Int

    @State private var mode = 0                      // 0 = elle, 1 = otomatik keşif
    @State private var xId = "whoop_strain"
    @State private var yId = "whoop_recovery"
    @State private var lag = 1
    @State private var picking: PickTarget?
    @State private var findings: [PatternScan.Finding] = []
    @State private var tagFindings: [PatternScan.TagFinding] = []
    @State private var hiddenTrivial = 0
    @State private var scanning = false
    @State private var scanned = false
    @State private var showFilterInfo = false

    private enum PickTarget: Identifiable { case x, y; var id: Int { self == .x ? 0 : 1 } }

    private var xDef: MetricDef? { HealthMetricCatalog.byId(xId) }
    private var yDef: MetricDef? { HealthMetricCatalog.byId(yId) }

    private var points: [PairedPoint] {
        guard let a = store.series[xId], let b = store.series[yId] else { return [] }
        return Stats.pair(a, b, lagDays: lag)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    Picker("Mod", selection: $mode) {
                        Text("Elle karşılaştır").tag(0)
                        Text("Otomatik keşif").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if mode == 0 { manualSection } else { discoverySection }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.lg)
            }
            .background(DS.Surface.background)
            .navigationTitle("Korelasyon Keşfi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
            .sheet(item: $picking) { target in
                MetricSelectSheet { id in
                    if target == .x { xId = id } else { yId = id }
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showFilterInfo) {
                DiscoveryFilterInfoView().environmentObject(profileStore)
            }
            .task(id: xId) { await store.ensureLoaded(xId, days: days) }
            .task(id: yId) { await store.ensureLoaded(yId, days: days) }
        }
    }

    // MARK: - Elle karşılaştırma
    @ViewBuilder private var manualSection: some View {
        VStack(spacing: DS.Space.sm) {
            selectorRow(label: "X (etki eden)", def: xDef) { picking = .x }
            selectorRow(label: "Y (etkilenen)", def: yDef) { picking = .y }
            Picker("Gecikme", selection: $lag) {
                Text("Aynı gün").tag(0)
                Text("Ertesi gün").tag(1)
                Text("2 gün sonra").tag(2)
            }
            .pickerStyle(.segmented)
        }

        let pts = points
        if pts.count < 3 {
            EmptyStateView(
                icon: "chart.dots.scatter",
                title: "Yeterli ortak gün yok",
                guidance: "Bu iki metriğin aynı günlerde verisi olmalı. Aralığı büyüt (90 gün) veya başka metrik seç."
            )
            .cardSurface()
        } else if let r = Stats.pearson(pts) {
            resultCard(r: r, pts: pts)
            scatter(pts)
        }
    }

    private func selectorRow(label: String, def: MetricDef?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
                Spacer()
                Text(def?.title ?? "Seç")
                    .font(DS.Font.secondary.weight(.semibold))
                    .foregroundStyle(DS.Text.primary)
                Image(systemName: "chevron.right")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
            }
            .padding(.vertical, DS.Space.md)
            .padding(.horizontal, DS.Space.md)
            .background(DS.Surface.card,
                        in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Surface.divider, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func resultCard(r: Double, pts: [PairedPoint]) -> some View {
        let dir = r > 0 ? "birlikte artıyor" : "ters yönde hareket ediyor"
        let lagText = lag == 0 ? "aynı gün" : "\(lag) gün sonra"
        return InsightCard(color: abs(r) >= 0.5 ? DS.Surface.accent : DS.Status.neutral, title: "Sonuç") {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    Text("r = \(DS.decimal(r, fraction: 2))")
                        .font(DS.Font.stat())
                        .foregroundStyle(DS.Text.primary)
                        .monospacedDigit()
                    Text(Stats.strengthLabel(r))
                        .font(DS.Font.secondary)
                        .foregroundStyle(DS.Text.secondary)
                }
                Text("\(xDef?.title ?? "") arttığında, \(yDef?.title ?? "") \(lagText) \(dir).")
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Text.primary)
                Text(Stats.confidenceNote(r: r, n: pts.count))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
            }
        }
    }

    private func scatter(_ pts: [PairedPoint]) -> some View {
        let lr = Stats.linreg(pts)
        let minX = pts.map(\.x).min() ?? 0
        let maxX = pts.map(\.x).max() ?? 1
        var trend: [PairedPoint] = []
        if let lr = lr {
            trend = [
                PairedPoint(date: Date(), x: minX, y: lr.slope * minX + lr.intercept),
                PairedPoint(date: Date(), x: maxX, y: lr.slope * maxX + lr.intercept),
            ]
        }
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            Chart {
                ForEach(pts) { p in
                    PointMark(x: .value("X", p.x), y: .value("Y", p.y))
                        .foregroundStyle(DS.Surface.accent.opacity(0.75))
                }
                ForEach(trend) { t in
                    LineMark(x: .value("X", t.x), y: .value("Y", t.y),
                             series: .value("s", "trend"))
                        .foregroundStyle(DS.Text.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                }
            }
            .frame(height: 250)
            HStack {
                Text("X: \(xDef?.title ?? "") (\(xDef?.unit ?? ""))")
                Spacer()
                Text("Y: \(yDef?.title ?? "") (\(yDef?.unit ?? ""))")
            }
            .font(DS.Font.caption)
            .foregroundStyle(DS.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Otomatik keşif
    @ViewBuilder private var discoverySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Yüklü tüm metrikleri ve etiketleri tarayıp en güçlü ilişkileri sıralar. Aynı gün ve ertesi gün etkileri ayrı değerlendirilir.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)

            HStack(spacing: DS.Space.sm) {
                Button { Task { await runScan(loadAll: false) } } label: {
                    Label("Yüklüleri tara", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Surface.accent)

                Button { Task { await runScan(loadAll: true) } } label: {
                    Label("Tümünü tara", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.bordered)
                .tint(DS.Surface.accent)
            }
            Text("\"Tümünü tara\" tüm katalog metriklerini Apple Health'ten çeker — biraz sürebilir.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)

            if scanning {
                HStack(spacing: DS.Space.sm) {
                    ProgressView()
                    Text("Taranıyor…").font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
                }
                .padding(.vertical, DS.Space.sm)
            }

            if !tagFindings.isEmpty {
                Text("Etiketlerin etkisi")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Text.primary)
                ForEach(tagFindings.prefix(8)) { f in tagRow(f) }
            }

            if !findings.isEmpty {
                Text("Metrik ilişkileri")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Text.primary)
                    .padding(.top, DS.Space.xs)
                ForEach(findings.prefix(profileStore.settings.discoveryTopCount)) { f in findingRow(f) }
                Text("Not: Çok sayıda çift tarandığı için en üstteki birkaç ilişki şansa da denk gelebilir (çoklu karşılaştırma). Bir bulguyu ciddiye almadan önce elle karşılaştırmada aç, örneklem sayısına bak ve birkaç hafta izle.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
                    .padding(.top, DS.Space.xs)
            }

            if scanned && hiddenTrivial > 0 {
                Button { showFilterInfo = true } label: {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("\(DS.integer(hiddenTrivial)) çift filtre nedeniyle gizlendi — neden?")
                            .font(DS.Font.caption)
                        Spacer()
                        Image(systemName: "chevron.right").font(DS.Font.caption)
                    }
                    .foregroundStyle(DS.Text.secondary)
                    .padding(DS.Space.md)
                    .background(DS.Surface.card,
                                in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .strokeBorder(DS.Surface.divider, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            if scanned && findings.isEmpty && tagFindings.isEmpty && !scanning {
                EmptyStateView(
                    icon: "questionmark.folder",
                    title: "Bulgu yok",
                    guidance: "Yeterli ortak günü olan metrik çifti bulunamadı. Aralığı 90 güne çıkar veya daha fazla metrik etkinleştir."
                )
                .cardSurface()
            }
        }
    }

    private func tagRow(_ f: PatternScan.TagFinding) -> some View {
        let tag = TagCatalog.tag(f.tagId)
        let planName = PlanEngine.displayName(forScanId: f.tagId)
        let metric = HealthMetricCatalog.byId(f.metricId)
        let worse = (metric?.higherIsBetter ?? true) ? (f.delta < 0) : (f.delta > 0)
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Text(planName ?? "\(tag?.emoji ?? "") \(tag?.title ?? f.tagId)")
                    .font(DS.Font.body.weight(.semibold))
                    .foregroundStyle(DS.Text.primary)
                Text(f.lag == 0 ? "aynı gün" : "ertesi gün")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
                Spacer()
                Text("\(f.deltaPct.formatted(.number.sign(strategy: .always()).precision(.fractionLength(0)).locale(DS.locale)))%")
                    .font(DS.Font.body.weight(.semibold))
                    .foregroundStyle(worse ? DS.Status.attention : DS.Status.positive)
                    .monospacedDigit()
            }
            Text("\(metric?.title ?? f.metricId): etiketli \(fmt(f.on)) · diğer \(fmt(f.off)) (n=\(DS.integer(f.n)))")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: DS.Space.md)
    }

    private func findingRow(_ f: PatternScan.Finding) -> some View {
        Button {
            xId = f.xId; yId = f.yId; lag = f.lag; mode = 0
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.xs) {
                    Text(HealthMetricCatalog.byId(f.xId)?.title ?? f.xId)
                        .font(DS.Font.caption.weight(.semibold))
                        .foregroundStyle(DS.Text.primary)
                    Image(systemName: "arrow.right")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                    Text(HealthMetricCatalog.byId(f.yId)?.title ?? f.yId)
                        .font(DS.Font.caption.weight(.semibold))
                        .foregroundStyle(DS.Text.primary)
                    Spacer()
                    Text(DS.decimal(f.r, fraction: 2))
                        .font(DS.Font.body.weight(.semibold))
                        .foregroundStyle(abs(f.r) >= 0.5 ? DS.Surface.accent : DS.Text.secondary)
                        .monospacedDigit()
                }
                Text("\(f.lag == 0 ? "aynı gün" : "\(f.lag) gün sonra") · n=\(DS.integer(f.n)) · \(Stats.strengthLabel(f.r))")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: DS.Space.md)
        }
        .buttonStyle(.plain)
    }

    private func runScan(loadAll: Bool) async {
        scanning = true
        defer { scanning = false; scanned = true }
        if loadAll { await store.loadAllHealthKit(days: days) }
        var tagDates: [String: Set<Date>] = [:]
        for tag in TagCatalog.all {
            let d = labels.dates(withTag: tag.id)
            if !d.isEmpty { tagDates[tag.id] = d }
        }
        let series = store.series
        let settings = profileStore.settings
        let result = PatternScan.scan(series: series, settings: settings)
        findings = result.findings
        hiddenTrivial = result.hiddenTrivial
        tagFindings = PatternScan.scanTags(series: series, tagDates: tagDates, settings: settings)
    }

    private func fmt(_ v: Double) -> String {
        v < 10 ? DS.decimal(v) : DS.integer(Int(v.rounded()))
    }
}

/// Katalogdan metrik seçme sayfası (aranabilir, veri var/yok işaretli).
/// Yapılandırma/liste ailesi — native List idiomu (Ayarlar ekranlarıyla tutarlı).
private struct MetricSelectSheet: View {
    @EnvironmentObject var store: DataStore
    let onPick: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var search = ""

    private var filtered: [MetricDef] {
        let all = HealthMetricCatalog.all
        guard !search.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(HealthMetricCatalog.categories, id: \.self) { cat in
                    let items = filtered.filter { $0.category == cat }
                    if !items.isEmpty {
                        Section(cat) {
                            ForEach(items) { def in
                                Button {
                                    onPick(def.id); dismiss()
                                } label: {
                                    HStack {
                                        Text(def.title)
                                        Spacer()
                                        if let s = store.series[def.id], !s.isEmpty {
                                            Text("\(s.count) gün")
                                                .font(.caption2).foregroundStyle(DS.Status.positive)
                                        } else {
                                            Text("veri yok")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Metrik ara")
            .navigationTitle("Metrik Seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }
}
