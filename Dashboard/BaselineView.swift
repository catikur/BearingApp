import SwiftUI
import Charts

struct BaselineView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss
    let deviations: [BaselineEngine.Deviation]
    let composite: BaselineEngine.Composite

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    intro
                    if composite.triggered { compositeAlert }
                    if deviations.isEmpty {
                        EmptyStateView(
                            icon: "waveform.path.ecg",
                            title: "Yeterli geçmiş yok",
                            guidance: "Baseline için en az \(profileStore.settings.baselineMinSamples) günlük veri gerekiyor. İzlenecek metrikleri Ayarlar'dan seçebilirsin."
                        )
                        .cardSurface()
                    } else {
                        ForEach(deviations) { d in row(d) }
                    }
                    footer
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.lg)
            }
            .background(DS.Surface.background)
            .navigationTitle("Baseline & Sapma")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }

    private var intro: some View {
        Text("Her metrik nüfus ortalamasıyla değil, senin son \(profileStore.settings.baselineWindowDays) gününle karşılaştırılıyor. z = bugünün baseline'dan kaç standart sapma uzakta olduğu.")
            .font(DS.Font.caption)
            .foregroundStyle(DS.Text.secondary)
    }

    // Bileşik sinyal — kritik kırmızının izinli olduğu iki bağlamdan biri (DESIGN.md §1).
    private var compositeAlert: some View {
        let names = composite.firing.map { HealthMetricCatalog.byId($0)?.title ?? $0 }
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label("Bileşik sinyal aktif", systemImage: "exclamationmark.triangle.fill")
                .font(DS.Font.body.weight(.semibold))
                .foregroundStyle(DS.Status.critical)
            Text("\(names.joined(separator: ", ")) aynı anda kötü yönde sapmış (\(DS.integer(composite.firing.count))/\(DS.integer(composite.needed))).")
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.primary)
            Text("Bu örüntü klasik olarak enfeksiyon, aşırı yüklenme veya toparlanma borcuyla birlikte görülür — tanı değil, dikkat sinyalidir. Bugün yükü hafifletmeyi değerlendirebilirsin.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.lg)
        .background(DS.Status.critical.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    private func row(_ d: BaselineEngine.Deviation) -> some View {
        let def = HealthMetricCatalog.byId(d.metricId)
        // Bireysel sapma: kötü yönde → dikkat; büyük ama iyi yönde → olumlu; rutin → nötr. Kırmızı YOK.
        let tint: Color = d.concerning
            ? DS.Status.attention
            : (abs(d.z) >= profileStore.settings.baselineZThreshold ? DS.Status.positive : DS.Text.tertiary)
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Text(def?.title ?? d.metricId)
                    .font(DS.Font.body.weight(.semibold))
                    .foregroundStyle(DS.Text.primary)
                Spacer()
                Text("z = \(d.z.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2)).locale(DS.locale)))")
                    .font(DS.Font.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            // z görselleştirme: -3…+3 bandında konum
            GeometryReader { g in
                let clamped = max(-3, min(3, d.z))
                let x = (clamped + 3) / 6 * g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Surface.divider).frame(height: 6)
                    Capsule().fill(DS.Text.tertiary.opacity(0.4))
                        .frame(width: g.size.width / 3, height: 6)
                        .offset(x: g.size.width / 3)
                    Circle().fill(tint).frame(width: 11, height: 11)
                        .offset(x: max(0, min(g.size.width - 11, x - 5.5)))
                }
            }
            .frame(height: 12)
            HStack {
                Text("bugün \(fmt(d.today)) \(def?.unit ?? "")")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
                    .monospacedDigit()
                Spacer()
                Text("baseline \(fmt(d.mean)) ± \(fmt(d.sd)) · n=\(DS.integer(d.samples))")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Eşik: |z| ≥ \(DS.decimal(profileStore.settings.baselineZThreshold)) → sapma sayılır. Yönü metriğin \"iyi tarafı\"na göre değerlendirilir (ör. HRV düşerse kötü, dinlenme nabzı yükselirse kötü).")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)
            Text("Eşiği, pencereyi ve izlenecek metrikleri Ayarlar → Motor Parametreleri'nden değiştirebilirsin.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)
        }
    }

    private func fmt(_ v: Double) -> String {
        v < 10 ? DS.decimal(v) : DS.integer(Int(v.rounded()))
    }
}
