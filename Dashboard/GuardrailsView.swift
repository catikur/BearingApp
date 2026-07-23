import SwiftUI

struct GuardrailsView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss
    let summary: GuardrailEngine.Summary
    /// Kural id → bugünkü durum. 14 günlük uyumdan ayrı: "şu an ne durumdayım".
    var todayStatuses: [UUID: GuardrailEngine.TodayStatus] = [:]
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    scoreHeader
                    if summary.results.isEmpty {
                        EmptyStateView(
                            icon: "checklist",
                            title: "Kural yok",
                            guidance: "Kendi kurallarını ekle — uyum skoru onlara göre hesaplanır.",
                            actionTitle: "Kural ekle",
                            action: { showEditor = true }
                        )
                        .cardSurface()
                    } else {
                        ForEach(summary.results) { r in ruleRow(r) }
                    }
                    Button {
                        showEditor = true
                    } label: {
                        Label("Kuralları düzenle", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(DS.Surface.accent)
                    Text("Skor = kuralların ağırlıklı uyum ortalaması. Ağırlığı, eşiği ve pencereyi sen belirlersin; hesap tamamen deterministiktir.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.lg)
            }
            .background(DS.Surface.background)
            .navigationTitle("Guardrail Uyumu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
            .sheet(isPresented: $showEditor) {
                RuleEditorView().environmentObject(profileStore)
            }
        }
    }

    // Skor rengi: durum kanalı, nadir. İyi → olumlu, altı → dikkat. Kırmızı YOK (DESIGN.md).
    private var scoreTint: Color {
        summary.score >= profileStore.settings.guardrailGoodScore ? DS.Status.positive : DS.Status.attention
    }

    private var scoreHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(DS.integer(Int(summary.score.rounded())))
                    .font(DS.Font.bigStat())
                    .foregroundStyle(scoreTint)
                Text("/ 100")
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Text.secondary)
            }
            // Rutin ilerleme teal kalır (DESIGN.md); skor rengi yalnız sayıdadır.
            ThinBar(progress: summary.score / 100)
            Text("\(DS.integer(summary.rulesWithData)) kural değerlendirildi · son \(DS.integer(summary.windowDays)) gün")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func ruleRow(_ r: GuardrailEngine.RuleResult) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(r.rule.summary())
                        .font(DS.Font.body.weight(.semibold))
                        .foregroundStyle(DS.Text.primary)
                    if !r.rule.note.isEmpty {
                        Text(r.rule.note)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Text.secondary)
                    }
                }
                Spacer()
                if r.hasData {
                    Text(DS.percent(Int(r.compliancePct.rounded())))
                        .font(DS.Font.heading)
                        .foregroundStyle(r.compliancePct >= 80 ? DS.Status.positive : DS.Status.attention)
                        .monospacedDigit()
                } else {
                    Text("veri yok")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                }
            }
            todayLine(r.rule)
            if r.hasData {
                ThinBar(progress: r.compliancePct / 100)
                HStack {
                    Text("\(DS.integer(r.compliantDays))/\(DS.integer(r.evaluatedDays)) \(r.rule.kind == .tagFrequency ? "hafta" : "gün")")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.secondary)
                        .monospacedDigit()
                    Spacer()
                    if let a = r.avgValue {
                        Text("ort. \(DS.decimal(a))")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Text.secondary)
                            .monospacedDigit()
                    }
                }
                if !r.failures.isEmpty {
                    Text("Son sapmalar: " + r.failures.prefix(3)
                        .map { $0.formatted(.dateTime.day().month(.abbreviated).locale(DS.locale)) }
                        .joined(separator: ", "))
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Bugünün (veya bu haftanın) durumu — 14 günlük uyumdan ayrı bir soru.
    @ViewBuilder private func todayLine(_ rule: GuardrailRule) -> some View {
        if let st = todayStatuses[rule.id], st.hasData, let v = st.value {
            let tint: Color = st.passes ? DS.Status.positive : DS.Status.attention
            HStack(spacing: DS.Space.xs) {
                Image(systemName: st.passes ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(DS.Font.caption)
                    .foregroundStyle(tint)
                Text("\(st.period.capitalized): \(fmtValue(v, for: rule)) — \(st.passes ? "uyuluyor" : "dışında")")
                    .font(DS.Font.caption)
                    .foregroundStyle(tint)
                Spacer()
            }
        }
    }

    private func fmtValue(_ v: Double, for rule: GuardrailRule) -> String {
        let unit: String = {
            switch rule.kind {
            case .percentOfEnergy: return "% enerji"
            case .tagFrequency:    return "kez"
            case .planAdherence:   return "% uyum"
            case .metricThreshold: return HealthMetricCatalog.byId(rule.targetId)?.unit ?? ""
            }
        }()
        return "\(DS.decimal(v)) \(unit)"
    }
}
