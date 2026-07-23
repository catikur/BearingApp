import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject var config: AIConfig
    @EnvironmentObject var memory: AIMemory
    @Environment(\.dismiss) var dismiss

    @State private var keyInput = ""
    @State private var showPrompt = false
    @State private var editingTask: AITask?
    @State private var showMemory = false
    @State private var customModel = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Yapay zekâ katmanı", isOn: $config.enabled)
                } footer: {
                    Text("Kapalıyken uygulama tamamen deterministik çalışır; hiçbir veri dışarı çıkmaz.")
                }

                Section("OpenRouter anahtarı") {
                    if config.hasKey {
                        HStack {
                            Label("Anahtar kayıtlı", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Sil", role: .destructive) { config.clearKey(); keyInput = "" }
                        }
                    } else {
                        SecureField("sk-or-...", text: $keyInput)
                        Button("Kaydet") { config.setKey(keyInput); keyInput = "" }
                            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Anahtar Keychain'de saklanır, UserDefaults'a veya yedeğe yazılmaz.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Model") {
                    Picker("Hazır modeller", selection: $config.model) {
                        ForEach(AIConfig.presetModels, id: \.self) { Text($0).tag($0) }
                        if !AIConfig.presetModels.contains(config.model) {
                            Text(config.model).tag(config.model)
                        }
                    }
                    HStack {
                        TextField("veya model kimliği yaz", text: $customModel)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button("Kullan") {
                            let t = customModel.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty { config.model = t; customModel = "" }
                        }
                        .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("OpenRouter'daki herhangi bir model kimliği çalışır (ör. \"mistralai/mistral-large\").")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Üretim ayarları") {
                    HStack {
                        Text("Sıcaklık")
                        Spacer()
                        Text(String(format: "%.2f", config.temperature)).foregroundStyle(.secondary)
                    }
                    Slider(value: $config.temperature, in: 0...1, step: 0.05)
                    Stepper("Maks. token: \(config.maxTokens)", value: $config.maxTokens, in: 300...4000, step: 100)
                    Text("Düşük sıcaklık = daha tutarlı, daha az yaratıcı yorum. Sayısal işler için 0.2–0.4 önerilir.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section {
                    Button { showPrompt = true } label: {
                        HStack {
                            Label("Sistem promptu (ana sınırlayıcı)", systemImage: "text.badge.checkmark")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Modelin uyması gereken kurallar. Varsayılan: hesap yapma, sayı uydurma, tanı koyma, ilaç dozu verme.")
                }

                Section {
                    ForEach(AITask.allCases) { t in
                        Button { editingTask = t } label: {
                            HStack {
                                Label(t.label, systemImage: t.icon)
                                Spacer()
                                if config.taskInstructions[t.rawValue] != nil {
                                    Text("özel").font(.caption2).foregroundStyle(.orange)
                                }
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text("Görev talimatları") }
                footer: { Text("Her görevin modele verdiği talimat. Beslenme planı ve antrenman ayarı görevlerinde model yapılandırılmış öneri döndürür; öneri plana yazılmadan önce motor doğrular ve sen onaylarsın.") }

                Section("Modele ne gönderilsin") {
                    Toggle("Profil ve hedef", isOn: $config.sendProfile)
                    Toggle("Motor çıktıları (TDEE, trend, sapma)", isOn: $config.sendEngines)
                    Toggle("Kurallar ve uyum", isOn: $config.sendRules)
                    Toggle("Son 7 gün metrik ortalamaları", isOn: $config.sendMetrics)
                    Toggle("Etiketlediğin günler", isOn: $config.sendLabels)
                    Toggle("Kalıcı hafıza", isOn: $config.sendMemory)
                }

                Section {
                    Button { showMemory = true } label: {
                        HStack {
                            Label("Kalıcı hafıza", systemImage: "brain")
                            Spacer()
                            Text("\(memory.items.count) not").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Stepper("Prompta girecek not: \(config.memoryLimit)", value: $config.memoryLimit, in: 5...60, step: 5)
                } header: { Text("Hafıza") }
                footer: { Text("Sabitlenen notlar her istekte önce gönderilir; kalanlar en yeniden eskiye doğru limit kadar eklenir.") }

                Section {
                    Button("Varsayılan sistem promptuna dön", role: .destructive) { config.resetPrompt() }
                }
            }
            .navigationTitle("Yapay Zekâ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
            .sheet(isPresented: $showPrompt) { PromptEditor(text: $config.systemPrompt) }
            .sheet(item: $editingTask) { t in
                TaskInstructionEditor(task: t,
                                      text: config.instruction(for: t),
                                      onSave: { config.setInstruction($0, for: t) },
                                      onReset: { config.resetInstruction(for: t) })
            }
            .sheet(isPresented: $showMemory) { MemoryView().environmentObject(memory) }
        }
    }
}

/// Sistem promptu düzenleyici
struct PromptEditor: View {
    @Binding var text: String
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bu metin her istekte modele ilk kural seti olarak gider.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                TextEditor(text: $text)
                    .font(.system(.callout, design: .monospaced))
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Sistem Promptu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
        }
    }
}

/// Hafıza yönetimi
struct MemoryView: View {
    @EnvironmentObject var memory: AIMemory
    @Environment(\.dismiss) var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Yeni not (ör. bira şişkinlik yapıyor)", text: $draft, axis: .vertical)
                            .lineLimit(1...3)
                        Button {
                            memory.add(draft); draft = ""
                        } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach(memory.items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Button { memory.togglePin(item) } label: {
                                Image(systemName: item.pinned ? "pin.fill" : "pin")
                                    .foregroundStyle(item.pinned ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text).font(.subheadline)
                                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { memory.delete(at: $0) }
                } header: {
                    Text("Notlar")
                } footer: {
                    Text("Sabitlenen notlar (📌) her istekte önceliklidir. Kaydırarak silebilirsin.")
                }
            }
            .navigationTitle("Kalıcı Hafıza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
        }
    }
}


/// Görev talimatı düzenleyici
struct TaskInstructionEditor: View {
    let task: AITask
    @State var text: String
    let onSave: (String) -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bu talimat, \"\(task.label)\" görevinde modele verilir. Deterministik anlık görüntü ve çıktı şeması otomatik eklenir.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                TextEditor(text: $text)
                    .font(.system(.callout, design: .monospaced))
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle(task.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Varsayılan") { text = task.defaultInstruction; onReset() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") { onSave(text); dismiss() }.bold()
                }
            }
        }
    }
}
