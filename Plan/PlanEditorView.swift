import SwiftUI

struct PlanEditorView: View {
    @EnvironmentObject var plan: PlanStore
    @Environment(\.dismiss) var dismiss
    @State private var editing: PlanItem?
    @State private var newItem: PlanItem?
    @State private var showWorkouts = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(PlanCategory.allCases) { cat in
                    let list = plan.items.filter { $0.category == cat }
                    if !list.isEmpty {
                        Section {
                            ForEach(list) { item in
                                Button { editing = item } label: { row(item) }
                                    .buttonStyle(.plain)
                            }
                            .onDelete { plan.delete(at: $0, in: cat) }
                        } header: {
                            Label(cat.label, systemImage: cat.icon)
                        }
                    }
                }

                Section {
                    Button { showWorkouts = true } label: {
                        Label("Antrenman şablonları", systemImage: "figure.strengthtraining.traditional")
                    }
                    Button(role: .destructive) { plan.resetPlan() } label: {
                        Label("Planı başlangıç setine döndür", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newItem = PlanItem(title: "Yeni öğe", category: .supplement,
                                                times: [TimeOfDay(hour: 9, minute: 0)]) } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } }
            }
            .sheet(item: $editing) { item in
                PlanItemForm(item: item, workouts: plan.workouts, allItems: plan.items) { plan.update($0) }
            }
            .sheet(item: $newItem) { item in
                PlanItemForm(item: item, workouts: plan.workouts, allItems: plan.items) { plan.add($0) }
            }
            .sheet(isPresented: $showWorkouts) {
                WorkoutListView().environmentObject(plan)
            }
        }
    }

    private func row(_ item: PlanItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title).font(.subheadline.bold())
                        .foregroundStyle(item.enabled ? .primary : .secondary)
                    if item.phase > 1 {
                        Text("F\(item.phase)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                    if item.locked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange) }
                }
                Text("\(item.schedule.label) · \(item.times.map { $0.label }.joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: item.notify ? "bell.fill" : "bell.slash")
                .font(.caption2)
                .foregroundStyle(item.notify ? .blue : Color.secondary.opacity(0.4))
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Öğe formu
struct PlanItemForm: View {
    @Environment(\.dismiss) var dismiss
    @State var item: PlanItem
    let workouts: [WorkoutTemplate]
    let allItems: [PlanItem]
    let onSave: (PlanItem) -> Void

    @State private var scheduleType = 0        // 0 günlük 1 haftanın günleri 2 N günde bir 3 tek sefer 4 göreli
    @State private var weekdays: Set<Int> = []
    @State private var everyN = 2
    @State private var oneOffDate = Date()
    @State private var anchorId: UUID?
    @State private var offsetDays = -3
    @State private var hasEnd = false
    @State private var endDate = Date()

    private let dayNames = [(1, "Paz"), (2, "Pzt"), (3, "Sal"), (4, "Çar"), (5, "Per"), (6, "Cum"), (7, "Cmt")]
    private var anchorCandidates: [PlanItem] {
        allItems.filter { if case .oneOff = $0.schedule { return true } else { return false } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tanım") {
                    TextField("Başlık", text: $item.title)
                    TextField("Detay (doz / miktar / açıklama)", text: $item.detail, axis: .vertical)
                        .lineLimit(1...3)
                    Picker("Kategori", selection: $item.category) {
                        ForEach(PlanCategory.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    Toggle("Etkin", isOn: $item.enabled)
                }

                Section("Zamanlama") {
                    Picker("Tekrar", selection: $scheduleType) {
                        Text("Her gün").tag(0)
                        Text("Haftanın günleri").tag(1)
                        Text("N günde bir").tag(2)
                        Text("Tek sefer").tag(3)
                        Text("Bir tarihe göreli").tag(4)
                    }
                    switch scheduleType {
                    case 1:
                        HStack(spacing: 6) {
                            ForEach(dayNames, id: \.0) { (num, name) in
                                Button {
                                    if weekdays.contains(num) { weekdays.remove(num) } else { weekdays.insert(num) }
                                } label: {
                                    Text(name).font(.caption2)
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .background(weekdays.contains(num) ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground),
                                                    in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    case 2:
                        Stepper("Her \(everyN) günde bir", value: $everyN, in: 2...30)
                    case 3:
                        DatePicker("Tarih", selection: $oneOffDate, displayedComponents: .date)
                    case 4:
                        if anchorCandidates.isEmpty {
                            Text("Önce tek seferlik bir öğe oluştur (ör. \"Kan testi\"), sonra buraya bağla.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Picker("Bağlı olduğu", selection: Binding(
                                get: { anchorId ?? anchorCandidates.first?.id },
                                set: { anchorId = $0 })) {
                                ForEach(anchorCandidates) { Text($0.title).tag(Optional($0.id)) }
                            }
                            Stepper(offsetDays < 0 ? "\(-offsetDays) gün önce" : "\(offsetDays) gün sonra",
                                    value: $offsetDays, in: -30...30)
                        }
                    default:
                        EmptyView()
                    }
                }

                Section("Saatler") {
                    ForEach(Array(item.times.enumerated()), id: \.offset) { idx, _ in
                        DatePicker("Saat \(idx + 1)", selection: Binding(
                            get: { item.times[idx].date(on: Date()) },
                            set: { item.times[idx] = TimeOfDay.from($0) }),
                            displayedComponents: .hourAndMinute)
                    }
                    .onDelete { item.times.remove(atOffsets: $0) }
                    Button { item.times.append(TimeOfDay(hour: 12, minute: 0)) } label: {
                        Label("Saat ekle", systemImage: "plus.circle")
                    }
                }

                Section("Bildirim") {
                    Toggle("Bildirim gönder", isOn: $item.notify)
                    if item.notify {
                        Stepper("Kaç dk önce: \(item.leadMinutes)", value: $item.leadMinutes, in: 0...120, step: 5)
                    }
                    Toggle("Kilitli (onay bekliyor)", isOn: $item.locked)
                    if item.locked {
                        TextField("Kilit nedeni", text: $item.lockNote)
                        Text("Kilitli öğeler planda görünür ama bildirim üretmez.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section("Süre ve faz") {
                    Stepper("Faz: \(item.phase)", value: $item.phase, in: 1...6)
                    Text("Faz 1 hemen başlar. Üst fazlar, önceki faz yeterince sürdürülünce açılır (tek değişken kuralı).")
                        .font(.caption2).foregroundStyle(.secondary)
                    Toggle("Bitiş tarihi var", isOn: $hasEnd)
                    if hasEnd { DatePicker("Bitiş", selection: $endDate, displayedComponents: .date) }
                }

                if item.category == .training {
                    Section("Antrenman şablonu") {
                        Picker("Şablon", selection: Binding(
                            get: { item.workoutTemplateId },
                            set: { item.workoutTemplateId = $0 })) {
                            Text("Yok").tag(Optional<UUID>.none)
                            ForEach(workouts) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }

                Section("Not") {
                    TextField("Serbest not", text: $item.note, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Kaydet") { save() }.bold() }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        switch item.schedule {
        case .daily: scheduleType = 0
        case .weekdays(let d): scheduleType = 1; weekdays = Set(d)
        case .everyNDays(let n): scheduleType = 2; everyN = n
        case .oneOff(let d): scheduleType = 3; oneOffDate = d
        case .relativeTo(let a, let o): scheduleType = 4; anchorId = a; offsetDays = o
        }
        if let e = item.endDate { hasEnd = true; endDate = e }
    }

    private func save() {
        switch scheduleType {
        case 1: item.schedule = .weekdays(Array(weekdays).sorted())
        case 2: item.schedule = .everyNDays(everyN)
        case 3: item.schedule = .oneOff(oneOffDate)
        case 4:
            if let a = anchorId ?? anchorCandidates.first?.id {
                item.schedule = .relativeTo(anchorId: a, offsetDays: offsetDays)
            }
        default: item.schedule = .daily
        }
        item.endDate = hasEnd ? endDate : nil
        item.times.sort()
        onSave(item)
        dismiss()
    }
}
