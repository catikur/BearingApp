import SwiftUI

struct RuleEditorView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss
    @State private var editing: GuardrailRule?
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(profileStore.rules) { rule in
                        Button { editing = rule } label: { row(rule) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { profileStore.deleteRules(at: $0) }
                    .onMove { profileStore.moveRules(from: $0, to: $1) }
                } footer: {
                    Text("Kurallar tamamen senin. Sürükleyerek sırala, kaydırarak sil.")
                }

                Section {
                    Button { showNew = true } label: { Label("Yeni kural", systemImage: "plus.circle") }
                    Button(role: .destructive) { profileStore.resetRules() } label: {
                        Label("Başlangıç setine dön", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Kurallar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } }
            }
            .sheet(item: $editing) { rule in
                RuleFormView(rule: rule) { profileStore.updateRule($0) }
            }
            .sheet(isPresented: $showNew) {
                RuleFormView(rule: GuardrailRule(name: "Yeni kural", targetId: "protein", value: 100)) {
                    profileStore.addRule($0)
                }
            }
        }
    }

    private func row(_ rule: GuardrailRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.summary()).font(.subheadline.bold())
                    .foregroundStyle(rule.enabled ? .primary : .secondary)
                HStack(spacing: 6) {
                    Text(rule.kind.label).font(.caption2).foregroundStyle(.secondary)
                    Text("ağırlık \(String(format: "%.1f", rule.weight))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if !rule.enabled {
                Text("kapalı").font(.caption2).foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// Tek bir kuralın formu
struct RuleFormView: View {
    @Environment(\.dismiss) var dismiss
    @State var rule: GuardrailRule
    let onSave: (GuardrailRule) -> Void

    private var metricOptions: [MetricDef] {
        HealthMetricCatalog.all.filter { $0.source == .healthKit }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tanım") {
                    TextField("Kural adı", text: $rule.name)
                    Picker("Tip", selection: $rule.kind) {
                        ForEach(RuleKind.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Etkin", isOn: $rule.enabled)
                }

                Section("Hedef") {
                    if rule.kind == .planAdherence {
                        Picker("Plan kategorisi", selection: $rule.targetId) {
                            ForEach(PlanCategory.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        Text("Uyum yüzdesi, seçili pencerede planlanan öğelerin kaçını tamamladığından hesaplanır.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if rule.kind == .tagFrequency {
                        Picker("Etiket", selection: $rule.targetId) {
                            ForEach(TagCatalog.all) { Text("\($0.emoji) \($0.title)").tag($0.id) }
                        }
                    } else {
                        Picker("Metrik", selection: $rule.targetId) {
                            ForEach(metricOptions) { Text($0.title).tag($0.id) }
                        }
                    }
                    if rule.kind == .percentOfEnergy {
                        HStack {
                            Text("kcal / gram")
                            Spacer()
                            TextField("9", value: $rule.kcalPerGram, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                        }
                        Text("Yağ 9, protein ve karbonhidrat 4 kcal/g.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section("Koşul") {
                    Picker("Operatör", selection: $rule.op) {
                        ForEach(RuleOperator.allCases) { Text($0.label).tag($0) }
                    }
                    HStack {
                        Text(rule.op == .between ? "Alt sınır" : "Değer")
                        Spacer()
                        TextField("0", value: $rule.value, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                    if rule.op == .between {
                        HStack {
                            Text("Üst sınır")
                            Spacer()
                            TextField("0", value: Binding(
                                get: { rule.value2 ?? rule.value },
                                set: { rule.value2 = $0 }), format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        }
                    }
                    if rule.kind == .tagFrequency {
                        Text("Etiket sıklığı haftalık değerlendirilir (gün/hafta).")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section("Skordaki ağırlığı") {
                    HStack {
                        Slider(value: $rule.weight, in: 0.5...3, step: 0.5)
                        Text(String(format: "%.1f", rule.weight)).font(.subheadline.bold()).frame(width: 40)
                    }
                    Text("Yüksek ağırlık, bu kuralın toplam uyum skorunu daha çok etkilemesi demektir.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Gerekçe (opsiyonel)") {
                    TextField("Neden bu kural var?", text: $rule.note, axis: .vertical)
                        .lineLimit(1...3)
                    Text("Bu not yapay zekâ katmanına da bağlam olarak gider.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section { Text(rule.summary()).font(.subheadline.bold()) } header: { Text("Önizleme") }
            }
            .navigationTitle("Kural")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") { onSave(rule); dismiss() }.bold()
                }
            }
        }
    }
}
