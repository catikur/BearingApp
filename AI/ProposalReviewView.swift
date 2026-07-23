import SwiftUI

/// LLM önerisini gösterir, deterministik doğrulama sonuçlarını listeler ve
/// yalnızca kullanıcının SEÇTİĞİ öğeleri plana yazar. Hiçbir şey otomatik uygulanmaz.
struct ProposalReviewView: View {
    @EnvironmentObject var plan: PlanStore
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss

    let proposal: AIProposal
    let raw: String
    let tdee: TDEEEngine.Result?

    @State private var selected: Set<UUID> = []
    @State private var selectedWorkouts: Set<UUID> = []
    @State private var showRaw = false
    @State private var applied = false

    private var issues: [ProposalValidator.Issue] {
        ProposalValidator.validate(proposal,
                                   rules: profileStore.rules,
                                   tdee: tdee,
                                   profile: profileStore.profile,
                                   context: profileStore.context,
                                   notifSettings: plan.notifSettings,
                                   phaseSettings: plan.phaseSettings,
                                   existingItems: plan.items)
    }
    private var blockers: [ProposalValidator.Issue] { issues.filter { $0.severity == .blocker } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    summaryCard
                    if !issues.isEmpty { issuesSection }
                    if let t = proposal.targets { targetsSection(t) }
                    if !proposal.items.isEmpty { itemsSection }
                    if !proposal.workoutChanges.isEmpty { workoutSection }
                    if !proposal.warnings.isEmpty { modelWarnings }
                    applyButton
                }
                .padding(DS.Space.lg)
            }
            .background(DS.Surface.background)
            .navigationTitle("Öneri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showRaw = true } label: { Label("Ham yanıtı gör", systemImage: "curlybraces") }
                        Button { selected = Set(proposal.items.map { $0.id }) } label: {
                            Label("Tümünü seç", systemImage: "checkmark.circle")
                        }
                        Button { selected.removeAll(); selectedWorkouts.removeAll() } label: {
                            Label("Seçimi temizle", systemImage: "circle")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } }
            }
            .sheet(isPresented: $showRaw) { ContextPreview(text: raw) }
        }
    }

    // MARK: Özet
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if !proposal.summary.isEmpty {
                Text(proposal.summary)
                    .font(DS.Font.body.weight(.semibold))
                    .foregroundStyle(DS.Text.primary)
            }
            if !proposal.rationale.isEmpty {
                Text(proposal.rationale)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
            }
            Label("Öneri plana yazılmadı. Aşağıdan seçtiklerin uygulanır.",
                  systemImage: "hand.raised")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Surface.accent)
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.accent.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    // MARK: Doğrulama
    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Motor doğrulaması")
                .font(DS.Font.heading)
                .foregroundStyle(DS.Text.primary)
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: DS.Space.sm) {
                    Image(systemName: icon(issue.severity))
                        .font(DS.Font.caption).foregroundStyle(color(issue.severity))
                    Text(issue.text)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.primary)
                    Spacer(minLength: 0)
                }
            }
            if !blockers.isEmpty {
                Text("Kırmızı maddeler, önerinin senin kurallarınla veya motorun hesabıyla çeliştiğini gösterir. Yine de uygulayabilirsin ama bilerek yap.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func icon(_ s: ProposalValidator.Severity) -> String {
        switch s {
        case .blocker: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle"
        }
    }
    // blocker → kritik kırmızı: DESIGN.md'de kırmızının izinli olduğu iki bağlamdan biri.
    private func color(_ s: ProposalValidator.Severity) -> Color {
        switch s {
        case .blocker: return DS.Status.critical
        case .warning: return DS.Status.attention
        case .info:    return DS.Text.secondary
        }
    }

    // MARK: Hedefler
    private func targetsSection(_ t: ProposedTargets) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Önerilen hedefler")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Text.primary)
            row("Kalori", t.kcal, "kcal", engine: tdee?.recommendedIntake)
            row("Protein", t.proteinG, "g")
            row("Karbonhidrat", t.carbG, "g")
            row("Yağ", t.fatG, "g")
            row("Doymuş yağ", t.satFatPctEnergy, "% enerji")
            row("Sodyum", t.sodiumMg, "mg")
            row("Lif", t.fiberG, "g")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder private func row(_ l: String, _ v: Double?, _ unit: String, engine: Double? = nil) -> some View {
        if let v, v > 0 {
            HStack {
                Text(l)
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Text.secondary)
                Spacer()
                if let e = engine {
                    Text("motor: \(DS.integer(Int(e.rounded())))")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                        .monospacedDigit()
                }
                Text("\(DS.integer(Int(v.rounded()))) \(unit)")
                    .font(DS.Font.secondary.weight(.semibold))
                    .foregroundStyle(DS.Text.primary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: Öğeler
    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text("Plan değişiklikleri")
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                Spacer()
                Text("\(DS.integer(selected.count))/\(DS.integer(proposal.items.count)) seçili")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
                    .monospacedDigit()
            }
            ForEach(proposal.items) { item in
                Button {
                    if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                } label: {
                    HStack(alignment: .top, spacing: DS.Space.md) {
                        Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(item.id) ? DS.Status.positive : DS.Text.tertiary)
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            HStack(spacing: DS.Space.xs) {
                                Image(systemName: item.planCategory.icon)
                                    .font(DS.Font.caption).foregroundStyle(item.planCategory.color)
                                Text(item.title)
                                    .font(DS.Font.body.weight(.semibold))
                                    .foregroundStyle(DS.Text.primary)
                                Text(actionLabel(item.action))
                                    .font(DS.Font.caption.weight(.bold))
                                    .padding(.horizontal, DS.Space.xs).padding(.vertical, 2)
                                    .background(DS.Surface.divider, in: Capsule())
                                    .foregroundStyle(DS.Text.secondary)
                            }
                            if !item.detail.isEmpty {
                                Text(item.detail).font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
                            }
                            Text("\(item.scheduleParsed.label) · \(item.timesParsed.map { $0.label }.joined(separator: ", "))")
                                .font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
                            if !item.note.isEmpty {
                                Text(item.note).font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, DS.Space.xs)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func actionLabel(_ a: String) -> String {
        switch a {
        case "update":  return "GÜNCELLE"
        case "disable": return "KAPAT"
        default:        return "YENİ"
        }
    }

    // MARK: Antrenman değişiklikleri
    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Antrenman değişiklikleri")
                .font(DS.Font.heading)
                .foregroundStyle(DS.Text.primary)
            ForEach(proposal.workoutChanges) { w in
                Button {
                    if selectedWorkouts.contains(w.id) { selectedWorkouts.remove(w.id) }
                    else { selectedWorkouts.insert(w.id) }
                } label: {
                    HStack(alignment: .top, spacing: DS.Space.md) {
                        Image(systemName: selectedWorkouts.contains(w.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedWorkouts.contains(w.id) ? DS.Status.positive : DS.Text.tertiary)
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text(w.templateName)
                                .font(DS.Font.body.weight(.semibold))
                                .foregroundStyle(DS.Text.primary)
                            ForEach(Array(w.exercises.enumerated()), id: \.offset) { _, ex in
                                Text("• \(ex.name) — \(ex.sets ?? 3)×\(ex.reps ?? "8-10")\(ex.targetRPE.map { " RPE \(DS.integer(Int($0.rounded())))" } ?? "")")
                                    .font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
                            }
                            if !w.note.isEmpty {
                                Text(w.note).font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, DS.Space.xs)
                }
                .buttonStyle(.plain)
                Divider()
            }
            Text("Şablon değişikliği mevcut hareket listesinin yerine geçer — uygulamadan önce şablonu kontrol et.")
                .font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var modelWarnings: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Modelin kendi uyarıları")
                .font(DS.Font.heading)
                .foregroundStyle(DS.Text.primary)
            ForEach(Array(proposal.warnings.enumerated()), id: \.offset) { _, w in
                Label(w, systemImage: "quote.opening")
                    .font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: Uygula
    private var applyButton: some View {
        VStack(spacing: DS.Space.sm) {
            Button {
                apply()
            } label: {
                Label(applied ? "Uygulandı" : "Seçilenleri plana uygula",
                      systemImage: applied ? "checkmark" : "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Surface.accent)
            .disabled(applied || (selected.isEmpty && selectedWorkouts.isEmpty))

            if !blockers.isEmpty && !applied {
                Text("\(DS.integer(blockers.count)) engelleyici uyarı var — yine de uygulayabilirsin, karar senin.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Status.critical)
            }
            Text("Yeni öğeler bildirimi KAPALI gelir. Planda görüp saatini ayarladıktan sonra açarsın.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)
        }
    }

    private func apply() {
        for item in proposal.items where selected.contains(item.id) {
            switch item.action {
            case "update":
                if let existing = plan.items.first(where: { $0.title.lowercased() == item.title.lowercased() }) {
                    var updated = existing
                    updated.detail = item.detail
                    updated.schedule = item.scheduleParsed
                    if !item.timesParsed.isEmpty { updated.times = item.timesParsed }
                    updated.note = item.note
                    plan.update(updated)
                } else {
                    plan.add(item.toPlanItem())
                }
            case "disable":
                if var existing = plan.items.first(where: { $0.title.lowercased() == item.title.lowercased() }) {
                    existing.enabled = false
                    plan.update(existing)
                }
            default:
                plan.add(item.toPlanItem())
            }
        }

        for w in proposal.workoutChanges where selectedWorkouts.contains(w.id) {
            if var tmpl = plan.workouts.first(where: { $0.name.lowercased() == w.templateName.lowercased() }) {
                if !w.exercises.isEmpty { tmpl.exercises = w.exercises.map { $0.toExercise() } }
                if !w.note.isEmpty { tmpl.note = w.note }
                plan.updateWorkout(tmpl)
            } else if !w.exercises.isEmpty {
                plan.updateWorkout(WorkoutTemplate(name: w.templateName,
                                                   exercises: w.exercises.map { $0.toExercise() },
                                                   note: w.note))
            }
        }
        applied = true
    }
}
