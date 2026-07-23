import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var config: DashboardConfig
    @EnvironmentObject var labels: LabelStore
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var plan: PlanStore
    @EnvironmentObject var notifier: NotificationManager
    @EnvironmentObject var aiConfig: AIConfig
    @EnvironmentObject var aiMemory: AIMemory
    @EnvironmentObject var aiClient: OpenRouterClient
    @StateObject private var whoopAuth = WhoopAuth.shared

    @State private var showPicker = false
    @State private var showLabel = false
    @State private var showCorrelation = false
    @State private var showSettings = false
    @State private var showAI = false
    @State private var detail: EngineDetail?
    @State private var selectedDetail: MetricDef?
    @State private var days = 30

    enum EngineDetail: Int, Identifiable {
        case tdee, weight, baseline, guardrail
        var id: Int { rawValue }
    }

    /// Etiket günleri + plan kategorisi tamamlama günleri — motorlara ve LLM bağlamına girer
    private var tagDates: [String: Set<Date>] {
        var d: [String: Set<Date>] = [:]
        for tag in TagCatalog.all {
            let s = labels.dates(withTag: tag.id)
            if !s.isEmpty { d[tag.id] = s }
        }
        // Plan: bir kategorinin o gün TAM tamamlandığı günler korelasyon taramasına girer
        for c in PlanCategory.allCases {
            let s = PlanEngine.completionDates(items: plan.items, logs: plan.logs, category: c,
                                               days: max(days, 30),
                                               unlockedPhase: plan.unlockedPhase,
                                               phaseEnabled: plan.phaseSettings.enabled)
            if !s.isEmpty { d[PlanEngine.scanId(c)] = s }
        }
        return d
    }

    /// Kategori bazında plan uyumu — guardrail motoruna ve LLM bağlamına girer
    private var planAdherence: [String: Double] {
        var out: [String: Double] = [:]
        for a in PlanEngine.adherenceByCategory(items: plan.items, logs: plan.logs,
                                                days: profileStore.settings.guardrailWindowDays,
                                                unlockedPhase: plan.unlockedPhase,
                                                phaseEnabled: plan.phaseSettings.enabled) {
            if let c = a.category { out[c.rawValue] = a.pct }
        }
        return out
    }

    /// TÜM deterministik hesaplar tek noktadan — kartlar, detaylar ve LLM aynı sayıyı görür
    private var engines: EngineOutputs {
        EngineOutputs.compute(series: store.series,
                              profile: profileStore.profile,
                              settings: profileStore.settings,
                              rules: profileStore.rules,
                              tagDates: tagDates,
                              planAdherence: planAdherence)
    }

    /// Kartların hedefleri tek noktadan çözülür (aynı TDEE sonucu paylaşılır).
    private var resolvedTargets: [String: TargetEngine.ResolvedTarget] {
        TargetEngine.resolveAll(metricIds: config.enabledIds,
                                rules: profileStore.rules,
                                tdee: engines.tdee,
                                profile: profileStore.profile)
    }

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.lg) {
                    header
                    engineCards
                    SectionHeader(title: "Metrikler", actionTitle: "Düzenle") { showPicker = true }
                    let targets = resolvedTargets
                    LazyVGrid(columns: cols, spacing: DS.Space.md) {
                        ForEach(config.enabledMetrics) { def in
                            MetricGridCard(def: def, days: days, target: targets[def.id])
                                .onTapGesture { selectedDetail = def }
                        }
                    }
                    if config.enabledMetrics.isEmpty {
                        EmptyStateView(
                            icon: "square.dashed",
                            title: "Metrik seçilmedi",
                            guidance: "Panelde izlemek istediğin metrikleri kataloğa dokunarak ekle.",
                            actionTitle: "Metrikleri düzenle",
                            action: { showPicker = true }
                        )
                        .cardSurface()
                    }
                    insights
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xxl)
            }
            .background(DS.Surface.background)
            .navigationTitle("Panel")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAI = true } label: { Image(systemName: "sparkles") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showLabel = true } label: { Image(systemName: "tag") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Aralık", selection: $days) {
                            Text("7 gün").tag(7); Text("30 gün").tag(30); Text("90 gün").tag(90)
                        }
                        Divider()
                        Button { showPicker = true } label: { Label("Metrikleri düzenle", systemImage: "slider.horizontal.3") }
                        Button { showCorrelation = true } label: { Label("Korelasyon keşfi", systemImage: "chart.dots.scatter") }
                        Button { showSettings = true } label: { Label("Ayarlar", systemImage: "gearshape") }
                        Divider()
                        if whoopAuth.isConnected {
                            Button("Whoop bağlantısını kes", role: .destructive) { whoopAuth.disconnect() }
                        } else {
                            Button("Whoop'a bağlan") { whoopAuth.connect() }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .refreshable { await reload() }
            .task(id: days) { await reload() }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(profileStore)
                    .environmentObject(plan)
                    .environmentObject(notifier)
                    .environmentObject(aiConfig)
                    .environmentObject(aiMemory)
                    .environmentObject(store)
                    .environmentObject(config)
            }
            .sheet(isPresented: $showAI) {
                AIAssistantView(contextFor: { aiContext($0) }, tdee: engines.tdee)
                    .environmentObject(aiClient)
                    .environmentObject(aiConfig)
                    .environmentObject(aiMemory)
                    .environmentObject(plan)
                    .environmentObject(profileStore)
            }
            .sheet(item: $detail) { d in
                switch d {
                case .tdee:
                    TDEEDetailView(result: engines.tdee)
                        .environmentObject(store).environmentObject(profileStore)
                case .weight:
                    WeightJourneyView(result: engines.trend)
                        .environmentObject(store).environmentObject(profileStore)
                case .baseline:
                    BaselineView(deviations: engines.deviations, composite: engines.composite)
                        .environmentObject(store).environmentObject(profileStore)
                case .guardrail:
                    GuardrailsView(summary: engines.guardrails,
                                   todayStatuses: GuardrailEngine.todayStatuses(
                                       rules: profileStore.rules,
                                       series: store.series,
                                       tagDates: tagDates,
                                       planAdherence: planAdherence))
                        .environmentObject(profileStore)
                }
            }
            .sheet(isPresented: $showPicker) {
                MetricPickerView().environmentObject(config)
            }
            .sheet(isPresented: $showLabel) {
                DayLabelSheet(date: Date()).environmentObject(labels)
            }
            .sheet(isPresented: $showCorrelation) {
                CorrelationView(days: days)
                    .environmentObject(store)
                    .environmentObject(labels)
                    .environmentObject(profileStore)
            }
            .sheet(item: $selectedDetail) { def in
                MetricDetailView(def: def, days: days)
                    .environmentObject(store)
                    .environmentObject(labels)
                    .environmentObject(profileStore)
            }
            .overlay { if store.loading { ProgressView().scaleEffect(1.2) } }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if let d = store.lastUpdated {
                    Text("Güncel: \(d.formatted(date: .abbreviated, time: .shortened))")
                        .font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
                }
                if !whoopAuth.isConnected {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "exclamationmark.circle")
                        Text("Whoop bağlı değil — Recovery/Strain için bağlan")
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Status.attention)
                }
            }
            Spacer()
        }
    }

    /// Dört deterministik motorun özeti — dokununca detay.
    /// Görsel ağırlık eşit değildir: bugün en önemli olan (TDEE) üstte ve büyük,
    /// baseline+guardrail yan yana küçük (DESIGN.md, görsel 02).
    private var engineCards: some View {
        let e = engines
        return VStack(spacing: DS.Space.md) {
            Button { detail = .tdee } label: {
                EngineCard(icon: "flame", title: "Ölçülmüş Metabolizma") {
                    TDEECardBody(r: e.tdee)
                }
            }.buttonStyle(.plain)

            Button { detail = .weight } label: {
                EngineCard(icon: "scalemass", title: "Kilo Yolculuğu") {
                    WeightCardBody(r: e.trend, target: profileStore.profile.targetWeightKg)
                }
            }.buttonStyle(.plain)

            HStack(alignment: .top, spacing: DS.Space.md) {
                Button { detail = .baseline } label: {
                    EngineCard(icon: "waveform.path.ecg", title: "Baseline", badge: {
                        if e.composite.triggered {
                            StatusChip(text: "sinyal", status: DS.Status.critical)
                        } else {
                            StatusChip(text: "nötr")
                        }
                    }) {
                        BaselineCardBody(devs: e.deviations, composite: e.composite)
                    }
                }.buttonStyle(.plain)

                Button { detail = .guardrail } label: {
                    EngineCard(icon: "checklist", title: "Guardrail") {
                        GuardrailCardBody(summary: e.guardrails,
                                          goodScore: profileStore.settings.guardrailGoodScore)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var insights: some View {
        let corr = alcoholCorrelation(for: "hrv")
        return VStack(spacing: DS.Space.md) {
            if corr.alcohol != nil || corr.sober != nil {
                InsightCard(color: DS.Surface.accent, title: "Alkolün HRV'ye etkisi") {
                    HStack(spacing: DS.Space.lg) {
                        statBox("Alkol günü", corr.alcohol.map { DS.integer(Int($0)) } ?? "—")
                        statBox("Alkolsüz", corr.sober.map { DS.integer(Int($0)) } ?? "—")
                        if let a = corr.alcohol, let b = corr.sober { statBox("Fark", "\(DS.integer(Int(b-a))) ms ↓") }
                    }
                }
            }
            HStack(spacing: DS.Space.md) {
                InsightCard(color: DS.Surface.accent, title: "Protein tutturma") {
                    Text(proteinAdherence().map { DS.percent($0) } ?? "—")
                        .font(DS.Font.stat())
                        .foregroundStyle(DS.Text.primary)
                        .monospacedDigit()
                }
                InsightCard(color: DS.Surface.accent, title: "Kilo trendi") {
                    Text(weightTrend().map { "\($0.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)).locale(DS.locale))) kg" } ?? "—")
                        .font(DS.Font.stat())
                        .foregroundStyle(DS.Text.primary)
                        .monospacedDigit()
                }
            }
            let counts = labelCounts()
            if !counts.isEmpty {
                InsightCard(color: DS.Surface.accent, title: "Son \(days) gün etiketleri") {
                    HStack(spacing: DS.Space.lg) {
                        ForEach(counts) { item in
                            VStack(spacing: DS.Space.xs) {
                                Text(item.tag.emoji)
                                Text(DS.integer(item.n))
                                    .font(DS.Font.body.weight(.semibold))
                                    .foregroundStyle(DS.Text.primary)
                                    .monospacedDigit()
                                Text(item.tag.title)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Text.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Button { showCorrelation = true } label: {
                InsightCard(color: DS.Surface.accent, title: "Korelasyon Keşfi") {
                    HStack {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text("Neyin neyi etkilediğini tara")
                                .font(DS.Font.body.weight(.semibold))
                                .foregroundStyle(DS.Text.primary)
                            Text("Metrik çiftleri + etiket etkileri, aynı gün ve ertesi gün")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Text.secondary)
                        }
                        Spacer()
                        Image(systemName: "chart.dots.scatter")
                            .font(DS.Font.heading)
                            .foregroundStyle(DS.Surface.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func statBox(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(v)
                .font(DS.Font.stat())
                .foregroundStyle(DS.Text.primary)
                .monospacedDigit()
            Text(l)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)
        }
    }

    private func reload() async {
        // Görünüm seçici (7/30/90) yalnız görünümü daraltır; çekim her zaman kalıcı pencereyi kapsar
        let window = max(days, config.fetchWindowDays)
        await store.refresh(days: window, ids: config.enabledIds)
        // Motorların ihtiyacı olan metrikler dashboard'da kapalı olsa bile yüklenir
        for id in profileStore.requiredMetricIds {
            await store.ensureLoaded(id, days: max(window, profileStore.settings.baselineWindowDays))
        }
    }

    /// LLM'e gidecek deterministik bağlam — motor çıktılarının aynısı, göreve göre biçimlenir
    private func aiContext(_ task: AITask) -> String {
        let e = engines
        let counts = labelCounts().map { ($0.tag.id, $0.n) }
        let today = PlanEngine.occurrences(on: Date(), items: plan.items,
                                           unlockedPhase: plan.unlockedPhase,
                                           phaseEnabled: plan.phaseSettings.enabled)
        let planSummary = AIContext.planBlock(
            occurrences: today,
            logs: plan.logs,
            adherence: PlanEngine.adherenceByCategory(items: plan.items, logs: plan.logs,
                                                      days: profileStore.settings.guardrailWindowDays,
                                                      unlockedPhase: plan.unlockedPhase,
                                                      phaseEnabled: plan.phaseSettings.enabled),
            streak: PlanEngine.streak(items: plan.items, logs: plan.logs,
                                      unlockedPhase: plan.unlockedPhase,
                                      phaseEnabled: plan.phaseSettings.enabled),
            phase: plan.unlockedPhase)
        let dayProgress = ProgressEngine.computeAll(
            metricIds: profileStore.settings.todayProgressMetricIds,
            series: store.series,
            rules: profileStore.rules,
            tdee: e.tdee,
            profile: profileStore.profile)
        return AIContext.snapshot(profile: profileStore.profile,
                                  settings: profileStore.settings,
                                  rules: profileStore.rules,
                                  healthContext: profileStore.context,
                                  task: task,
                                  planBlock: planSummary,
                                  tdee: e.tdee,
                                  trend: e.trend,
                                  deviations: e.deviations,
                                  composite: e.composite,
                                  guardrails: e.guardrails,
                                  dayProgress: dayProgress,
                                  series: store.series,
                                  labelCounts: counts,
                                  config: aiConfig)
    }

    // İçgörü hesapları (alkol günü: HealthKit alcoholBev>0 VEYA lokal "alkol" etiketi)
    private func alcoholDays() -> Set<Date> {
        let cal = Calendar.current
        var set = Set<Date>()
        if let s = store.series["alcoholBev"] {
            set.formUnion(s.filter { $0.value > 0 }.map { cal.startOfDay(for: $0.date) })
        }
        set.formUnion(labels.dates(withTag: "alcohol"))   // yerel etiketleri de say
        return set
    }
    private func alcoholCorrelation(for id: String) -> (alcohol: Double?, sober: Double?) {
        guard let s = store.series[id] else { return (nil, nil) }
        let days = alcoholDays(); let cal = Calendar.current
        var a: [Double] = []; var b: [Double] = []
        for dv in s {
            if days.contains(cal.startOfDay(for: dv.date)) { a.append(dv.value) }
            else { b.append(dv.value) }
        }
        func mean(_ x: [Double]) -> Double? { x.isEmpty ? nil : x.reduce(0,+)/Double(x.count) }
        return (mean(a), mean(b))
    }
    private func proteinAdherence() -> Int? {
        guard let s = store.series["protein"], !s.isEmpty else { return nil }
        return Int(Double(s.filter { $0.value >= 170 }.count) / Double(s.count) * 100)
    }
    private func weightTrend() -> Double? {
        guard let s = store.series["weight"], s.count >= 2 else { return nil }
        return s.last!.value - s.first!.value
    }

    /// Son `days` gün içindeki etiket sayıları (özet kart için)
    private struct LabelCount: Identifiable {
        let tag: DayTag; let n: Int
        var id: String { tag.id }
    }
    private func labelCounts() -> [LabelCount] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let start = cal.startOfDay(for: cutoff)
        var counts: [String: Int] = [:]
        for (d, tags) in labels.labeledDays() where d >= start {
            for t in tags { counts[t, default: 0] += 1 }
        }
        return TagCatalog.all.compactMap { tag in counts[tag.id].map { LabelCount(tag: tag, n: $0) } }
    }
}
