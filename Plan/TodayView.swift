import SwiftUI

struct TodayView: View {
    @EnvironmentObject var plan: PlanStore
    @EnvironmentObject var notifier: NotificationManager
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var profileStore: ProfileStore

    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var showEditor = false
    @State private var session: WorkoutTemplate?
    @State private var sessionDay = Date()

    private var occurrences: [PlanOccurrence] {
        PlanEngine.occurrences(on: day, items: plan.items,
                               unlockedPhase: plan.unlockedPhase,
                               phaseEnabled: plan.phaseSettings.enabled)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    // MARK: Bugünün beslenme ilerlemesi (deterministik — motordan gelir)
    /// TDEE motorunu aynı girdilerle çalıştırır; kalori hedefi buradan çözülür.
    private var tdee: TDEEEngine.Result? {
        TDEEEngine.compute(intake: store.series["calories"] ?? [],
                           weight: store.series["weight"] ?? [],
                           settings: profileStore.settings,
                           profile: profileStore.profile)
    }

    private var dayProgresses: [DayProgress] {
        ProgressEngine.computeAll(metricIds: profileStore.settings.todayProgressMetricIds,
                                  series: store.series,
                                  rules: profileStore.rules,
                                  tdee: tdee,
                                  profile: profileStore.profile)
    }

    /// Kalori hedefi TDEE'den geliyor ve güven düşükse görsel olarak belli edilir.
    private func lowConfidence(_ dp: DayProgress) -> Bool {
        dp.metricId == "calories" && dp.target?.source == .tdeeEngine && tdee?.confidence == .low
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.lg) {
                    summaryCard
                    if isToday { phaseCard }
                    nutritionBlock
                    if occurrences.isEmpty {
                        EmptyStateView(
                            icon: "calendar.badge.plus",
                            title: "Bu gün için plan yok",
                            guidance: "Plan düzenleyiciden öğün, suplement veya antrenman ekleyebilirsin.",
                            actionTitle: "Plan düzenleyiciyi aç",
                            action: { showEditor = true }
                        )
                        .cardSurface()
                    } else {
                        timeline
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xxl)
            }
            .background(DS.Surface.background)
            .safeAreaInset(edge: .top) { dayNavigator }
            .navigationTitle(isToday ? "Bugün" : day.formatted(.dateTime.weekday(.wide).locale(DS.locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditor = true } label: { Image(systemName: "list.bullet.rectangle") }
                }
            }
            .sheet(isPresented: $showEditor) {
                PlanEditorView().environmentObject(plan)
            }
            .sheet(item: $session) { tmpl in
                WorkoutSessionView(template: tmpl, day: sessionDay).environmentObject(plan)
            }
            .task {
                await notifier.refreshStatus()
                // Beslenme bloğu için gereken metrikler Panel'e girilmeden de yüklensin
                await loadNutritionSeries()
            }
        }
    }

    /// Bugün bloğunun ihtiyaç duyduğu serileri yükler (zaten yüklüyse atlar).
    private func loadNutritionSeries() async {
        let window = max(profileStore.settings.tdeeWindowDays, 30)
        for id in profileStore.settings.todayProgressMetricIds + ["calories", "weight"] {
            await store.ensureLoaded(id, days: window)
        }
    }

    // MARK: Beslenme ilerleme bloğu
    /// Yalnızca bugün görüntülenirken gösterilir: "bugüne kadar" ilerleme, geçmiş
    /// bir günde anlamsız (ProgressEngine bugünü ölçer). Geçmişte gizlenir.
    @ViewBuilder private var nutritionBlock: some View {
        let progresses = dayProgresses
        if isToday && !progresses.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("Bugünün beslenmesi")
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                ForEach(progresses, id: \.metricId) { dp in
                    DayProgressRow(progress: dp, lowConfidence: lowConfidence(dp))
                }
                Text("Hedefler kurallarından, kalori ölçülmüş TDEE'den gelir; yedek katalog değeri açıkça işaretlenir.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    // MARK: Gün gezinme
    private var dayNavigator: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: DS.Touch.minTarget, height: DS.Touch.minTarget)
            }
            .accessibilityLabel("Önceki gün")
            Spacer()
            VStack(spacing: 0) {
                Text((isToday ? "Bugün · " : "") + DS.shortDate(day))
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                if !isToday {
                    Button("Bugüne dön") { day = Calendar.current.startOfDay(for: Date()) }
                        .font(DS.Font.caption)
                } else {
                    Text(day.formatted(.dateTime.weekday(.wide).locale(DS.locale)))
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.secondary)
                }
            }
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: DS.Touch.minTarget, height: DS.Touch.minTarget)
            }
            .accessibilityLabel("Sonraki gün")
        }
        .foregroundStyle(DS.Surface.accent)
        .padding(.horizontal, DS.Space.sm)
        .background(DS.Surface.background)
    }

    private func shift(_ n: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: n, to: day) { day = d }
    }

    // MARK: Günün özeti
    private var summaryCard: some View {
        let total = occurrences.count
        let done = occurrences.filter { plan.status(for: $0) == .done }.count
        let streak = PlanEngine.streak(items: plan.items, logs: plan.logs,
                                       unlockedPhase: plan.unlockedPhase,
                                       phaseEnabled: plan.phaseSettings.enabled)
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Günün özeti")
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                Spacer()
                if plan.phaseSettings.enabled {
                    StatusChip(text: "Faz \(plan.unlockedPhase)", status: DS.Status.info)
                }
            }
            // Rutin ilerleme teal kalır; kırmızıya dönmez (DESIGN.md)
            ThinBar(progress: total > 0 ? Double(done) / Double(total) : 0)
            HStack {
                Text("\(DS.integer(done)) / \(DS.integer(total)) tamamlandı")
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Text.secondary)
                    .monospacedDigit()
                Spacer()
                // Seri var ama ekranın kahramanı değil — üçüncül ve sessiz
                if streak > 0 {
                    Text("Seri: \(DS.integer(streak)) gün")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                }
            }
            if !notifier.authorized && plan.notifSettings.enabled {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "bell.slash")
                    Text("Bildirim izni yok — Ayarlar → Bildirimler")
                }
                .font(DS.Font.caption)
                .foregroundStyle(DS.Status.attention)
            }
        }
        .cardSurface()
    }

    // MARK: Faz durumu (tek değişken kuralı)
    @ViewBuilder private var phaseCard: some View {
        if plan.phaseSettings.enabled {
            let st = PlanEngine.phaseState(items: plan.items, logs: plan.logs,
                                           settings: plan.phaseSettings,
                                           unlockedPhase: plan.unlockedPhase)
            if st.nextPhase != nil {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    HStack {
                        Text("Faz \(st.unlocked)")
                            .font(DS.Font.sectionHeader)
                            .foregroundStyle(DS.Text.primary)
                        Spacer()
                        Text("\(st.daysInCurrent) gün · %\(Int(st.adherenceInCurrent)) uyum")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Text.secondary)
                            .monospacedDigit()
                    }
                    if st.readyToAdvance {
                        Text("Faz \(st.nextPhase ?? 0) açılabilir — yeni bir değişken eklemeye hazırsın.")
                            .font(DS.Font.secondary)
                            .foregroundStyle(DS.Text.primary)
                        Button("Faz \(st.nextPhase ?? 0)'i aç") { plan.advancePhase() }
                            .buttonStyle(.bordered)
                            .tint(DS.Surface.accent)
                            .controlSize(.small)
                    } else {
                        Text(st.daysRemaining > 0
                             ? "Yeni değişken eklemek için \(st.daysRemaining) gün daha: mevcut fazı oturtuyorsun."
                             : "Uyum %\(Int(plan.phaseSettings.minAdherence)) üstüne çıkınca sonraki faz açılır.")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Text.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }

    // MARK: Zaman çizelgesi
    private var timeline: some View {
        VStack(spacing: DS.Space.md) {
            ForEach(occurrences) { occ in
                row(occ)
            }
        }
    }

    private func row(_ occ: PlanOccurrence) -> some View {
        let status = plan.status(for: occ)
        return PlanTimelineRow(
            time: TimeOfDay.from(occ.when).label,
            title: occ.item.title,
            identity: occ.item.category.identity,
            state: rowState(status),
            accessory: rowAccessory(occ),
            onToggle: { cycle(occ, from: status) }
        )
        .contextMenu {
            Button { plan.setStatus(.done, for: occ) } label: { Label("Yaptım", systemImage: "checkmark") }
            Button { plan.setStatus(.skipped, for: occ) } label: { Label("Atladım", systemImage: "minus.circle") }
            if status != nil {
                Button(role: .destructive) { plan.setStatus(nil, for: occ) } label: {
                    Label("İşareti kaldır", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private func rowState(_ s: PlanStatus?) -> PlanItemState {
        switch s {
        case .done:    return .done
        case .skipped: return .skipped
        case nil:      return .upcoming
        }
    }

    /// Tek dokunuş döngüsü: bekliyor → yapıldı → atlandı → bekliyor (DESIGN.md).
    /// Hafif haptik; kesin seçim için satırı basılı tut (context menu).
    private func cycle(_ occ: PlanOccurrence, from status: PlanStatus?) {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch status {
            case nil:       plan.setStatus(.done, for: occ)
            case .done:     plan.setStatus(.skipped, for: occ)
            case .skipped:  plan.setStatus(nil, for: occ)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Satır altı ek bilgi: detay notu, kilit ve antrenman seansı düğmesi
    private func rowAccessory(_ occ: PlanOccurrence) -> (() -> AnyView)? {
        let hasDetail = !occ.item.detail.isEmpty
        let workout = plan.workout(occ.item.workoutTemplateId)
        guard hasDetail || occ.item.locked || workout != nil else { return nil }
        return {
            AnyView(
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    if hasDetail {
                        Text(occ.item.detail)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Text.secondary)
                            .lineLimit(2)
                    }
                    if occ.item.locked {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: "lock.fill")
                            Text(occ.item.lockNote.isEmpty ? "Onay bekliyor" : occ.item.lockNote)
                        }
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Status.attention)
                    }
                    if let w = workout {
                        Button {
                            sessionDay = occ.when
                            session = w
                        } label: {
                            Text("Seans başlat · \(w.exercises.count) hareket")
                                .font(DS.Font.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(DS.Surface.accent)
                        .controlSize(.small)
                    }
                }
            )
        }
    }
}

// MARK: - Günlük hedef ilerleme satırı
/// Yön-duyarlı ilerleme satırı: metrik adı, bugün/hedef, çubuk, kalan miktar, kaynak.
/// Renk dili DESIGN.md'ye uyar: kırmızı yok; tavan aşımı turuncu (dikkat),
/// atMost dolumu teal "başarı" gibi görünmez, hedefe ulaşma sakin teal.
private struct DayProgressRow: View {
    let progress: DayProgress
    var lowConfidence: Bool = false

    private var def: MetricDef? { HealthMetricCatalog.byId(progress.metricId) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(def?.title ?? progress.metricId)
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Text.primary)
                Spacer()
                valueLabel
            }
            ThinBar(progress: barFill, tint: barTint)
            HStack(alignment: .firstTextBaseline) {
                Text(remainingText)
                    .font(DS.Font.caption)
                    .foregroundStyle(progress.state == .overTarget ? DS.Status.attention : DS.Text.secondary)
                Spacer()
                Text(sourceText)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, DS.Space.xs)
    }

    // MARK: bugün / hedef
    private var valueLabel: some View {
        HStack(spacing: DS.Space.xs) {
            Text(fmt(progress.today))
                .foregroundStyle(DS.Text.primary)
            if let t = progress.target {
                if lowConfidence {
                    // Düşük güven güven dilbilgisiyle: ince ağırlık + kesikli alt çizgi (DESIGN.md §2).
                    ConfidenceText(text: "/ \(targetLabel(t))",
                                   confidence: .low,
                                   font: DS.Font.numericCaption,
                                   color: DS.Text.secondary)
                } else {
                    Text("/ \(targetLabel(t))")
                        .foregroundStyle(DS.Text.secondary)
                }
            } else {
                Text(def?.unit ?? "")
                    .foregroundStyle(DS.Text.tertiary)
            }
        }
        .font(DS.Font.numericCaption)
    }

    // MARK: çubuk dolumu ve rengi
    private var barFill: Double {
        guard let t = progress.target else { return 0 }
        switch t.direction {
        case .between:
            let u = t.upperValue ?? t.value
            return u > 0 ? progress.today / u : 0
        default:
            return t.value > 0 ? progress.today / t.value : 0
        }
    }

    private var barTint: Color {
        guard let t = progress.target else { return DS.Text.tertiary }
        switch t.direction {
        case .atLeast:
            // Hedefe doğru dolmak iyi — sakin teal.
            return DS.Surface.accent
        case .atMost:
            // Bütçe: nötr dolum; aşınca turuncu. Teal "başarı" hissi verilmez.
            return progress.state == .overTarget ? DS.Status.attention : DS.Text.secondary
        case .between:
            switch progress.state {
            case .overTarget: return DS.Status.attention
            case .atTarget:   return DS.Surface.accent
            default:          return DS.Text.tertiary
            }
        }
    }

    // MARK: kalan miktar metni (yöne göre)
    private var remainingText: String {
        guard let t = progress.target else { return "hedef yok" }
        let r = progress.remaining
        switch t.direction {
        case .atLeast:
            return progress.state == .atTarget ? "hedefe ulaşıldı" : "\(fmt(r)) \(t.unit) kaldı"
        case .atMost:
            return progress.state == .overTarget
                ? "\(fmt(abs(r))) \(t.unit) aşıldı"
                : "\(fmt(r)) \(t.unit) bütçe kaldı"
        case .between:
            switch progress.state {
            case .belowTarget: return "banda \(fmt(r)) \(t.unit) var"
            case .overTarget:  return "\(fmt(abs(r))) \(t.unit) fazla"
            default:           return "bant içinde"
            }
        }
    }

    // MARK: kaynak işareti (+ türetme notu + düşük güven)
    private var sourceText: String {
        guard let t = progress.target else { return "hedef yok" }
        var parts: [String] = []
        switch t.source {
        case .guardrailRule: parts.append("kuralın")
        case .tdeeEngine:    parts.append("TDEE")
        case .catalog:       parts.append("yedek")
        case .none:          break
        }
        if let note = t.derivedNote { parts.append(note) }
        if lowConfidence { parts.append("düşük güven") }
        return parts.joined(separator: " · ")
    }

    // MARK: biçimlendirme
    private func fmt(_ v: Double) -> String {
        let u = progress.target?.unit ?? def?.unit ?? ""
        if u == "kcal" || u == "mg" || u == "µg" || u == "adım" {
            return DS.integer(Int(v.rounded()))
        }
        return v < 10 ? DS.decimal(v) : DS.integer(Int(v.rounded()))
    }

    private func targetLabel(_ t: TargetEngine.ResolvedTarget) -> String {
        if t.direction == .between, let u = t.upperValue {
            return "\(fmt(t.value))–\(fmt(u)) \(t.unit)"
        }
        return "\(t.direction.symbol) \(fmt(t.value)) \(t.unit)"
    }
}
