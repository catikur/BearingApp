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
    private var currentTask: Task<Void, Never>?

    private struct ORMessage: Codable { let role: String; let content: String }
    private struct ORRequest: Codable {
        let model: String
        let messages: [ORMessage]
        let temperature: Double
        let max_tokens: Int
        let stream: Bool
        let usage: UsageOpt            // akış sonunda kullanım bilgisi gelsin (maliyet sayacı)
        let provider: ProviderPref     // zero-retention: veri toplamayan sağlayıcılara yönlen (§8.5)
        struct UsageOpt: Codable { let include: Bool }
        struct ProviderPref: Codable { let data_collection: String }
    }
    /// SSE akış parçası: choices[].delta.content + (son parçada) usage
    private struct ORStreamChunk: Codable {
        struct Choice: Codable {
            struct Delta: Codable { let content: String? }
            let delta: Delta?
        }
        struct UsageInfo: Codable { let prompt_tokens: Int?; let completion_tokens: Int? }
        struct APIError: Codable { let message: String? }
        let choices: [Choice]?
        let usage: UsageInfo?
        let error: APIError?
    }

    func clear() {
        messages.removeAll(); lastError = nil
        lastProposal = nil; parseError = nil; lastRawProposal = ""
    }

    /// Kullanıcı akışı durdurabilir (§8.3 — iptal her an mümkün). Kısmi metin korunur.
    func cancel() { currentTask?.cancel() }

    func send(_ text: String,
              context: String,
              config: AIConfig,
              memory: AIMemory,
              task: AITask = .chat) async {
        currentTask?.cancel()
        let t = Task { await performSend(text, context: context, config: config, memory: memory, task: task) }
        currentTask = t
        await t.value
    }

    private func performSend(_ text: String,
                             context: String,
                             config: AIConfig,
                             memory: AIMemory,
                             task: AITask) async {

        guard let key = config.apiKey, !key.isEmpty else {
            lastError = "OpenRouter API anahtarı yok. Ayarlar → Yapay Zekâ bölümünden ekle."
            return
        }
        // Maliyet tavanı (§8.2): bütçe dolduysa nazik sınır — istek atılmaz
        if config.budgetExhausted {
            lastError = "Günlük token bütçesi doldu (\(config.todayUsage()) / \(config.dailyTokenBudget)). Yarın sıfırlanır; gerekiyorsa Ayarlar → Yapay Zekâ'dan artır."
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
        // Sohbet geçmişi (son 12 tur) — canlı doldurulacak boş asistan mesajı SONRA eklenir
        for m in messages.suffix(12) { payload.append(ORMessage(role: m.role, content: m.content)) }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("bearing", forHTTPHeaderField: "X-Title")
        req.httpBody = try? JSONEncoder().encode(
            ORRequest(model: config.model, messages: payload,
                      temperature: config.temperature, max_tokens: config.maxTokens,
                      stream: true,
                      usage: .init(include: true),
                      provider: .init(data_collection: "deny")))

        // Canlı dolacak asistan balonu (akış UI'ı)
        messages.append(ChatMessage(role: "assistant", content: ""))
        var acc = ""
        var usageTokens = 0
        var streamError: String?

        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                var body = ""
                for try await line in bytes.lines { body += line; if body.count > 400 { break } }
                let msg = (try? JSONDecoder().decode(ORStreamChunk.self, from: Data(body.utf8)))?.error?.message
                dropEmptyAssistantTail()
                lastError = msg.map { "OpenRouter: \($0)" }
                    ?? "Sunucu hatası (\((resp as? HTTPURLResponse)?.statusCode ?? -1))"
                return
            }
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let chunk = String(line.dropFirst(6))
                if chunk == "[DONE]" { break }
                guard let d = chunk.data(using: .utf8),
                      let parsed = try? JSONDecoder().decode(ORStreamChunk.self, from: d) else { continue }
                if let msg = parsed.error?.message { streamError = "OpenRouter: \(msg)"; break }
                if let delta = parsed.choices?.first?.delta?.content, !delta.isEmpty {
                    acc += delta
                    messages[messages.count - 1].content = acc
                }
                if let u = parsed.usage {
                    usageTokens = (u.prompt_tokens ?? 0) + (u.completion_tokens ?? 0)
                }
            }
        } catch is CancellationError {
            // Kullanıcı durdurdu (§8.3): kısmi metin kalır, hata sayılmaz
            if acc.isEmpty { dropEmptyAssistantTail() }
        } catch {
            if acc.isEmpty { dropEmptyAssistantTail() }
            lastError = "Ağ hatası: \(error.localizedDescription)"
            return
        }

        // Kullanım sayacı: sağlayıcı usage vermediyse (ör. iptal) kaba tahmin — ~4 karakter/token
        config.addUsage(usageTokens > 0 ? usageTokens
                                        : max(1, (system.count + text.count + acc.count) / 4))

        if let e = streamError {
            if acc.isEmpty { dropEmptyAssistantTail() }
            lastError = e
            return
        }
        if acc.isEmpty {
            // Boş/yetersiz sonuç durumu (§8.3): dürüst mesaj + sonraki adım
            dropEmptyAssistantTail()
            lastError = "Model işe yarar bir yanıt üretemedi — soruyu daraltıp yeniden dene."
            return
        }
        lastError = nil

        // Yapılandırılmış görevlerde öneriyi ayrıştır — plana YAZILMAZ, onay bekler
        if task.structured {
            lastRawProposal = acc
            switch ProposalParser.parse(acc) {
            case .success(let p): lastProposal = p; parseError = nil
            case .failure(let e): lastProposal = nil; parseError = e.message
            }
        } else {
            lastProposal = nil; parseError = nil
        }
    }

    /// Akış hiç içerik üretmeden bittiyse boş asistan balonunu kaldır
    private func dropEmptyAssistantTail() {
        if let last = messages.last, last.role == "assistant", last.content.isEmpty {
            messages.removeLast()
        }
    }
}
