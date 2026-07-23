import Foundation

// =====================================================================
// DETERMİNİSTİK MOTOR KATMANI
// Buradaki hiçbir hesap LLM'e devredilmez. LLM yalnızca bu çıktıları
// okuyup yorumlayabilir; sayı üretemez, yeniden hesaplayamaz.
// =====================================================================

enum Confidence: String {
    case low, medium, high
    var label: String {
        switch self {
        case .low:    return "düşük güven"
        case .medium: return "orta güven"
        case .high:   return "iyi güven"
        }
    }
}

// MARK: - Ortak yardımcılar
enum Series {
    /// Son `days` gün içindeki örnekler
    static func window(_ s: [MetricSample], days: Int, endingAt end: Date = Date()) -> [MetricSample] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end)) else { return s }
        return s.filter { $0.date >= start }.sorted { $0.date < $1.date }
    }

    /// Gün indeksine göre doğrusal regresyon eğimi (birim/gün)
    static func slopePerDay(_ s: [MetricSample]) -> Double? {
        guard s.count >= 3, let first = s.first?.date else { return nil }
        let cal = Calendar.current
        let pts: [PairedPoint] = s.map {
            let d = Double(cal.dateComponents([.day], from: cal.startOfDay(for: first),
                                              to: cal.startOfDay(for: $0.date)).day ?? 0)
            return PairedPoint(date: $0.date, x: d, y: $0.value)
        }
        return Stats.linreg(pts)?.slope
    }

    static func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0,+) / Double(v.count) }

    static func sd(_ v: [Double]) -> Double? {
        guard v.count >= 2, let m = mean(v) else { return nil }
        let varsum = v.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (varsum / Double(v.count - 1)).squareRoot()
    }
}

// MARK: - 1) Adaptif TDEE
/// Enerji dengesi yöntemi: TDEE = ortalama alım − (kilo eğimi × kcal/kg)
/// Formül tahmini değil ölçümü kullanır: gerçekte ne yediğin + gerçekte ne kadar değiştiğin.
enum TDEEEngine {

    struct Result {
        let tdee: Double                  // ölçülmüş günlük enerji harcaması
        let meanIntake: Double
        let slopeKgPerDay: Double
        let windowDays: Int
        let intakeDays: Int
        let intakeCoverage: Double        // loglanan gün oranı
        let weightSamples: Int
        let confidence: Confidence
        let bmrReference: Double          // Mifflin-St Jeor (yalnızca karşılaştırma)
        let recommendedIntake: Double     // hedef hıza göre önerilen alım
        let currentDeficit: Double        // tdee − meanIntake
    }

    static func compute(intake: [MetricSample],
                        weight: [MetricSample],
                        settings: EngineSettings,
                        profile: UserProfile) -> Result? {

        let win = settings.tdeeWindowDays
        let intakeW = Series.window(intake, days: win).filter { $0.value > 0 }
        let weightW = Series.window(weight, days: win)

        guard intakeW.count >= 3, weightW.count >= 3,
              let meanIntake = Series.mean(intakeW.map { $0.value }),
              let slope = Series.slopePerDay(weightW),
              let lastWeight = weightW.last?.value else { return nil }

        let coverage = Double(intakeW.count) / Double(win)
        let tdee = meanIntake - slope * settings.kcalPerKg

        // Güven: veri günü + log kapsaması + kilo örneklem yoğunluğu
        var conf: Confidence = .high
        if intakeW.count < settings.tdeeMinDays || coverage < settings.tdeeMinIntakeCoverage { conf = .medium }
        if intakeW.count < settings.tdeeMinDays / 2 || coverage < 0.4 || weightW.count < 5 { conf = .low }

        // Sonuç fizyolojik olarak absürtse güveni düşür (ör. log eksikliği TDEE'yi şişirir)
        let bmr = profile.bmr(weightKg: lastWeight)
        if tdee < bmr * 0.8 || tdee > bmr * 3.0 { conf = .low }

        let targetDaily = profile.targetRateKgPerWeek * settings.kcalPerKg / 7
        return Result(tdee: tdee,
                      meanIntake: meanIntake,
                      slopeKgPerDay: slope,
                      windowDays: win,
                      intakeDays: intakeW.count,
                      intakeCoverage: coverage,
                      weightSamples: weightW.count,
                      confidence: conf,
                      bmrReference: bmr,
                      recommendedIntake: tdee - targetDaily,
                      currentDeficit: tdee - meanIntake)
    }
}

// MARK: - 2) Kilo trendi (EMA) + hedefe varış
enum TrendEngine {

    struct Result {
        let smoothed: [MetricSample]      // EMA serisi
        let smoothedNow: Double
        let rawNow: Double
        let ratePerWeek: Double           // negatif = kayıp
        let rateWindowDays: Int
        let startWeight: Double
        let totalChange: Double
        let progressPct: Double?          // hedefe göre tamamlanan %
        let remainingKg: Double
        let weeksRemaining: Double?
        let etaDate: Date?
        let onTrack: Bool                 // hedef hıza göre
        let residualMAD: Double           // ham−EMA tipik sapması (projeksiyon konisi için)
    }

    /// Projeksiyon noktası: beklenen değer + belirsizlik bandı (koni)
    struct ProjectionPoint {
        let date: Date
        let expected: Double
        let low: Double
        let high: Double
    }

    /// Mevcut hızın doğrusal uzantısı + veri gürültüsünden türeyen genişleyen koni.
    /// Grafik sunumu içindir; tüm sayılar Result'tan gelir, görünüm katmanı hesap yapmaz.
    static func projection(from r: Result, horizonDays: Int) -> [ProjectionPoint] {
        guard horizonDays > 0, abs(r.ratePerWeek) >= 0.01 else { return [] }
        let cal = Calendar.current
        let perDay = r.ratePerWeek / 7
        let base = max(r.residualMAD, 0.1)
        var out: [ProjectionPoint] = []
        for d in stride(from: 0, through: horizonDays, by: max(1, horizonDays / 30)) {
            guard let date = cal.date(byAdding: .day, value: d, to: Date()) else { continue }
            let expected = r.smoothedNow + perDay * Double(d)
            // Koni √t ile genişler: yakın gelecek dar, uzak gelecek geniş
            let spread = base * (0.4 + 1.6 * (Double(d) / Double(horizonDays)).squareRoot())
            out.append(ProjectionPoint(date: date, expected: expected,
                                       low: expected - spread, high: expected + spread))
        }
        return out
    }

    static func compute(weight: [MetricSample],
                        settings: EngineSettings,
                        profile: UserProfile) -> Result? {

        let sorted = weight.sorted { $0.date < $1.date }
        guard let rawNow = sorted.last?.value, sorted.count >= 2 else { return nil }

        // EMA — yarı ömre göre alfa
        let alpha = 1 - pow(0.5, 1.0 / max(1, settings.emaHalfLifeDays))
        var ema: [MetricSample] = []
        var acc = sorted[0].value
        for s in sorted {
            acc = alpha * s.value + (1 - alpha) * acc
            ema.append(MetricSample(date: s.date, value: acc))
        }
        guard let smoothedNow = ema.last?.value else { return nil }

        // Hız: EMA üzerinde regresyon (ham veri gürültülü)
        let rateWin = Series.window(ema, days: settings.rateWindowDays)
        let perDay = Series.slopePerDay(rateWin) ?? 0
        let perWeek = perDay * 7

        let startWeight = profile.startWeightKg ?? sorted.first?.value ?? rawNow
        let total = smoothedNow - startWeight
        let target = profile.targetWeightKg
        let remaining = smoothedNow - target

        var progress: Double? = nil
        let span = startWeight - target
        if abs(span) > 0.1 { progress = max(0, min(100, (startWeight - smoothedNow) / span * 100)) }

        // Varış tahmini yalnızca doğru yönde anlamlı hız varsa
        var weeks: Double? = nil
        var eta: Date? = nil
        if abs(remaining) > 0.2, perWeek != 0, (remaining > 0) == (perWeek < 0), abs(perWeek) >= 0.05 {
            let w = abs(remaining / perWeek)
            weeks = w
            eta = Calendar.current.date(byAdding: .day, value: Int(w * 7), to: Date())
        }

        let onTrack = abs(perWeek) >= profile.targetRateKgPerWeek * 0.7 && (remaining > 0) == (perWeek < 0)

        // Ham−EMA tipik sapması (MAD): projeksiyon konisinin genişliği buradan gelir
        let recentPairs = zip(sorted, ema).suffix(settings.rateWindowDays)
        let residuals = recentPairs.map { abs($0.0.value - $0.1.value) }
        let residualMAD = Series.mean(residuals) ?? 0.3

        return Result(smoothed: ema, smoothedNow: smoothedNow, rawNow: rawNow,
                      ratePerWeek: perWeek, rateWindowDays: settings.rateWindowDays,
                      startWeight: startWeight, totalChange: total,
                      progressPct: progress, remainingKg: remaining,
                      weeksRemaining: weeks, etaDate: eta, onTrack: onTrack,
                      residualMAD: residualMAD)
    }
}

// MARK: - 3) Kişisel baseline & sapma
/// Her metrik kendi geçmişiyle karşılaştırılır — popülasyon normuyla değil.
enum BaselineEngine {

    struct Deviation: Identifiable {
        let metricId: String
        let today: Double
        let mean: Double
        let sd: Double
        let z: Double
        let concerning: Bool     // metriğin "iyi yönü"ne göre kötü tarafta mı
        let samples: Int
        var id: String { metricId }
    }

    struct Composite {
        let firing: [String]
        let needed: Int
        let triggered: Bool
    }

    /// Bugünü, kendisi hariç son N günün ortalama/SD'siyle karşılaştır.
    static func deviation(for id: String,
                          series: [MetricSample],
                          settings: EngineSettings) -> Deviation? {
        let w = Series.window(series, days: settings.baselineWindowDays)
        guard w.count >= settings.baselineMinSamples, let today = w.last else { return nil }
        let history = w.dropLast().map { $0.value }     // bugünü baseline'a katma
        guard history.count >= settings.baselineMinSamples - 1,
              let m = Series.mean(history), let s = Series.sd(history), s > 0 else { return nil }

        let z = (today.value - m) / s
        let higherIsBetter = HealthMetricCatalog.byId(id)?.higherIsBetter ?? true
        let badDirection = higherIsBetter ? (z < 0) : (z > 0)
        let concerning = badDirection && abs(z) >= settings.baselineZThreshold

        return Deviation(metricId: id, today: today.value, mean: m, sd: s, z: z,
                         concerning: concerning, samples: history.count)
    }

    static func evaluate(series: [String: [MetricSample]],
                         settings: EngineSettings) -> [Deviation] {
        settings.baselineMetricIds.compactMap { id in
            guard let s = series[id], !s.isEmpty else { return nil }
            return deviation(for: id, series: s, settings: settings)
        }
        .sorted { abs($0.z) > abs($1.z) }
    }

    /// Bileşik sinyal: birden çok metrik aynı anda kötü yönde saparsa
    static func composite(series: [String: [MetricSample]],
                          settings: EngineSettings) -> Composite {
        var firing: [String] = []
        for id in settings.compositeMetricIds {
            guard let s = series[id], let d = deviation(for: id, series: s, settings: settings) else { continue }
            if d.concerning { firing.append(id) }
        }
        return Composite(firing: firing,
                         needed: settings.compositeMinFiring,
                         triggered: firing.count >= settings.compositeMinFiring)
    }
}

// MARK: - 4) Guardrail uyum skoru
enum GuardrailEngine {

    struct RuleResult: Identifiable {
        let rule: GuardrailRule
        let compliantDays: Int
        let evaluatedDays: Int
        let compliancePct: Double
        let avgValue: Double?
        let failures: [Date]
        var id: UUID { rule.id }
        var hasData: Bool { evaluatedDays > 0 }
    }

    struct Summary {
        let score: Double            // ağırlıklı ortalama uyum %
        let results: [RuleResult]
        let windowDays: Int
        let rulesWithData: Int
    }

    static func evaluate(rules: [GuardrailRule],
                         series: [String: [MetricSample]],
                         tagDates: [String: Set<Date>],
                         settings: EngineSettings,
                         planAdherence: [String: Double] = [:]) -> Summary {

        let win = settings.guardrailWindowDays
        var results: [RuleResult] = []

        for rule in rules where rule.enabled {
            switch rule.kind {
            case .metricThreshold:
                results.append(evalMetric(rule, series: series, win: win, transform: nil))

            case .percentOfEnergy:
                // değer = (gram × kcal/g) ÷ toplam kalori × 100
                guard let cal = series["calories"] else {
                    results.append(empty(rule)); continue
                }
                let calMap = Stats.dailyMap(cal)
                results.append(evalMetric(rule, series: series, win: win) { date, grams in
                    guard let kcal = calMap[Calendar.current.startOfDay(for: date)], kcal > 0 else { return nil }
                    return grams * rule.kcalPerGram / kcal * 100
                })

            case .tagFrequency:
                results.append(evalTagFrequency(rule, tagDates: tagDates, win: win))

            case .planAdherence:
                guard let pct = planAdherence[rule.targetId] else {
                    results.append(empty(rule)); continue
                }
                let ok = passes(pct, rule)
                results.append(RuleResult(rule: rule,
                                          compliantDays: ok ? 1 : 0,
                                          evaluatedDays: 1,
                                          compliancePct: ok ? 100 : pct,
                                          avgValue: pct,
                                          failures: []))
            }
        }

        let withData = results.filter { $0.hasData }
        let totalW = withData.reduce(0) { $0 + $1.rule.weight }
        let score = totalW > 0
            ? withData.reduce(0) { $0 + $1.compliancePct * $1.rule.weight } / totalW
            : 0

        return Summary(score: score, results: results, windowDays: win, rulesWithData: withData.count)
    }

    // MARK: Kural değerlendirme
    private static func passes(_ v: Double, _ rule: GuardrailRule) -> Bool {
        switch rule.op {
        case .atLeast: return v >= rule.value
        case .atMost:  return v <= rule.value
        case .between: return v >= rule.value && v <= (rule.value2 ?? rule.value)
        }
    }

    private static func evalMetric(_ rule: GuardrailRule,
                                   series: [String: [MetricSample]],
                                   win: Int,
                                   transform: ((Date, Double) -> Double?)? = nil) -> RuleResult {
        guard let s = series[rule.targetId] else { return empty(rule) }
        let w = Series.window(s, days: win)
        var ok = 0, total = 0
        var vals: [Double] = []
        var fails: [Date] = []
        for sample in w {
            let raw: Double?
            if let t = transform { raw = t(sample.date, sample.value) } else { raw = sample.value }
            guard let v = raw else { continue }
            total += 1; vals.append(v)
            if passes(v, rule) { ok += 1 } else { fails.append(sample.date) }
        }
        return RuleResult(rule: rule,
                          compliantDays: ok,
                          evaluatedDays: total,
                          compliancePct: total > 0 ? Double(ok) / Double(total) * 100 : 0,
                          avgValue: Series.mean(vals),
                          failures: fails.sorted(by: >))
    }

    /// Etiket sıklığı: pencereyi 7 günlük bloklara böl, her blokta etiket sayısını kuralla karşılaştır
    private static func evalTagFrequency(_ rule: GuardrailRule,
                                         tagDates: [String: Set<Date>],
                                         win: Int) -> RuleResult {
        let cal = Calendar.current
        guard let days = tagDates[rule.targetId] else { return empty(rule) }
        let weeks = max(1, win / 7)
        var ok = 0
        var counts: [Double] = []
        var fails: [Date] = []
        for w in 0..<weeks {
            guard let end = cal.date(byAdding: .day, value: -(w * 7), to: cal.startOfDay(for: Date())),
                  let start = cal.date(byAdding: .day, value: -7, to: end) else { continue }
            let n = days.filter { $0 > start && $0 <= end }.count
            counts.append(Double(n))
            if passes(Double(n), rule) { ok += 1 } else { fails.append(end) }
        }
        return RuleResult(rule: rule,
                          compliantDays: ok,
                          evaluatedDays: weeks,
                          compliancePct: Double(ok) / Double(weeks) * 100,
                          avgValue: Series.mean(counts),
                          failures: fails)
    }

    private static func empty(_ rule: GuardrailRule) -> RuleResult {
        RuleResult(rule: rule, compliantDays: 0, evaluatedDays: 0,
                   compliancePct: 0, avgValue: nil, failures: [])
    }

    // MARK: Bugünün durumu (14 günlük uyumdan ayrı — "şu an ne durumdayım")
    struct TodayStatus {
        let ruleId: UUID
        let value: Double?     // bugünkü ölçülen değer (percentOfEnergy grama değil %'ye çevrili)
        let passes: Bool
        let hasData: Bool
        let period: String     // "bugün" | "bu hafta" | "dönem"
    }

    static func todayStatus(_ rule: GuardrailRule,
                            series: [String: [MetricSample]],
                            tagDates: [String: Set<Date>],
                            planAdherence: [String: Double]) -> TodayStatus {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func todaySum(_ id: String) -> Double? {
            guard let s = series[id] else { return nil }
            let vals = s.filter { cal.startOfDay(for: $0.date) == today }.map { $0.value }
            return vals.isEmpty ? nil : vals.reduce(0, +)
        }
        func none(_ period: String) -> TodayStatus {
            TodayStatus(ruleId: rule.id, value: nil, passes: false, hasData: false, period: period)
        }

        switch rule.kind {
        case .metricThreshold:
            guard let v = todaySum(rule.targetId) else { return none("bugün") }
            return TodayStatus(ruleId: rule.id, value: v, passes: passes(v, rule),
                               hasData: true, period: "bugün")

        case .percentOfEnergy:
            guard let grams = todaySum(rule.targetId),
                  let kcal = todaySum("calories"), kcal > 0 else { return none("bugün") }
            let pct = grams * rule.kcalPerGram / kcal * 100
            return TodayStatus(ruleId: rule.id, value: pct, passes: passes(pct, rule),
                               hasData: true, period: "bugün")

        case .tagFrequency:
            // Haftalık kural: son 7 gün (bugün dahil) sayımı. Etiket yoksa 0 meşrudur.
            guard let start = cal.date(byAdding: .day, value: -6, to: today) else { return none("bu hafta") }
            let n = (tagDates[rule.targetId] ?? []).filter { $0 >= start && $0 <= today }.count
            return TodayStatus(ruleId: rule.id, value: Double(n), passes: passes(Double(n), rule),
                               hasData: true, period: "bu hafta")

        case .planAdherence:
            guard let pct = planAdherence[rule.targetId] else { return none("dönem") }
            return TodayStatus(ruleId: rule.id, value: pct, passes: passes(pct, rule),
                               hasData: true, period: "dönem")
        }
    }

    static func todayStatuses(rules: [GuardrailRule],
                              series: [String: [MetricSample]],
                              tagDates: [String: Set<Date>],
                              planAdherence: [String: Double] = [:]) -> [UUID: TodayStatus] {
        var out: [UUID: TodayStatus] = [:]
        for rule in rules where rule.enabled {
            out[rule.id] = todayStatus(rule, series: series, tagDates: tagDates, planAdherence: planAdherence)
        }
        return out
    }
}

// MARK: - 5) Hedef çözümleyici (kanonik hedef kaynağı)
/// Bir metriğin "gerçek" günlük hedefini tek yerden çözer. Aynı metrik için
/// hedef üç ayrı yerde tanımlı olabilir (kullanıcının GuardrailRule'u, TDEE motoru,
/// katalog yedeği). Bu motor önceliği belirler ki kart, Bugün bloğu ve LLM bağlamı
/// AYNI sayıyı kullansın. Uydurma hedef üretmez — çözülemeyen metrik hedefsizdir.
enum TargetEngine {

    /// Hedefin nereden geldiği — arayüz bunu ince bir işaretle gösterir.
    enum TargetSource { case guardrailRule, tdeeEngine, catalog, none }

    struct ResolvedTarget {
        let metricId: String
        let value: Double              // ana eşik (.between için alt sınır)
        let upperValue: Double?        // yalnızca .between için üst sınır
        let direction: RuleOperator    // atLeast | atMost | between
        let source: TargetSource
        let unit: String
        let derivedNote: String?       // ör. "%7 enerji ≈ 18 g" gibi türetme açıklaması
    }

    /// Çözümleme sırası (harfiyen): kullanıcı kuralı → enerji yüzdesi → TDEE → katalog → yok.
    static func resolve(metricId: String,
                        rules: [GuardrailRule],
                        tdee: TDEEEngine.Result?,
                        profile: UserProfile) -> ResolvedTarget? {

        let unit = HealthMetricCatalog.byId(metricId)?.unit ?? ""

        // 1) Etkin metrik eşiği kuralı — kanonik kaynak.
        if let rule = rules.first(where: {
            $0.enabled && $0.kind == .metricThreshold && $0.targetId == metricId
        }) {
            return ResolvedTarget(metricId: metricId, value: rule.value,
                                  upperValue: rule.value2, direction: rule.op,
                                  source: .guardrailRule, unit: unit, derivedNote: nil)
        }

        // 2) Enerji yüzdesi kuralı (ör. doymuş yağ ≤ %7) → grama çevir.
        //    Kalori hedefi 3. adımdan gelir; mutfakta gram lazım, yüzde değil.
        //    (targetId == "calories" ise özyinelemeye girmemek için atla.)
        if metricId != "calories",
           let rule = rules.first(where: {
               $0.enabled && $0.kind == .percentOfEnergy && $0.targetId == metricId
           }),
           rule.kcalPerGram > 0,
           let kcalTarget = resolve(metricId: "calories", rules: rules,
                                    tdee: tdee, profile: profile)?.value {
            let grams = kcalTarget * rule.value / 100 / rule.kcalPerGram
            let note = "%\(fmtInt(rule.value)) enerji ≈ \(fmtInt(grams)) \(unit)"
            return ResolvedTarget(metricId: metricId, value: grams,
                                  upperValue: nil, direction: rule.op,
                                  source: .guardrailRule, unit: unit, derivedNote: note)
        }

        // 3) Kalori → TDEE motorunun önerdiği alım. Yön profil hedefinden gelir.
        if metricId == "calories", let tdee = tdee {
            let rate = profile.targetRateKgPerWeek
            // "Sıfıra çok yakın" = koruma; bakım kalorisi ±%5 bandı olarak gösterilir.
            let maintenanceEpsilon = 0.05          // kg/hafta — yön kararı için, hedef değil
            let value = tdee.recommendedIntake
            if abs(rate) < maintenanceEpsilon {
                return ResolvedTarget(metricId: metricId, value: value * 0.95,
                                      upperValue: value * 1.05, direction: .between,
                                      source: .tdeeEngine, unit: unit, derivedNote: nil)
            }
            // rate > 0 → kilo kaybı → alım bir tavan (.atMost); rate < 0 → alım (.atLeast)
            let dir: RuleOperator = rate > 0 ? .atMost : .atLeast
            return ResolvedTarget(metricId: metricId, value: value, upperValue: nil,
                                  direction: dir, source: .tdeeEngine,
                                  unit: unit, derivedNote: nil)
        }

        // 4) Katalog gömülü hedefi — yalnızca kullanıcı kuralı yokken devreye giren yedek.
        if let def = HealthMetricCatalog.byId(metricId), let target = def.target {
            return ResolvedTarget(metricId: metricId, value: target, upperValue: nil,
                                  direction: def.higherIsBetter ? .atLeast : .atMost,
                                  source: .catalog, unit: unit, derivedNote: nil)
        }

        // 5) Hiçbiri yok — uydurma yapma.
        return nil
    }

    /// Toplu çözümleme: verilen metriklerin hepsini tek seferde çöz.
    static func resolveAll(metricIds: [String],
                           rules: [GuardrailRule],
                           tdee: TDEEEngine.Result?,
                           profile: UserProfile) -> [String: ResolvedTarget] {
        var out: [String: ResolvedTarget] = [:]
        for id in metricIds {
            if let t = resolve(metricId: id, rules: rules, tdee: tdee, profile: profile) {
                out[id] = t
            }
        }
        return out
    }

    private static func fmtInt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - 6) Günün ilerlemesi (bugüne kadar, 7 günlük ortalama DEĞİL)
enum ProgressState { case belowTarget, atTarget, overTarget, noTarget }

struct DayProgress {
    let metricId: String
    let today: Double              // bugünün toplamı/değeri
    let target: TargetEngine.ResolvedTarget?
    let ratio: Double              // today / target.value (yön yorumu view'da)
    let remaining: Double          // yöne göre anlamı değişir (bkz. compute)
    let state: ProgressState
}

enum ProgressEngine {

    /// Bugünün değerini metriğin toplama tipine göre hesaplar.
    /// Veri yoksa 0 döner — sıfır meşru bir değerdir, "veri yok" değil.
    static func todayValue(_ series: [MetricSample],
                           aggregation: Aggregation,
                           now: Date = Date()) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let todays = series.filter { cal.startOfDay(for: $0.date) == start }
        if todays.isEmpty { return 0 }
        switch aggregation {
        case .average:
            return Series.mean(todays.map { $0.value }) ?? 0
        case .latest, .whoop:
            return todays.sorted { $0.date < $1.date }.last?.value ?? 0
        case .sum, .sleepHours:
            return todays.reduce(0) { $0 + $1.value }
        }
    }

    /// Bir metrik için bugünkü ilerleme. Yön davranışı DayProgress spec'ine göre:
    /// atLeast → hedefe ulaşmak iyi; atMost → hedef bir tavan; between → kabul bandı.
    static func compute(metricId: String,
                        series: [MetricSample],
                        target: TargetEngine.ResolvedTarget?,
                        aggregation: Aggregation,
                        now: Date = Date()) -> DayProgress {

        let today = todayValue(series, aggregation: aggregation, now: now)

        guard let t = target else {
            return DayProgress(metricId: metricId, today: today, target: nil,
                               ratio: 0, remaining: 0, state: .noTarget)
        }

        let ratio = t.value > 0 ? today / t.value : 0

        switch t.direction {
        case .atLeast:
            // Hedefe ulaşmak iyi; aşmak sorun değil. Kalan = hedefe kalan miktar.
            let remaining = max(0, t.value - today)
            let state: ProgressState = today >= t.value ? .atTarget : .belowTarget
            return DayProgress(metricId: metricId, today: today, target: t,
                               ratio: ratio, remaining: remaining, state: state)

        case .atMost:
            // Hedef bir tavan. Kalan = kalan bütçe (negatif = aşım). %100 başarı değil.
            let remaining = t.value - today
            let state: ProgressState = today > t.value ? .overTarget : .atTarget
            return DayProgress(metricId: metricId, today: today, target: t,
                               ratio: ratio, remaining: remaining, state: state)

        case .between:
            // Kabul bandı: altı belowTarget, içi atTarget, üstü overTarget.
            let upper = t.upperValue ?? t.value
            let state: ProgressState
            let remaining: Double
            if today < t.value {
                state = .belowTarget
                remaining = t.value - today          // banda ulaşmak için kalan (pozitif)
            } else if today > upper {
                state = .overTarget
                remaining = upper - today            // bandın üstünde aşım (negatif)
            } else {
                state = .atTarget
                remaining = 0
            }
            return DayProgress(metricId: metricId, today: today, target: t,
                               ratio: ratio, remaining: remaining, state: state)
        }
    }

    /// Toplu: verilen metriklerin hepsi için bugünkü ilerleme.
    static func computeAll(metricIds: [String],
                           series: [String: [MetricSample]],
                           rules: [GuardrailRule],
                           tdee: TDEEEngine.Result?,
                           profile: UserProfile,
                           now: Date = Date()) -> [DayProgress] {
        metricIds.map { id in
            let target = TargetEngine.resolve(metricId: id, rules: rules,
                                              tdee: tdee, profile: profile)
            let agg = HealthMetricCatalog.byId(id)?.aggregation ?? .sum
            return compute(metricId: id, series: series[id] ?? [],
                           target: target, aggregation: agg, now: now)
        }
    }
}

// MARK: - Tek kaynak: tüm motor çıktıları
/// Kartlar, detay ekranları ve LLM bağlamı AYNI hesaplamayı kullansın diye
/// bütün motorlar buradan tek seferde çalıştırılır.
struct EngineOutputs {
    let tdee: TDEEEngine.Result?
    let trend: TrendEngine.Result?
    let deviations: [BaselineEngine.Deviation]
    let composite: BaselineEngine.Composite
    let guardrails: GuardrailEngine.Summary

    static func compute(series: [String: [MetricSample]],
                        profile: UserProfile,
                        settings: EngineSettings,
                        rules: [GuardrailRule],
                        tagDates: [String: Set<Date>],
                        planAdherence: [String: Double] = [:]) -> EngineOutputs {
        EngineOutputs(
            tdee: TDEEEngine.compute(intake: series["calories"] ?? [],
                                     weight: series["weight"] ?? [],
                                     settings: settings, profile: profile),
            trend: TrendEngine.compute(weight: series["weight"] ?? [],
                                       settings: settings, profile: profile),
            deviations: BaselineEngine.evaluate(series: series, settings: settings),
            composite: BaselineEngine.composite(series: series, settings: settings),
            guardrails: GuardrailEngine.evaluate(rules: rules, series: series,
                                                 tagDates: tagDates, settings: settings,
                                                 planAdherence: planAdherence)
        )
    }
}
