import SwiftUI

// MARK: - Seans (log girme)
// Hız öncelikli form (DESIGN.md, görsel 06): 56 pt hedefli BigStepper'lar,
// "Seti Kaydet", camlı dinlenme çubuğu (glassEffect SADECE bu işlevsel katmanda).
struct WorkoutSessionView: View {
    @EnvironmentObject var plan: PlanStore
    @Environment(\.dismiss) var dismiss
    let template: WorkoutTemplate
    let day: Date

    @State private var log: WorkoutLog = WorkoutLog(templateId: UUID(), day: Date())
    @State private var loaded = false

    /// Şu an düzenlenen set (BigStepper'lar bunu besler)
    private struct ActiveSet: Equatable { let exerciseId: UUID; let index: Int }
    @State private var active: ActiveSet?
    @State private var editWeight: Double = 0
    @State private var editReps: Int = 8

    @State private var restRemaining: Int?   // saniye; nil → çubuk gizli
    private let restTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.lg) {
                    if !template.note.isEmpty {
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: "exclamationmark.shield")
                            Text(template.note)
                        }
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Status.attention)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(padding: DS.Space.md)
                    }
                    ForEach(template.exercises) { ex in
                        exerciseCard(ex)
                    }
                    summaryCard
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, 120)   // yüzen çubuk için alan
            }
            .background(DS.Surface.background)
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Seansı bitir") {
                        log.completedAt = Date()
                        plan.saveWorkoutLog(log)
                        dismiss()
                    }.bold()
                }
            }
            .safeAreaInset(edge: .bottom) { restBar }
            .onReceive(restTimer) { _ in
                guard let r = restRemaining else { return }
                if r <= 1 { restRemaining = nil } else { restRemaining = r - 1 }
            }
            .onAppear(perform: loadLog)
        }
    }

    // MARK: Egzersiz kartı

    private func exerciseCard(_ ex: Exercise) -> some View {
        let key = ex.id.uuidString
        let sets = log.entries[key] ?? []
        let doneCount = sets.filter { $0.done }.count
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: IdentityColor.workout.symbolName)
                    .foregroundStyle(IdentityColor.workout.color)
                Text(ex.name)
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                IdentityChip(text: "Set \(min(doneCount + 1, ex.sets)) / \(ex.sets)", identity: .workout)
            }
            Text(targetLine(ex))
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.secondary)

            // Set satırları — dokununca o set düzenlemeye alınır
            VStack(spacing: 0) {
                ForEach(0..<ex.sets, id: \.self) { i in
                    setRow(ex, index: i, sets: sets)
                    if i < ex.sets - 1 { Divider().overlay(DS.Surface.divider) }
                }
            }

            // Aktif set bu egzersizdeyse: büyük stepper'lar + kaydet
            if let a = active, a.exerciseId == ex.id {
                VStack(spacing: DS.Space.lg) {
                    Divider().overlay(DS.Surface.divider)
                    BigStepper(
                        label: "Ağırlık",
                        valueText: "\(WorkoutSessionView.numText(editWeight)) kg",
                        onDecrement: { editWeight = max(0, editWeight - 2.5) },
                        onIncrement: { editWeight += 2.5 }
                    )
                    BigStepper(
                        label: "Tekrar",
                        valueText: DS.integer(editReps),
                        onDecrement: { editReps = max(1, editReps - 1) },
                        onIncrement: { editReps += 1 }
                    )
                    Button {
                        saveActiveSet(ex)
                    } label: {
                        Text("Seti Kaydet")
                            .font(DS.Font.heading)
                            .frame(maxWidth: .infinity, minHeight: DS.Touch.comfortable)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Surface.accent)
                }
            }

            footnotes(ex)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func setRow(_ ex: Exercise, index i: Int, sets: [SetLog]) -> some View {
        let s = i < sets.count ? sets[i] : SetLog(setIndex: i)
        let isActive = active == ActiveSet(exerciseId: ex.id, index: i)
        return Button {
            activate(ex, index: i)
        } label: {
            HStack(spacing: DS.Space.md) {
                Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(s.done ? DS.Surface.accent : DS.Surface.divider)
                Text("Set \(i + 1)")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Text.primary)
                Spacer()
                if let w = s.weight, let r = s.reps {
                    Text("\(WorkoutSessionView.numText(w)) kg × \(DS.integer(r))")
                        .font(DS.Font.numericCaption)
                        .foregroundStyle(DS.Text.secondary)
                } else {
                    Text(isActive ? "giriliyor…" : "—")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                }
            }
            .padding(.vertical, DS.Space.sm)
            .frame(minHeight: DS.Touch.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? DS.Surface.accent.opacity(0.06) : .clear)
    }

    @ViewBuilder
    private func footnotes(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if !ex.note.isEmpty {
                Text(ex.note).font(DS.Font.caption).foregroundStyle(DS.Text.tertiary)
            }
            if !ex.progression.isEmpty {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "arrow.up.right")
                    Text(ex.progression)
                }
                .font(DS.Font.caption).foregroundStyle(DS.Status.positive)
            }
            if let last = plan.lastSets(templateId: template.id, exerciseId: ex.id, before: day),
               !last.isEmpty {
                Text("Geçen sefer: " + last.compactMap { s -> String? in
                    guard let w = s.weight, let r = s.reps else { return nil }
                    return "\(Int(w))×\(r)"
                }.joined(separator: ", "))
                .font(DS.Font.caption).foregroundStyle(DS.Surface.accent)
            }
        }
    }

    private func targetLine(_ ex: Exercise) -> String {
        var parts = ["Hedef: \(ex.sets) set × \(ex.reps) tekrar"]
        if let rpe = ex.targetRPE { parts.append("RPE \(WorkoutSessionView.numText(rpe))") }
        parts.append("\(ex.restSeconds) sn dinlenme")
        return parts.joined(separator: " · ")
    }

    // MARK: Seans özeti

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            TextField("Seans notu", text: $log.note, axis: .vertical)
                .lineLimit(1...3)
                .font(DS.Font.body)
            Divider().overlay(DS.Surface.divider)
            HStack {
                Text("Toplam hacim")
                    .font(DS.Font.secondary).foregroundStyle(DS.Text.secondary)
                Spacer()
                Text("\(DS.integer(Int(log.totalVolume))) kg")
                    .font(DS.Font.numericCaption).foregroundStyle(DS.Text.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: Aktif set akışı

    /// Bir seti düzenlemeye al; stepper değerlerini mevcut kayıttan,
    /// yoksa geçen seferden, o da yoksa önceki setten tohumla.
    private func activate(_ ex: Exercise, index i: Int) {
        ensure(ex.id.uuidString, ex.sets)
        let sets = log.entries[ex.id.uuidString] ?? []
        let s = i < sets.count ? sets[i] : SetLog(setIndex: i)
        let lastTime = plan.lastSets(templateId: template.id, exerciseId: ex.id, before: day)
        editWeight = s.weight
            ?? (i > 0 ? sets[i - 1].weight : nil)
            ?? lastTime?.first(where: { $0.setIndex == i })?.weight
            ?? lastTime?.first?.weight
            ?? 0
        editReps = s.reps
            ?? lastTime?.first(where: { $0.setIndex == i })?.reps
            ?? Int(ex.reps.prefix(while: { $0.isNumber }))
            ?? 8
        withAnimation(.easeInOut(duration: 0.15)) {
            active = ActiveSet(exerciseId: ex.id, index: i)
        }
    }

    /// Onay sakindir: satır güncellenir, dinlenme sayacı belirir, konfeti yağmaz.
    private func saveActiveSet(_ ex: Exercise) {
        guard let a = active, a.exerciseId == ex.id else { return }
        let key = ex.id.uuidString
        ensure(key, ex.sets)
        guard var arr = log.entries[key], arr.indices.contains(a.index) else { return }
        arr[a.index].weight = editWeight
        arr[a.index].reps = editReps
        arr[a.index].done = true
        log.entries[key] = arr

        withAnimation(.easeInOut(duration: 0.15)) {
            restRemaining = ex.restSeconds
            // Sıradaki tamamlanmamış sete geç (varsa)
            if let next = (0..<ex.sets).first(where: { !(arr[$0].done) }) {
                activate(ex, index: next)
            } else {
                active = nil
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func numText(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
    static func parseDouble(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    private func ensure(_ key: String, _ count: Int) {
        if log.entries[key] == nil || (log.entries[key]?.count ?? 0) < count {
            var arr = log.entries[key] ?? []
            while arr.count < count { arr.append(SetLog(setIndex: arr.count)) }
            log.entries[key] = arr
        }
    }

    private func loadLog() {
        guard !loaded else { return }
        loaded = true
        log = plan.log(for: template.id, on: day)
            ?? WorkoutLog(templateId: template.id, day: Calendar.current.startOfDay(for: day))
        // İlk tamamlanmamış seti hazırla
        if let first = template.exercises.first {
            ensure(first.id.uuidString, first.sets)
            let sets = log.entries[first.id.uuidString] ?? []
            let idx = (0..<first.sets).first(where: { i in !(i < sets.count && sets[i].done) }) ?? 0
            activate(first, index: idx)
        }
    }

    // MARK: Dinlenme sayacı — cam efekti SADECE burada (işlevsel katman)

    @ViewBuilder
    private var restBar: some View {
        if let remaining = restRemaining, remaining > 0 {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "timer")
                    .foregroundStyle(DS.Surface.accent)
                Text("Dinlenme: \(String(format: "%d:%02d", remaining / 60, remaining % 60))")
                    .font(DS.Font.numericCaption)
                    .foregroundStyle(DS.Text.primary)
                    .monospacedDigit()
                Spacer()
                Button("+30 sn") { restRemaining = remaining + 30 }
                    .font(DS.Font.caption)
                    .buttonStyle(.bordered)
                    .tint(DS.Surface.accent)
                Button("Atla") { restRemaining = nil }
                    .font(DS.Font.caption)
                    .buttonStyle(.bordered)
                    .tint(DS.Text.secondary)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
            .glassEffect(.regular, in: Capsule())   // iOS 26 Liquid Glass — işlevsel katman
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.sm)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Şablon listesi
struct WorkoutListView: View {
    @EnvironmentObject var plan: PlanStore
    @Environment(\.dismiss) var dismiss
    @State private var editing: WorkoutTemplate?

    var body: some View {
        NavigationStack {
            List {
                ForEach(plan.workouts) { w in
                    Button { editing = w } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(.subheadline.bold())
                            Text("\(w.focus) · \(w.exercises.count) hareket · ~\(w.estimatedMinutes) dk")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Section {
                    Button {
                        editing = WorkoutTemplate(name: "Yeni şablon")
                    } label: { Label("Yeni şablon", systemImage: "plus.circle") }
                }
            }
            .navigationTitle("Antrenman Şablonları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
            .sheet(item: $editing) { w in
                WorkoutEditorView(template: w) { plan.updateWorkout($0) }
            }
        }
    }
}

// MARK: - Şablon düzenleyici
struct WorkoutEditorView: View {
    @Environment(\.dismiss) var dismiss
    @State var template: WorkoutTemplate
    let onSave: (WorkoutTemplate) -> Void
    @State private var editingExercise: Exercise?

    var body: some View {
        NavigationStack {
            Form {
                Section("Şablon") {
                    TextField("Ad", text: $template.name)
                    TextField("Odak", text: $template.focus)
                    Stepper("Süre: ~\(template.estimatedMinutes) dk", value: $template.estimatedMinutes, in: 15...120, step: 5)
                    TextField("Güvenlik / genel not", text: $template.note, axis: .vertical).lineLimit(1...3)
                }
                Section("Hareketler") {
                    ForEach(template.exercises) { ex in
                        Button { editingExercise = ex } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).font(.subheadline)
                                Text("\(ex.sets)×\(ex.reps) · \(ex.restSeconds) sn dinlenme")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { template.exercises.remove(atOffsets: $0) }
                    .onMove { template.exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        editingExercise = Exercise(name: "Yeni hareket")
                    } label: { Label("Hareket ekle", systemImage: "plus.circle") }
                }
            }
            .navigationTitle("Şablon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") { onSave(template); dismiss() }.bold()
                }
            }
            .sheet(item: $editingExercise) { ex in
                ExerciseForm(exercise: ex) { updated in
                    if let i = template.exercises.firstIndex(where: { $0.id == updated.id }) {
                        template.exercises[i] = updated
                    } else {
                        template.exercises.append(updated)
                    }
                }
            }
        }
    }
}

// MARK: - Hareket formu
struct ExerciseForm: View {
    @Environment(\.dismiss) var dismiss
    @State var exercise: Exercise
    let onSave: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Hareket") {
                    TextField("Ad", text: $exercise.name)
                    Stepper("Set: \(exercise.sets)", value: $exercise.sets, in: 1...10)
                    TextField("Tekrar (ör. 8-10)", text: $exercise.reps)
                    HStack {
                        Text("Hedef RPE")
                        Spacer()
                        TextField("7", text: Binding(
                            get: { exercise.targetRPE.map { WorkoutSessionView.numText($0) } ?? "" },
                            set: { exercise.targetRPE = WorkoutSessionView.parseDouble($0) }))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60)
                    }
                    Stepper("Dinlenme: \(exercise.restSeconds) sn", value: $exercise.restSeconds, in: 30...240, step: 15)
                    TextField("Tempo (opsiyonel)", text: $exercise.tempo)
                }
                Section("Notlar") {
                    TextField("Teknik notu", text: $exercise.note, axis: .vertical).lineLimit(1...3)
                    TextField("İlerleme kuralı", text: $exercise.progression, axis: .vertical).lineLimit(1...3)
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") { onSave(exercise); dismiss() }.bold()
                }
            }
        }
    }
}
