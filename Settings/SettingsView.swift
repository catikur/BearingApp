import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var plan: PlanStore
    @EnvironmentObject var notifier: NotificationManager
    @EnvironmentObject var aiConfig: AIConfig
    @EnvironmentObject var memory: AIMemory
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var config: DashboardConfig
    @StateObject private var whoopAuth = WhoopAuth.shared
    @Environment(\.dismiss) var dismiss

    @State private var showWhoopCreds = false
    @State private var whoopClientID = ""
    @State private var whoopClientSecret = ""

    @State private var showRules = false
    @State private var showAI = false
    @State private var showDiscovery = false
    @State private var showNotif = false
    @State private var showContext = false
    @State private var showPlan = false
    @State private var showMetricPick: MetricPickTarget?
    @State private var showTargets = false
    @State private var showTodayMetrics = false

    private enum MetricPickTarget: Identifiable {
        case baseline, composite
        var id: Int { self == .baseline ? 0 : 1 }
    }

    var body: some View {
        NavigationStack {
            Form {
                dataSection
                profileSection
                goalSection
                tdeeSection
                trendSection
                baselineSection
                planSection
                guardrailSection
                targetsSection
                discoverySection
                aiSection
                resetSection
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
            .sheet(isPresented: $showRules) { RuleEditorView().environmentObject(profileStore) }
            .sheet(isPresented: $showAI) {
                AISettingsView().environmentObject(aiConfig).environmentObject(memory)
            }
            .sheet(isPresented: $showDiscovery) {
                DiscoveryFilterInfoView().environmentObject(profileStore)
            }
            .sheet(isPresented: $showContext) {
                HealthContextView().environmentObject(profileStore)
            }
            .sheet(isPresented: $showNotif) {
                NotificationSettingsView().environmentObject(plan).environmentObject(notifier)
            }
            .sheet(isPresented: $showPlan) {
                PlanEditorView().environmentObject(plan)
            }
            .sheet(item: $showMetricPick) { target in
                MultiMetricPicker(
                    title: target == .baseline ? "İzlenecek metrikler" : "Bileşik sinyal metrikleri",
                    selection: target == .baseline
                        ? $profileStore.settings.baselineMetricIds
                        : $profileStore.settings.compositeMetricIds)
            }
            .sheet(isPresented: $showTargets) {
                TargetsSummaryView(tdee: resolvedTDEE).environmentObject(profileStore)
            }
            .sheet(isPresented: $showTodayMetrics) {
                MultiMetricPicker(title: "Bugün bloğu metrikleri",
                                  selection: $profileStore.settings.todayProgressMetricIds)
            }
        }
    }

    /// Hedef özetinin ihtiyaç duyduğu kalori hedefi için TDEE — motorla aynı girdiler.
    private var resolvedTDEE: TDEEEngine.Result? {
        TDEEEngine.compute(intake: store.series["calories"] ?? [],
                           weight: store.series["weight"] ?? [],
                           settings: profileStore.settings,
                           profile: profileStore.profile)
    }

    // MARK: Veri kaynakları
    private var dataSection: some View {
        Section {
            HStack {
                Label("Whoop", systemImage: "waveform.path.ecg")
                Spacer()
                if whoopAuth.isConnected {
                    Text("Bağlı").font(.subheadline).foregroundStyle(Color.green)
                    Button("Kes", role: .destructive) { whoopAuth.disconnect() }
                        .font(.subheadline).buttonStyle(.borderless)
                } else {
                    Button("Bağlan") { whoopAuth.connect() }
                        .buttonStyle(.borderless)
                        .disabled(!whoopAuth.hasCredentials)
                }
            }
            if let err = whoopAuth.authError {
                Text(err).font(.caption).foregroundStyle(Color.red)
            }
            // Whoop istemci bilgileri: Keychain'de yaşar; repo/binary'de sır yok (docs/adr/0002).
            // developer.whoop.com → Create App; Redirect URI: bearing://whoop-callback
            DisclosureGroup(isExpanded: $showWhoopCreds.animation()) {
                TextField("Client ID", text: $whoopClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .onAppear { if whoopClientID.isEmpty { whoopClientID = whoopAuth.storedClientID } }
                SecureField("Client Secret", text: $whoopClientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Kimlik bilgilerini kaydet") {
                    whoopAuth.saveCredentials(clientID: whoopClientID, clientSecret: whoopClientSecret)
                    whoopClientSecret = ""
                    showWhoopCreds = false
                }
                .disabled(whoopClientID.trimmingCharacters(in: .whitespaces).isEmpty ||
                          whoopClientSecret.trimmingCharacters(in: .whitespaces).isEmpty)
                if whoopAuth.hasCredentials {
                    Button("Kimlik bilgilerini sil", role: .destructive) {
                        whoopAuth.clearCredentials()
                        whoopClientID = ""
                    }
                }
            } label: {
                HStack {
                    Text("Whoop istemci bilgileri")
                    Spacer()
                    Text(whoopAuth.hasCredentials ? "kayıtlı" : "eksik")
                        .font(DS.Font.caption)
                        .foregroundStyle(whoopAuth.hasCredentials ? Color.green : DS.Status.attention)
                }
            }
            Picker("Geçmiş penceresi", selection: Binding(
                get: { config.fetchWindowDays },
                set: { config.setFetchWindow($0) }
            )) {
                Text("30 gün").tag(30)
                Text("90 gün").tag(90)
                Text("180 gün").tag(180)
                Text("1 yıl").tag(365)
                Text("2 yıl").tag(730)
            }
            Button {
                Task { await pullHistory() }
            } label: {
                if store.loading {
                    HStack(spacing: 8) { ProgressView(); Text("Çekiliyor…") }
                } else {
                    Label("Geçmiş veriyi şimdi çek", systemImage: "arrow.down.circle")
                }
            }
            .disabled(store.loading)
            WhoopDiagnosticsView(whoop: store.whoop)
        } header: { Text("Veri kaynakları") } footer: {
            Text("Pencere hem Whoop hem HealthKit çekimine uygulanır; dashboard'daki 7/30/90 seçici yalnız görünümü daraltır. Whoop verisi sayfalanarak alınır, uzun pencerelerde çekim birkaç saniye sürebilir.")
        }
    }

    private func pullHistory() async {
        let window = config.fetchWindowDays
        await store.refresh(days: window, ids: config.enabledIds)
        for id in profileStore.requiredMetricIds {
            await store.ensureLoaded(id, days: max(window, profileStore.settings.baselineWindowDays))
        }
    }

    // MARK: Profil
    private var profileSection: some View {
        Section("Profil") {
            TextField("Ad (opsiyonel)", text: $profileStore.profile.name)
            Stepper("Yaş: \(profileStore.profile.age)", value: $profileStore.profile.age, in: 14...100)
            Picker("Cinsiyet", selection: $profileStore.profile.sex) {
                ForEach(BioSex.allCases) { Text($0.label).tag($0) }
            }
            num("Boy (cm)", $profileStore.profile.heightCm)
        }
    }

    // MARK: Hedef
    private var goalSection: some View {
        Section {
            num("Hedef kilo (kg)", $profileStore.profile.targetWeightKg)
            num("Hedef hız (kg/hafta)", $profileStore.profile.targetRateKgPerWeek)
            HStack {
                Text("Başlangıç kilosu")
                Spacer()
                TextField("otomatik", value: Binding(
                    get: { profileStore.profile.startWeightKg ?? 0 },
                    set: { profileStore.profile.startWeightKg = $0 > 0 ? $0 : nil }),
                    format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            }
            TextField("Amacın (yapay zekâ katmanına bağlam olur)",
                      text: $profileStore.profile.goalNote, axis: .vertical)
                .lineLimit(1...4)
        } header: { Text("Hedef") }
        footer: { Text("Başlangıç kilosu boşsa serideki ilk ölçüm kullanılır. İlerleme yüzdesi buna göre hesaplanır.") }
    }

    // MARK: TDEE
    private var tdeeSection: some View {
        Section {
            stepper("Pencere", $profileStore.settings.tdeeWindowDays, 7...60, "gün")
            stepper("Minimum gün", $profileStore.settings.tdeeMinDays, 5...30, "gün")
            num("kcal / kg", $profileStore.settings.kcalPerKg)
            HStack {
                Text("Min. log kapsaması")
                Spacer()
                Text("%\(Int(profileStore.settings.tdeeMinIntakeCoverage * 100))")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $profileStore.settings.tdeeMinIntakeCoverage, in: 0.3...1.0, step: 0.05)
        } header: { Text("Adaptif TDEE") }
        footer: { Text("kcal/kg: 1 kg vücut ağırlığı değişiminin enerji karşılığı. Yaygın varsayım 7700; yağsız doku kaybı payı varsa düşürebilirsin.") }
    }

    // MARK: Kilo trendi
    private var trendSection: some View {
        Section {
            HStack {
                Text("EMA yarı ömrü")
                Spacer()
                Text("\(Int(profileStore.settings.emaHalfLifeDays)) gün").foregroundStyle(.secondary)
            }
            Slider(value: $profileStore.settings.emaHalfLifeDays, in: 2...21, step: 1)
            stepper("Hız penceresi", $profileStore.settings.rateWindowDays, 7...90, "gün")
        } header: { Text("Kilo trendi") }
        footer: { Text("Yarı ömür kısa → trend daha çevik ama gürültülü. Uzun → daha kararlı ama geç tepki verir.") }
    }

    // MARK: Baseline
    private var baselineSection: some View {
        Section {
            stepper("Baseline penceresi", $profileStore.settings.baselineWindowDays, 7...120, "gün")
            HStack {
                Text("Sapma eşiği (z)")
                Spacer()
                Text(String(format: "%.1f", profileStore.settings.baselineZThreshold)).foregroundStyle(.secondary)
            }
            Slider(value: $profileStore.settings.baselineZThreshold, in: 1.0...3.0, step: 0.1)
            stepper("Min. örneklem", $profileStore.settings.baselineMinSamples, 5...60, "gün")

            Button { showMetricPick = .baseline } label: {
                HStack {
                    Text("İzlenecek metrikler")
                    Spacer()
                    Text("\(profileStore.settings.baselineMetricIds.count)").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button { showMetricPick = .composite } label: {
                HStack {
                    Text("Bileşik sinyal metrikleri")
                    Spacer()
                    Text("\(profileStore.settings.compositeMetricIds.count)").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            stepper("Kaç metrik birlikte sapmalı", $profileStore.settings.compositeMinFiring, 2...6, "")
        } header: { Text("Baseline & sapma") }
        footer: { Text("Eşik düşük → daha çok uyarı, daha çok yanlış alarm. 1.5 makul bir başlangıç; 2.0 daha seçici.") }
    }

    // MARK: Guardrail
    private var guardrailSection: some View {
        Section {
            stepper("Değerlendirme penceresi", $profileStore.settings.guardrailWindowDays, 7...90, "gün")
            HStack {
                Text("\"İyi\" skor eşiği")
                Spacer()
                Text("\(Int(profileStore.settings.guardrailGoodScore))").foregroundStyle(.secondary)
            }
            Slider(value: $profileStore.settings.guardrailGoodScore, in: 50...100, step: 5)
            Button { showRules = true } label: {
                HStack {
                    Text("Kuralları düzenle")
                    Spacer()
                    Text("\(profileStore.rules.filter { $0.enabled }.count) etkin").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: { Text("Guardrail uyumu") }
    }

    // MARK: Günlük hedefler
    private var targetsSection: some View {
        Section {
            Button { showTargets = true } label: {
                HStack {
                    Label("Hedeflerim özeti", systemImage: "target")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            Button { showTodayMetrics = true } label: {
                HStack {
                    Text("Bugün bloğu metrikleri")
                    Spacer()
                    Text("\(profileStore.settings.todayProgressMetricIds.count)").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: { Text("Günlük hedefler") }
        footer: { Text("Hedeflerim özeti: her metriğin hedefi nereden geliyor (kuralın / TDEE / yedek). Bugün bloğu: Bugün sekmesinde ilerlemesi gösterilecek metrikler.") }
    }

    // MARK: AI
    private var aiSection: some View {
        Section {
            Button { showContext = true } label: {
                HStack {
                    Label("Kişisel bağlam", systemImage: "person.text.rectangle")
                    Spacer()
                    Text(profileStore.context.isEmpty ? "boş" : "dolu")
                        .foregroundStyle(profileStore.context.isEmpty ? Color.secondary : Color.green)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            Button { showAI = true } label: {
                HStack {
                    Label("Yapay Zekâ (OpenRouter)", systemImage: "sparkles")
                    Spacer()
                    Text(aiConfig.enabled && aiConfig.hasKey ? "açık" : "kapalı")
                        .foregroundStyle(aiConfig.enabled && aiConfig.hasKey ? .green : .secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } footer: {
            Text("Yapay zekâ yalnızca yorum yapar. Bütün sayılar bu cihazda deterministik olarak hesaplanır ve modele hazır verilir.")
        }
    }

    private var planSection: some View {
        Section {
            Button { showPlan = true } label: {
                HStack {
                    Label("Plan öğeleri", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Text("\(plan.items.filter { $0.enabled }.count) etkin").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            Button { showNotif = true } label: {
                HStack {
                    Label("Bildirimler", systemImage: "bell.badge")
                    Spacer()
                    Text(plan.notifSettings.enabled && notifier.authorized ? "açık" : "kapalı")
                        .foregroundStyle(plan.notifSettings.enabled && notifier.authorized ? .green : .secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: { Text("Plan ve hatırlatmalar") }
    }

    private var discoverySection: some View {
        Section {
            Button { showDiscovery = true } label: {
                HStack {
                    Label("Keşif filtreleri", systemImage: "line.3.horizontal.decrease.circle")
                    Spacer()
                    Text(filterSummary).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: { Text("Korelasyon keşfi") }
        footer: { Text("Hangi metrik çiftlerinin listeden gizlendiğini görebilir ve filtreyi kapatabilirsin.") }
    }

    private var filterSummary: String {
        let t = profileStore.settings.discoveryFilterTwins
        let f = profileStore.settings.discoveryFilterFamilies
        if t && f { return "2 filtre açık" }
        if t || f { return "1 filtre açık" }
        return "kapalı"
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) { profileStore.resetSettings() } label: {
                Label("Motor parametrelerini sıfırla", systemImage: "arrow.counterclockwise")
            }
        }
    }

    // MARK: Yardımcılar
    private func num(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
    private func stepper(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, _ unit: String) -> some View {
        Stepper("\(label): \(value.wrappedValue)\(unit.isEmpty ? "" : " " + unit)", value: value, in: range)
    }
}

/// Çoklu metrik seçici (baseline / bileşik sinyal listeleri için)
struct MultiMetricPicker: View {
    let title: String
    @Binding var selection: [String]
    @Environment(\.dismiss) var dismiss
    @State private var search = ""

    private var items: [MetricDef] {
        let all = HealthMetricCatalog.all
        return search.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selection.isEmpty {
                    Section("Seçili") {
                        ForEach(selection, id: \.self) { id in
                            HStack {
                                Text(HealthMetricCatalog.byId(id)?.title ?? id)
                                Spacer()
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selection.removeAll { $0 == id } }
                        }
                        .onMove { selection.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
                ForEach(HealthMetricCatalog.categories, id: \.self) { cat in
                    let list = items.filter { $0.category == cat && !selection.contains($0.id) }
                    if !list.isEmpty {
                        Section(cat) {
                            ForEach(list) { def in
                                Button { selection.append(def.id) } label: {
                                    HStack {
                                        Text(def.title)
                                        Spacer()
                                        Image(systemName: "plus.circle").foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Metrik ara")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } }
            }
        }
    }
}

// MARK: - Hedeflerim özeti
/// Tüm çözümlenmiş hedefler tek listede: her birinin yanında kaynağı ve yönü.
/// Çelişki tekrar oluşursa kullanıcı tek bakışta fark eder. Hesap TargetEngine'de.
struct TargetsSummaryView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss
    let tdee: TDEEEngine.Result?

    /// Bugün bloğu metrikleri + kural hedefli metrikler + kalori (sıralı, tekilleştirilmiş).
    private var metricIds: [String] {
        var ids = profileStore.settings.todayProgressMetricIds
        ids.append("calories")
        for r in profileStore.rules where r.enabled {
            if r.kind == .metricThreshold || r.kind == .percentOfEnergy { ids.append(r.targetId) }
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private var resolved: [(String, TargetEngine.ResolvedTarget)] {
        metricIds.compactMap { id in
            TargetEngine.resolve(metricId: id, rules: profileStore.rules,
                                 tdee: tdee, profile: profileStore.profile)
                .map { (id, $0) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if resolved.isEmpty {
                    ContentUnavailableView("Hedef yok",
                        systemImage: "target",
                        description: Text("Hiçbir metrik için çözümlenmiş hedef yok. Kural ekle veya kalori için TDEE hesaplanmasını bekle."))
                } else {
                    Section {
                        ForEach(resolved, id: \.0) { id, t in row(id, t) }
                    } footer: {
                        Text("Kaynak sırası: kuralın → TDEE → yedek katalog. Farklı bir hedef istiyorsan kural oluştur; yedek yalnızca kural yokken devreye girer.")
                    }
                }
            }
            .navigationTitle("Hedeflerim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }

    private func row(_ id: String, _ t: TargetEngine.ResolvedTarget) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(HealthMetricCatalog.byId(id)?.title ?? id)
                    .font(.subheadline.bold())
                Spacer()
                Text(targetText(t))
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 6) {
                sourceBadge(t.source)
                if let note = t.derivedNote {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    private func targetText(_ t: TargetEngine.ResolvedTarget) -> String {
        if t.direction == .between, let u = t.upperValue {
            return "\(fmt(t.value))–\(fmt(u)) \(t.unit)"
        }
        return "\(t.direction.symbol) \(fmt(t.value)) \(t.unit)"
    }

    @ViewBuilder private func sourceBadge(_ s: TargetEngine.TargetSource) -> some View {
        let (text, color): (String, Color) = {
            switch s {
            case .guardrailRule: return ("kuralın", DS.Status.positive)
            case .tdeeEngine:    return ("TDEE", DS.Surface.accent)
            case .catalog:       return ("yedek", DS.Status.neutral)
            case .none:          return ("yok", DS.Status.neutral)
            }
        }()
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Whoop tanı paneli
/// WhoopStore iç içe ObservableObject olduğundan (DataStore.whoop) ayrı bir view'da
/// @ObservedObject ile izlenir; yoksa @Published değişimleri SettingsView'u yenilemez.
private struct WhoopDiagnosticsView: View {
    @ObservedObject var whoop: WhoopStore

    var body: some View {
        if let sync = whoop.lastSync {
            VStack(alignment: .leading, spacing: 4) {
                Text("Son Whoop çekimi: \(sync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(whoop.lastCounts, id: \.0) { item in
                        VStack(spacing: 1) {
                            Text("\(item.1)").font(.caption.bold())
                                .foregroundStyle(item.1 > 0 ? Color.primary : Color.orange)
                            Text(item.0).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(Array(whoop.lastErrors.prefix(3).enumerated()), id: \.offset) { _, e in
                    Text(e).font(.caption2).foregroundStyle(Color.red).lineLimit(3)
                }
                if whoop.lastErrors.count > 3 {
                    Text("… ve \(whoop.lastErrors.count - 3) hata daha")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
