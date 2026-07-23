import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var plan: PlanStore
    @EnvironmentObject var notifier: NotificationManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Bildirimler", isOn: $plan.notifSettings.enabled)
                    HStack {
                        Text("Sistem izni")
                        Spacer()
                        if notifier.authorized {
                            Label("verildi", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        } else {
                            Button("İzin iste") { Task { await notifier.requestAuthorization() } }
                        }
                    }
                    HStack {
                        Text("Kurulu bildirim")
                        Spacer()
                        Text("\(notifier.pendingCount) / \(plan.notifSettings.maxScheduled)")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("iOS uygulama başına en fazla 64 bekleyen bildirime izin verir. Bu yüzden yalnızca önümüzdeki günler kurulur ve uygulama her açıldığında tazelenir.")
                }

                Section("Kategoriler") {
                    ForEach(PlanCategory.allCases) { c in
                        Toggle(isOn: Binding(
                            get: { plan.notifSettings.categoryEnabled[c.rawValue] ?? true },
                            set: { plan.notifSettings.categoryEnabled[c.rawValue] = $0 })) {
                            Label(c.label, systemImage: c.icon)
                        }
                    }
                }

                Section {
                    DatePicker("Başlangıç", selection: Binding(
                        get: { plan.notifSettings.quietStart.date(on: Date()) },
                        set: { plan.notifSettings.quietStart = TimeOfDay.from($0) }),
                        displayedComponents: .hourAndMinute)
                    DatePicker("Bitiş", selection: Binding(
                        get: { plan.notifSettings.quietEnd.date(on: Date()) },
                        set: { plan.notifSettings.quietEnd = TimeOfDay.from($0) }),
                        displayedComponents: .hourAndMinute)
                } header: { Text("Sessiz saatler") }
                footer: { Text("Bu aralığa düşen bildirimler kurulmaz. Gece yarısını aşan aralık desteklenir.") }

                Section {
                    Stepper("Kaç gün önden: \(plan.notifSettings.horizonDays)",
                            value: $plan.notifSettings.horizonDays, in: 1...14)
                    Stepper("Maksimum bildirim: \(plan.notifSettings.maxScheduled)",
                            value: $plan.notifSettings.maxScheduled, in: 10...60, step: 5)
                } header: { Text("Kurulum penceresi") }

                Section {
                    Toggle("Sıralı başlatma (tek değişken kuralı)", isOn: $plan.phaseSettings.enabled)
                    if plan.phaseSettings.enabled {
                        Stepper("Faz başına en az: \(plan.phaseSettings.minDaysPerPhase) gün",
                                value: $plan.phaseSettings.minDaysPerPhase, in: 3...60)
                        HStack {
                            Text("Gereken uyum")
                            Spacer()
                            Text("%\(Int(plan.phaseSettings.minAdherence))").foregroundStyle(.secondary)
                        }
                        Slider(value: $plan.phaseSettings.minAdherence, in: 40...100, step: 5)
                        HStack {
                            Text("Açık faz")
                            Spacer()
                            Text("\(plan.unlockedPhase)").foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Faz kuralı") }
                footer: { Text("Yeni bir değişken (ör. yeni suplement) ancak mevcut faz bu süre ve uyum eşiğini geçince açılır. Böylece neyin işe yaradığını ayırt edebilirsin.") }

                Section {
                    Button("Bildirimleri şimdi yeniden kur") {
                        Task {
                            await notifier.reschedule(items: plan.items,
                                                      settings: plan.notifSettings,
                                                      unlockedPhase: plan.unlockedPhase,
                                                      phaseEnabled: plan.phaseSettings.enabled)
                        }
                    }
                    Button("Tüm bekleyen bildirimleri sil", role: .destructive) { notifier.cancelAll() }
                }
            }
            .navigationTitle("Bildirimler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
            .task { await notifier.refreshStatus() }
        }
    }
}
