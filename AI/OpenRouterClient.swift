import Foundation
import SwiftUI

// MARK: - Sohbet modeli
struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: String        // "user" | "assistant"
    var content: String
    var date: Date = Date()
}

// MARK: - Deterministik bağlam üretici
/// LLM'e giden metnin TAMAMI burada üretilir ve kullanıcıya aynen gösterilebilir.
/// Buradaki her sayı motor katmanından gelir — bu dosyada hesap yapılmaz.
enum AIContext {

    @MainActor
    static func snapshot(profile: UserProfile,
                         settings: EngineSettings,
                         rules: [GuardrailRule],
                         healthContext: HealthContext,
                         task: AITask,
                         planBlock: String,
                         tdee: TDEEEngine.Result?,
                         trend: TrendEngine.Result?,
                         deviations: [BaselineEngine.Deviation],
                         composite: BaselineEngine.Composite,
                         guardrails: GuardrailEngine.Summary?,
                         dayProgress: [DayProgress] = [],
                         series: [String: [MetricSample]],
                         labelCounts: [(String, Int)],
                         config: AIConfig) -> String {

        var b: [String] = []
        b.append("### DETERMİNİSTİK ANLIK GÖRÜNTÜ (uygulama tarafından hesaplandı)")
        b.append("Tarih: \(Date().formatted(date: .abbreviated, time: .shortened))")

        if config.sendProfile {
            b.append("\n## Profil")
            b.append("- Yaş \(profile.age), \(profile.sex.label), boy \(Int(profile.heightCm)) cm")
            b.append("- Hedef kilo: \(f(profile.targetWeightKg)) kg · hedef hız: \(f(profile.targetRateKgPerWeek)) kg/hafta")
            if !profile.goalNote.isEmpty { b.append("- Kullanıcının amacı: \(profile.goalNote)") }
            let ctx = healthContext.promptBlock()
            if !ctx.isEmpty { b.append(ctx) }
        }

        if config.sendEngines {
            b.append("\n## Adaptif TDEE")
            if let t = tdee {
                b.append("- Ölçülmüş TDEE: \(f0(t.tdee)) kcal/gün (\(t.confidence.label))")
                b.append("- Ortalama alım: \(f0(t.meanIntake)) kcal · \(t.intakeDays)/\(t.windowDays) gün loglanmış (%\(f0(t.intakeCoverage*100)))")
                b.append("- Kilo eğimi: \(f2(t.slopeKgPerDay*7)) kg/hafta")
                b.append("- Mevcut açık: \(f0(t.currentDeficit)) kcal/gün")
                b.append("- Hedef hız için önerilen alım: \(f0(t.recommendedIntake)) kcal/gün")
                b.append("- Karşılaştırma için BMR (Mifflin-St Jeor): \(f0(t.bmrReference)) kcal")
            } else { b.append("- Hesaplanamadı (yeterli kalori/kilo verisi yok)") }

            b.append("\n## Kilo trendi")
            if let w = trend {
                b.append("- Düzleştirilmiş kilo: \(f(w.smoothedNow)) kg (ham son: \(f(w.rawNow)) kg)")
                b.append("- Hız: \(f2(w.ratePerWeek)) kg/hafta (\(w.rateWindowDays) günlük pencere)")
                b.append("- Başlangıçtan değişim: \(f2(w.totalChange)) kg")
                if let p = w.progressPct { b.append("- Hedefe ilerleme: %\(f0(p))") }
                b.append("- Hedefe kalan: \(f(w.remainingKg)) kg")
                if let e = w.etaDate, let wk = w.weeksRemaining {
                    b.append("- Mevcut hızla tahmini varış: \(e.formatted(date: .abbreviated, time: .omitted)) (~\(f0(wk)) hafta)")
                } else {
                    b.append("- Varış tahmini yok (mevcut hız hedefe götürmüyor veya çok düşük)")
                }
            } else { b.append("- Hesaplanamadı (yeterli kilo verisi yok)") }

            b.append("\n## Baseline sapmaları (kendi geçmişine göre, z-skor)")
            if deviations.isEmpty { b.append("- Değerlendirilecek metrik yok") }
            for d in deviations.prefix(8) {
                let title = HealthMetricCatalog.byId(d.metricId)?.title ?? d.metricId
                b.append("- \(title): bugün \(f(d.today)) · baseline \(f(d.mean))±\(f(d.sd)) · z=\(f2(d.z))\(d.concerning ? " ⚠︎ kötü yönde sapma" : "")")
            }
            if composite.triggered {
                let names = composite.firing.map { HealthMetricCatalog.byId($0)?.title ?? $0 }
                b.append("- BİLEŞİK SİNYAL AKTİF: \(names.joined(separator: ", ")) aynı anda kötü yönde (\(composite.firing.count)/\(composite.needed))")
            }
        }

        if config.sendRules, let g = guardrails {
            b.append("\n## Guardrail uyumu (kullanıcının kendi kuralları, son \(g.windowDays) gün)")
            b.append("- Ağırlıklı uyum skoru: %\(f0(g.score))")
            for r in g.results {
                if r.hasData {
                    b.append("- \(r.rule.summary()) → %\(f0(r.compliancePct)) uyum (\(r.compliantDays)/\(r.evaluatedDays))\(r.rule.note.isEmpty ? "" : " · gerekçe: \(r.rule.note)")")
                } else {
                    b.append("- \(r.rule.summary()) → veri yok")
                }
            }
        }

        if config.sendEngines, !dayProgress.isEmpty {
            b.append("\n## Bugünün hedefleri ve ilerlemesi (çözümlenmiş — kart ve Bugün bloğuyla aynı)")
            for dp in dayProgress {
                let title = HealthMetricCatalog.byId(dp.metricId)?.title ?? dp.metricId
                guard let t = dp.target else {
                    b.append("- \(title): bugün \(f(dp.today)) — hedef yok")
                    continue
                }
                let tgt = t.direction == .between
                    ? "\(f(t.value))–\(f(t.upperValue ?? t.value))"
                    : "\(t.direction.symbol) \(f(t.value))"
                let flag = dp.state == .overTarget ? " — TAVAN AŞILDI" : ""
                b.append("- \(title): bugün \(f(dp.today)) / hedef \(tgt) \(t.unit) (kaynak: \(sourceLabel(t.source)), yön: \(t.direction.label))\(flag)")
            }
        }

        if config.sendEngines, !planBlock.isEmpty {
            b.append(planBlock)
        }

        if config.sendMetrics {
            b.append(task.needsNutritionDetail
                     ? "\n## Son 7 gün ortalamaları (beslenme öncelikli)"
                     : "\n## Son 7 gün ortalamaları")
            let ids = series.keys.sorted()
            var lines: [String] = []
            for id in ids {
                guard let s = series[id], !s.isEmpty else { continue }
                let last7 = Series.window(s, days: 7).map { $0.value }
                guard let m = Series.mean(last7), let def = HealthMetricCatalog.byId(id) else { continue }
                lines.append("- \(def.title): \(f(m)) \(def.unit)")
            }
            b.append(lines.isEmpty ? "- Veri yok" : lines.joined(separator: "\n"))
        }

        if config.sendLabels {
            b.append("\n## Kullanıcının işaretlediği günler")
            if labelCounts.isEmpty { b.append("- Etiket yok") }
            for (tagId, n) in labelCounts {
                let name = TagCatalog.tag(tagId)?.title
                    ?? PlanEngine.displayName(forScanId: tagId)
                    ?? tagId
                b.append("- \(name): \(n) gün")
            }
        }

        b.append("\n### KURAL: Yukarıdaki sayılar kesindir. Yeniden hesaplama, ekleme veya tahmin yapma.")
        b.append("\n### GÖREV: \(task.label)")
        b.append(config.instruction(for: task))
        if task.structured { b.append("\n" + AITask.outputSchema) }
        return b.joined(separator: "\n")
    }

    /// Bugünün planı + uyum — deterministik plan motorundan gelir
    static func planBlock(occurrences: [PlanOccurrence],
                          logs: [String: PlanLog],
                          adherence: [PlanEngine.Adherence],
                          streak: Int,
                          phase: Int) -> String {
        var b: [String] = ["\n## Plan (bugün)"]
        if occurrences.isEmpty {
            b.append("- Bugün için planlanmış öğe yok")
        } else {
            let done = occurrences.filter { logs[$0.key]?.status == .done }.count
            b.append("- \(done)/\(occurrences.count) tamamlandı · kesintisiz seri: \(streak) gün · aktif faz: \(phase)")
            for o in occurrences {
                let st = logs[o.key]?.status
                let mark = st == .done ? "[yapıldı]" : (st == .skipped ? "[atlandı]" : "[bekliyor]")
                b.append("- \(TimeOfDay.from(o.when).label) \(o.item.title) \(mark)")
            }
        }
        if !adherence.isEmpty {
            b.append("\n## Plan uyumu (kategori)")
            for a in adherence {
                guard let c = a.category else { continue }
                b.append("- \(c.label): %\(String(format: "%.0f", a.pct)) (\(a.done)/\(a.total))")
            }
        }
        return b.joined(separator: "\n")
    }

    private static func sourceLabel(_ s: TargetEngine.TargetSource) -> String {
        switch s {
        case .guardrailRule: return "kuralın"
        case .tdeeEngine:    return "TDEE"
        case .catalog:       return "yedek katalog"
        case .none:          return "yok"
        }
    }

    private static func f(_ v: Double)  -> String { String(format: "%.1f", v) }
    private static func f0(_ v: Double) -> String { String(format: "%.0f", v) }
    private static func f2(_ v: Double) -> String { String(format: "%.2f", v) }
}

// MARK: - OpenRouter istemcisi
@MainActor
final class OpenRouterClient: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var sending = false
    @Published var lastError: String?
    @Published var lastContext: String = ""
    @Published var lastProposal: AIProposal?
    @Published var lastRawProposal: String = ""
    @Published var parseError: String?

    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    private struct ORMessage: Codable { let role: String; let content: String }
    private struct ORRequest: Codable {
        let model: String
        let messages: [ORMessage]
        let temperature: Double
        let max_tokens: Int
    }
    private struct ORResponse: Codable {
        struct Choice: Codable { let message: ORMessage }
        struct APIError: Codable { let message: String? }
        let choices: [Choice]?
        let error: APIError?
    }

    func clear() {
        messages.removeAll(); lastError = nil
        lastProposal = nil; parseError = nil; lastRawProposal = ""
    }

    func send(_ text: String,
              context: String,
              config: AIConfig,
              memory: AIMemory,
              task: AITask = .chat) async {

        guard let key = config.apiKey, !key.isEmpty else {
            lastError = "OpenRouter API anahtarı yok. Ayarlar → Yapay Zekâ bölümünden ekle."
            return
        }
        lastContext = context
        messages.append(ChatMessage(role: "user", content: text))
        sending = true
        defer { sending = false }

        // Sistem katmanı: ana sınırlayıcı + hafıza + deterministik görüntü
        var system = config.systemPrompt
        if config.sendMemory {
            system += "\n\n### KALICI HAFIZA (kullanıcının onayladığı notlar)\n" + memory.promptBlock(limit: config.memoryLimit)
        }
        system += "\n\n" + context

        var payload: [ORMessage] = [ORMessage(role: "system", content: system)]
        // Sohbet geçmişi (son 12 tur)
        for m in messages.suffix(12) { payload.append(ORMessage(role: m.role, content: m.content)) }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("bearing", forHTTPHeaderField: "X-Title")
        req.httpBody = try? JSONEncoder().encode(
            ORRequest(model: config.model, messages: payload,
                      temperature: config.temperature, max_tokens: config.maxTokens))

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let decoded = try? JSONDecoder().decode(ORResponse.self, from: data)
            if let msg = decoded?.error?.message {
                lastError = "OpenRouter: \(msg)"; return
            }
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastError = "Sunucu hatası (\((resp as? HTTPURLResponse)?.statusCode ?? -1))"; return
            }
            guard let content = decoded?.choices?.first?.message.content else {
                lastError = "Yanıt çözümlenemedi."; return
            }
            messages.append(ChatMessage(role: "assistant", content: content))
            lastError = nil

            // Yapılandırılmış görevlerde öneriyi ayrıştır — plana YAZILMAZ, onay bekler
            if task.structured {
                lastRawProposal = content
                switch ProposalParser.parse(content) {
                case .success(let p): lastProposal = p; parseError = nil
                case .failure(let e): lastProposal = nil; parseError = e.message
                }
            } else {
                lastProposal = nil; parseError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
