import SwiftUI

/// Dashboard özelleştirme: hangi metrikler görünsün (ekle/çıkar), sıralama.
struct MetricPickerView: View {
    @EnvironmentObject var config: DashboardConfig
    @Environment(\.dismiss) var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                // Etkin metrikler (sürükle-sırala + çıkar)
                Section("Dashboard'da gösterilenler (\(config.enabledIds.count))") {
                    ForEach(config.enabledMetrics) { def in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(def.title)
                                Text("\(def.category) · \(def.source.rawValue)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(def.unit).font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { config.toggle(def.id) }
                    }
                    .onMove { config.move(from: $0, to: $1) }
                }

                // Kategoriye göre eklenebilir metrikler
                ForEach(HealthMetricCatalog.categories, id: \.self) { cat in
                    let items = HealthMetricCatalog.metrics(in: cat)
                        .filter { !config.isEnabled($0.id) }
                        .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
                    if !items.isEmpty {
                        Section(cat) {
                            ForEach(items) { def in
                                HStack {
                                    Image(systemName: "plus.circle").foregroundStyle(.blue)
                                    VStack(alignment: .leading) {
                                        Text(def.title)
                                        Text(def.source.rawValue).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(def.unit).font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { config.toggle(def.id) }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Metrik ara")
            .navigationTitle("Metrikleri Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Varsayılan") { config.resetToDefault() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }
}
