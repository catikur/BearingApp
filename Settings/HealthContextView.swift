import SwiftUI

struct HealthContextView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss
    @State private var newLab = HealthContext.LabNote(name: "", value: "")

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Buradaki bilgiler yapay zekâ katmanına bağlam olarak gider. Uygulama bunları ölçemez — sen yazarsın. Boş bırakırsan gönderilmez.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                listSection("Aktif durumlar", "Ör. insülin direnci, tinnitus, TME",
                            $profileStore.context.conditions)

                listSection("KESİN KAÇINILACAKLAR", "Öneri bunları içeremez",
                            $profileStore.context.avoid, tint: .red)

                listSection("İntolerans / tetikleyici", "Ör. bira, hamur işi, çiğ brokoli",
                            $profileStore.context.intolerances)

                listSection("Tercihler", "Sevdiğin yiyecekler, mutfak tarzı",
                            $profileStore.context.preferences)

                listSection("Antrenman ekipmanı", "Ör. dambıl, barbell, spor salonu",
                            $profileStore.context.equipment)

                Section("Zaman kısıtları") {
                    TextField("Ör. hafta içi 19:00 sonrası antrenman yapabilirim",
                              text: $profileStore.context.scheduleNotes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    ForEach($profileStore.context.keyLabs) { $lab in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Test adı", text: $lab.name)
                                .font(.subheadline.bold())
                            TextField("Değer ve tarih", text: $lab.value)
                                .font(.caption)
                            TextField("Not (opsiyonel)", text: $lab.note)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { profileStore.context.keyLabs.remove(atOffsets: $0) }
                    HStack {
                        TextField("Test", text: $newLab.name)
                        TextField("Değer", text: $newLab.value)
                        Button {
                            guard !newLab.name.isEmpty else { return }
                            profileStore.context.keyLabs.append(newLab)
                            newLab = HealthContext.LabNote(name: "", value: "")
                        } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newLab.name.isEmpty)
                    }
                } header: { Text("Kilit lab değerleri") }
                footer: { Text("Trend takibi için değil — yapay zekânın kararlarını bağlamlandırması için. Ör. \"Apo B · 138 mg/dL · Nis 2025\".") }

                listSection("Bekleyen uzman onayı", "Ör. kardiyoloji onayı öncesi ağır yük yok",
                            $profileStore.context.pendingClinical, tint: DS.Status.attention)

                Section("Serbest not") {
                    TextField("Eklemek istediğin her şey", text: $profileStore.context.freeNotes, axis: .vertical)
                        .lineLimit(1...6)
                }
            }
            .navigationTitle("Kişisel Bağlam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func listSection(_ title: String, _ placeholder: String,
                             _ binding: Binding<[String]>, tint: Color = .primary) -> some View {
        Section {
            ForEach(Array(binding.wrappedValue.enumerated()), id: \.offset) { idx, _ in
                HStack {
                    TextField(placeholder, text: Binding(
                        get: { idx < binding.wrappedValue.count ? binding.wrappedValue[idx] : "" },
                        set: { if idx < binding.wrappedValue.count { binding.wrappedValue[idx] = $0 } }))
                }
            }
            .onDelete { binding.wrappedValue.remove(atOffsets: $0) }
            Button { binding.wrappedValue.append("") } label: {
                Label("Ekle", systemImage: "plus.circle")
            }
        } header: {
            Text(title).foregroundStyle(tint)
        } footer: {
            Text(placeholder).font(.caption2)
        }
    }
}
