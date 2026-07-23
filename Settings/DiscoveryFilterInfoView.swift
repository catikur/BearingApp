import SwiftUI

/// Otomatik keşifte hangi çiftlerin neden gizlendiğini birebir gösterir
/// ve filtreyi buradan kapatmayı sağlar. Gizli kural bırakmamak için var.
struct DiscoveryFilterInfoView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Otomatik keşif yüzlerce metrik çiftini tarar. Bazı çiftler tanım gereği neredeyse %100 korele olur ve listenin tepesini doldurur — gerçek bulguları aşağı iter. Bu iki filtre onları gizler. İstersen kapat: hiçbir şey silinmez, sadece listeye geri gelir.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("İkiz metrikleri gizle", isOn: $profileStore.settings.discoveryFilterTwins)
                } header: {
                    Text("Filtre 1 — İkizler")
                } footer: {
                    Text("İki kaynak aynı şeyi ölçüyor. Aralarındaki korelasyon cihaz uyumunu gösterir, sağlığın hakkında bir şey söylemez.")
                }

                Section {
                    ForEach(Array(PatternScan.twinGroups.enumerated()), id: \.offset) { _, group in
                        groupRow(group)
                    }
                } header: {
                    Text("Gizlenen ikiz çiftleri (\(PatternScan.twinGroups.count))")
                }

                Section {
                    Toggle("Aynı aile metriklerini gizle", isOn: $profileStore.settings.discoveryFilterFamilies)
                } header: {
                    Text("Filtre 2 — Aileler")
                } footer: {
                    Text("Biri diğerinin parçası veya doğrudan türevi. Örneğin derin uyku toplam uykunun içinde; ikisi zaten birlikte hareket eder.")
                }

                Section {
                    ForEach(Array(PatternScan.familyGroups.enumerated()), id: \.offset) { _, group in
                        groupRow(group)
                    }
                } header: {
                    Text("Gizlenen aileler (\(PatternScan.familyGroups.count))")
                }

                Section {
                    Stepper("Minimum ortak gün: \(profileStore.settings.discoveryMinN)",
                            value: $profileStore.settings.discoveryMinN, in: 3...60)
                    Stepper("Listede gösterilecek: \(profileStore.settings.discoveryTopCount)",
                            value: $profileStore.settings.discoveryTopCount, in: 5...50, step: 5)
                    Toggle("Ertesi gün etkisini de tara", isOn: $profileStore.settings.discoveryScanNextDay)
                } header: {
                    Text("Diğer tarama parametreleri")
                } footer: {
                    Text("Minimum ortak gün düşerse daha çok bulgu çıkar ama küçük örneklem gürültüsü artar.")
                }
            }
            .navigationTitle("Keşif Filtreleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
        }
    }

    private func groupRow(_ group: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(group.map { HealthMetricCatalog.byId($0)?.title ?? $0 }.joined(separator: "  ↔  "))
                .font(.caption)
            Text(group.joined(separator: ", "))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }
}
