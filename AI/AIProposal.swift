import Foundation

// MARK: - LLM'den gelen öneri
// NOT: Swift'in sentezlediği decoder eksik anahtarda hata fırlatır ve varsayılanı kullanmaz.
// LLM çıktısı her zaman eksiksiz gelmediği için tüm modellerde toleranslı decoder yazıyoruz.
struct AIProposal: Codable {
    var summary: String = ""
    var rationale: String = ""
    var targets: ProposedTargets?
    var items: [ProposedItem] = []
    var workoutChanges: [ProposedWorkout] = []
    var warnings: [String] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case summary, rationale, targets, items, workoutChanges, warnings
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary        = (try? c.decodeIfPresent(String.self, forKey: .summary)) as? String ?? ""
        rationale      = (try? c.decodeIfPresent(String.self, forKey: .rationale)) as? String ?? ""
        targets        = try? c.decodeIfPresent(ProposedTargets.self, forKey: .targets)
        items          = (try? c.decodeIfPresent([ProposedItem].self, forKey: .items)) as? [ProposedItem] ?? []
        workoutChanges = (try? c.decodeIfPresent([ProposedWorkout].self, forKey: .workoutChanges)) as? [ProposedWorkout] ?? []
        warnings       = (try? c.decodeIfPresent([String].self, forKey: .warnings)) as? [String] ?? []
    }
}

struct ProposedTargets: Codable {
    var kcal: Double?
    var proteinG: Double?
    var carbG: Double?
    var fatG: Double?
    var sodiumMg: Double?
    var satFatPctEnergy: Double?
    var fiberG: Double?
}

struct ProposedItem: Codable, Identifiable {
    var id = UUID()
    var action: String = "add"          // add | update | disable
    var title: String = ""
    var category: String = "meal"
    var detail: String = ""
    var scheduleType: String = "daily"  // daily | weekdays | everyNDays | oneOff
    var weekdays: [Int]?
    var everyN: Int?
    var times: [String] = []
    var phase: Int?
    var note: String = ""

    init() {}

    enum CodingKeys: String, CodingKey {
        case action, title, category, detail, scheduleType, weekdays, everyN, times, phase, note
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys, _ d: String) -> String {
            ((try? c.decodeIfPresent(String.self, forKey: k)) as? String) ?? d
        }
        action       = str(.action, "add")
        title        = str(.title, "")
        category     = str(.category, "meal")
        detail       = str(.detail, "")
        scheduleType = str(.scheduleType, "daily")
        note         = str(.note, "")
        weekdays     = try? c.decodeIfPresent([Int].self, forKey: .weekdays)
        everyN       = try? c.decodeIfPresent(Int.self, forKey: .everyN)
        phase        = try? c.decodeIfPresent(Int.self, forKey: .phase)
        times        = ((try? c.decodeIfPresent([String].self, forKey: .times)) as? [String]) ?? []
    }

    var planCategory: PlanCategory { PlanCategory(rawValue: category) ?? .meal }

    var timesParsed: [TimeOfDay] {
        times.compactMap { s in
            let p = s.split(separator: ":")
            guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]),
                  (0...23).contains(h), (0...59).contains(m) else { return nil }
            return TimeOfDay(hour: h, minute: m)
        }
    }

    var scheduleParsed: ScheduleKind {
        switch scheduleType {
        case "weekdays":   return .weekdays((weekdays ?? []).filter { (1...7).contains($0) })
        case "everyNDays": return .everyNDays(max(2, everyN ?? 2))
        case "oneOff":     return .oneOff(Date())
        default:           return .daily
        }
    }

    func toPlanItem() -> PlanItem {
        PlanItem(title: title.isEmpty ? "Öneri" : title,
                 category: planCategory,
                 detail: detail,
                 schedule: scheduleParsed,
                 times: timesParsed.isEmpty ? [TimeOfDay(hour: 12, minute: 0)] : timesParsed,
                 phase: max(1, phase ?? 1),
                 notify: false,                     // öneriler sessiz gelir; sen açarsın
                 note: note)
    }
}

struct ProposedWorkout: Codable, Identifiable {
    var id = UUID()
    var templateName: String = ""
    var action: String = "update"
    var exercises: [ProposedExercise] = []
    var note: String = ""

    init() {}

    enum CodingKeys: String, CodingKey { case templateName, action, exercises, note }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templateName = ((try? c.decodeIfPresent(String.self, forKey: .templateName)) as? String) ?? ""
        action       = ((try? c.decodeIfPresent(String.self, forKey: .action)) as? String) ?? "update"
        note         = ((try? c.decodeIfPresent(String.self, forKey: .note)) as? String) ?? ""
        exercises    = ((try? c.decodeIfPresent([ProposedExercise].self, forKey: .exercises)) as? [ProposedExercise]) ?? []
    }
}

struct ProposedExercise: Codable {
    var name: String = ""
    var sets: Int?
    var reps: String?
    var targetRPE: Double?
    var note: String?

    init() {}

    enum CodingKeys: String, CodingKey { case name, sets, reps, targetRPE, note }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name      = ((try? c.decodeIfPresent(String.self, forKey: .name)) as? String) ?? ""
        sets      = try? c.decodeIfPresent(Int.self, forKey: .sets)
        reps      = try? c.decodeIfPresent(String.self, forKey: .reps)
        targetRPE = try? c.decodeIfPresent(Double.self, forKey: .targetRPE)
        note      = try? c.decodeIfPresent(String.self, forKey: .note)
    }

    func toExercise() -> Exercise {
        Exercise(name: name,
                 sets: sets ?? 3,
                 reps: reps ?? "8-10",
                 targetRPE: targetRPE,
                 note: note ?? "")
    }
}

// MARK: - JSON ayrıştırma
struct ProposalParseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ProposalParser {
    /// Modelin yanıtından JSON'u çıkarır (kod bloğu işaretleri, ön/arka metin toleranslı).
    static func parse(_ raw: String) -> Result<AIProposal, ProposalParseError> {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "```json", with: "")
             .replacingOccurrences(of: "```", with: "")
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") else {
            return .failure(ProposalParseError(message: "Yanıtta JSON bulunamadı."))
        }
        let json = String(s[start...end])
        guard let data = json.data(using: .utf8) else {
            return .failure(ProposalParseError(message: "Yanıt kodlanamadı."))
        }
        do {
            return .success(try JSONDecoder().decode(AIProposal.self, from: data))
        } catch {
            return .failure(ProposalParseError(message: "JSON çözümlenemedi: \(error.localizedDescription)"))
        }
    }
}

// MARK: - Deterministik doğrulama
/// LLM'in önerisi plana yazılmadan ÖNCE motor tarafından denetlenir.
/// Buradaki her kontrol deterministiktir; model bu kararlara karışamaz.
enum ProposalValidator {

    enum Severity: String { case blocker, warning, info }

    struct Issue: Identifiable {
        let id = UUID()
        let severity: Severity
        let text: String
    }

    static func validate(_ p: AIProposal,
                         rules: [GuardrailRule],
                         tdee: TDEEEngine.Result?,
                         profile: UserProfile,
                         context: HealthContext,
                         notifSettings: NotificationSettings,
                         phaseSettings: PhaseSettings,
                         existingItems: [PlanItem]) -> [Issue] {

        var out: [Issue] = []

        // 1) Kalori hedefi motorun önerisiyle uyumlu mu?
        if let kcal = p.targets?.kcal, kcal > 0 {
            if let t = tdee {
                let diff = kcal - t.recommendedIntake
                if abs(diff) > 250 {
                    out.append(Issue(severity: .blocker,
                        text: String(format: "Önerilen kalori %.0f kcal, motorun hesabı %.0f kcal (fark %+.0f). Model kendi hesabını yapmış olabilir.", kcal, t.recommendedIntake, diff)))
                } else if abs(diff) > 100 {
                    out.append(Issue(severity: .warning,
                        text: String(format: "Kalori hedefi motorun hesabından %+.0f kcal sapıyor.", diff)))
                }
            } else {
                out.append(Issue(severity: .blocker,
                    text: "Model kalori hedefi vermiş ama motor henüz TDEE hesaplayamıyor — bu sayının dayanağı yok."))
            }
        }

        // 2) Guardrail kurallarıyla çakışma
        for rule in rules where rule.enabled {
            guard let value = targetValue(for: rule, in: p.targets) else { continue }
            if !satisfies(value, rule) {
                out.append(Issue(severity: .blocker,
                    text: "\(rule.summary()) kuralın ihlal ediliyor — öneri: \(fmt(value))."))
            }
        }

        // 2b) Çözümlenmiş hedeflerle YÖN kontrolü — kurala bağlı olmayan hedefleri de kapsar
        //     (kalori TDEE'den, makrolar katalog yedeğinden gelebilir). Kural varsa (#2)
        //     zaten kontrol edildiğinden burada .guardrailRule kaynağı atlanır.
        let directionChecks: [(String, Double?)] = [
            ("protein", p.targets?.proteinG),
            ("carbs",   p.targets?.carbG),
            ("fat",     p.targets?.fatG),
            ("sodium",  p.targets?.sodiumMg),
            ("fiber",   p.targets?.fiberG),
        ]
        for (metricId, proposed) in directionChecks {
            guard let v = proposed, v > 0,
                  let t = TargetEngine.resolve(metricId: metricId, rules: rules, tdee: tdee, profile: profile),
                  t.source != .guardrailRule else { continue }
            let title = HealthMetricCatalog.byId(metricId)?.title ?? metricId
            switch t.direction {
            case .atMost where v > t.value:
                out.append(Issue(severity: .blocker,
                    text: "\(title): önerilen \(fmt(v)) \(t.unit), hedef bir tavan (≤ \(fmt(t.value)), kaynak: \(sourceLabel(t.source))). Üstünde."))
            case .atLeast where v < t.value:
                out.append(Issue(severity: .warning,
                    text: "\(title): önerilen \(fmt(v)) \(t.unit), taban hedefin (≥ \(fmt(t.value))) altında."))
            case .between:
                if let u = t.upperValue, v > u {
                    out.append(Issue(severity: .blocker,
                        text: "\(title): önerilen \(fmt(v)) \(t.unit), kabul bandının üstünde (\(fmt(t.value))–\(fmt(u)))."))
                } else if v < t.value {
                    out.append(Issue(severity: .warning,
                        text: "\(title): önerilen \(fmt(v)) \(t.unit), kabul bandının altında (\(fmt(t.value))–\(fmt(t.upperValue ?? t.value)))."))
                }
            default: break
            }
        }

        // 3) Kaçınılacaklar listesi
        let haystack = (p.summary + " " + p.rationale + " " +
                        p.items.map { $0.title + " " + $0.detail }.joined(separator: " ")).lowercased()
        for term in context.avoid + context.intolerances where !term.isEmpty {
            if haystack.contains(term.lowercased()) {
                out.append(Issue(severity: .blocker,
                    text: "Öneride \"\(term)\" geçiyor — kaçınılacaklar/intolerans listende."))
            }
        }

        // 4) Tek değişken kuralı
        if phaseSettings.enabled {
            let newCount = p.items.filter { $0.action == "add" }.count
            if newCount > 2 {
                out.append(Issue(severity: .warning,
                    text: "\(newCount) yeni öğe öneriliyor. Tek değişken kuralı gereği aynı anda 1–2 değişiklik daha sağlıklı — seçerek uygula."))
            }
        }

        // 5) Sessiz saat çakışması
        for item in p.items {
            for t in item.timesParsed where notifSettings.isQuiet(t) {
                out.append(Issue(severity: .info,
                    text: "\"\(item.title)\" \(t.label) sessiz saatlere düşüyor — bildirim kurulmaz."))
            }
        }

        // 6) Şema sağlığı
        for item in p.items {
            if PlanCategory(rawValue: item.category) == nil {
                out.append(Issue(severity: .warning,
                    text: "\"\(item.title)\" için bilinmeyen kategori (\(item.category)) — öğün olarak alınacak."))
            }
            if item.times.count != item.timesParsed.count {
                out.append(Issue(severity: .warning,
                    text: "\"\(item.title)\" saatlerinden bazıları okunamadı."))
            }
        }

        // 7) Ekipman dışı hareket
        if !context.equipment.isEmpty {
            let equip = context.equipment.map { $0.lowercased() }
            for w in p.workoutChanges {
                for ex in w.exercises {
                    let n = ex.name.lowercased()
                    let known = ["barbell", "dumbbell", "halter", "dambıl", "kettlebell", "makine", "kablo", "cable"]
                    if let hit = known.first(where: { n.contains($0) }),
                       !equip.contains(where: { $0.contains(hit) }) {
                        out.append(Issue(severity: .info,
                            text: "\"\(ex.name)\" ekipman listende görünmeyen bir araç gerektirebilir."))
                    }
                }
            }
        }

        // 8) Bildirim yükü
        let addedNotifications = p.items.filter { $0.action == "add" }
            .reduce(0) { $0 + max(1, $1.timesParsed.count) }
        if addedNotifications > 6 {
            out.append(Issue(severity: .warning,
                text: "Bu öneri günlük \(addedNotifications) yeni hatırlatma noktası ekliyor — bildirim yorgunluğu riski."))
        }

        // 9) Çakışan başlık
        for item in p.items where item.action == "add" {
            if existingItems.contains(where: { $0.title.lowercased() == item.title.lowercased() }) {
                out.append(Issue(severity: .info,
                    text: "\"\(item.title)\" adında bir öğe zaten var — kopya oluşabilir."))
            }
        }

        return out
    }

    // MARK: Yardımcılar
    private static func targetValue(for rule: GuardrailRule, in t: ProposedTargets?) -> Double? {
        guard let t else { return nil }
        switch rule.kind {
        case .percentOfEnergy where rule.targetId == "satFat": return t.satFatPctEnergy
        case .metricThreshold:
            switch rule.targetId {
            case "protein":  return t.proteinG
            case "sodium":   return t.sodiumMg
            case "fiber":    return t.fiberG
            case "calories": return t.kcal
            case "carbs":    return t.carbG
            case "fat":      return t.fatG
            default:         return nil
            }
        default: return nil
        }
    }

    private static func satisfies(_ v: Double, _ rule: GuardrailRule) -> Bool {
        switch rule.op {
        case .atLeast: return v >= rule.value
        case .atMost:  return v <= rule.value
        case .between: return v >= rule.value && v <= (rule.value2 ?? rule.value)
        }
    }

    private static func sourceLabel(_ s: TargetEngine.TargetSource) -> String {
        switch s {
        case .guardrailRule: return "kuralın"
        case .tdeeEngine:    return "TDEE"
        case .catalog:       return "yedek katalog"
        case .none:          return "yok"
        }
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
