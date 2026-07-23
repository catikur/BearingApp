import Foundation

/// İki metriğin aynı güne (veya gecikmeli güne) eşlenmiş değeri
struct PairedPoint: Identifiable {
    let id = UUID()
    let date: Date
    let x: Double
    let y: Double
}

enum Stats {

    /// Günlük seriden gün->değer haritası (aynı güne birden çok örnek varsa sonuncusu)
    static func dailyMap(_ s: [MetricSample]) -> [Date: Double] {
        let cal = Calendar.current
        var m: [Date: Double] = [:]
        for v in s { m[cal.startOfDay(for: v.date)] = v.value }
        return m
    }

    /// x gününü y'nin (gün + lagDays) değeriyle eşle.
    /// lag = 0 → aynı gün, lag = 1 → "x bugün, y yarın" (gecikmeli etki)
    static func pair(_ x: [MetricSample], _ y: [MetricSample], lagDays: Int) -> [PairedPoint] {
        let cal = Calendar.current
        let xm = dailyMap(x), ym = dailyMap(y)
        var out: [PairedPoint] = []
        for (d, xv) in xm {
            guard let t = cal.date(byAdding: .day, value: lagDays, to: d) else { continue }
            if let yv = ym[cal.startOfDay(for: t)] {
                out.append(PairedPoint(date: d, x: xv, y: yv))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Pearson korelasyon katsayısı (-1…+1)
    static func pearson(_ pts: [PairedPoint]) -> Double? {
        guard pts.count >= 3 else { return nil }
        let n = Double(pts.count)
        let mx = pts.reduce(0) { $0 + $1.x } / n
        let my = pts.reduce(0) { $0 + $1.y } / n
        var num = 0.0, dx2 = 0.0, dy2 = 0.0
        for p in pts {
            let dx = p.x - mx, dy = p.y - my
            num += dx * dy; dx2 += dx * dx; dy2 += dy * dy
        }
        guard dx2 > 0, dy2 > 0 else { return nil }   // sabit seri → korelasyon tanımsız
        return num / (dx2 * dy2).squareRoot()
    }

    /// Trend çizgisi için basit doğrusal regresyon
    static func linreg(_ pts: [PairedPoint]) -> (slope: Double, intercept: Double)? {
        guard pts.count >= 3 else { return nil }
        let n = Double(pts.count)
        let mx = pts.reduce(0) { $0 + $1.x } / n
        let my = pts.reduce(0) { $0 + $1.y } / n
        var num = 0.0, den = 0.0
        for p in pts { num += (p.x - mx) * (p.y - my); den += (p.x - mx) * (p.x - mx) }
        guard den > 0 else { return nil }
        let slope = num / den
        return (slope, my - slope * mx)
    }

    static func strengthLabel(_ r: Double) -> String {
        switch abs(r) {
        case 0.7...:      return "güçlü"
        case 0.5..<0.7:   return "orta-güçlü"
        case 0.3..<0.5:   return "orta"
        case 0.15..<0.3:  return "zayıf"
        default:          return "yok denecek kadar zayıf"
        }
    }

    /// Kaba güven notu: n küçükse zayıf korelasyon gürültü olabilir
    static func confidenceNote(r: Double, n: Int) -> String {
        if n < 10 { return "Örneklem çok küçük (n=\(n)) — fikir verir, kanıt değil." }
        if abs(r) < 0.3 { return "İlişki zayıf; günlük dalgalanma bunu açıklayabilir." }
        if n < 20 { return "Örneklem sınırlı (n=\(n)) — trend olarak izle." }
        return "Örneklem makul (n=\(n)) — yine de korelasyon nedensellik değildir."
    }
}

/// Otomatik örüntü tarama: tüm metrik çiftlerini ve etiket etkilerini sıralar.
enum PatternScan {

    // MARK: Metrik ↔ metrik bulgusu
    struct Finding: Identifiable {
        let xId: String, yId: String
        let lag: Int
        let r: Double
        let n: Int
        var id: String { "\(xId)>\(yId)@\(lag)" }
    }

    /// Aynı şeyi ölçen "ikizler" — korelasyonları trivial (r≈1), listeyi kirletir.
    /// Ayarlar'dan kapatılabilir; kapatınca bu çiftler de listeye girer.
    static let twinGroups: [[String]] = [
        ["hrv", "whoop_hrv"],
        ["rhr", "whoop_rhr"],
        ["weight", "whoop_weight"],
        ["sleep", "whoop_sleepDuration"],
        ["respRate", "whoop_respRate"],
        ["spo2", "whoop_spo2"],
        ["activeEnergy", "whoop_calories"],
        ["calories", "whoop_calories"],
        ["whoop_strain", "whoop_workoutStrain"],
        ["exerciseTime", "whoop_workoutCount"],
    ]

    /// Mekanik olarak birbirinin parçası olan aileler (ör. uyku evreleri ↔ toplam uyku).
    /// Ayarlar'dan kapatılabilir.
    static let familyGroups: [[String]] = [
        ["sleep", "whoop_sleepDuration", "whoop_deepSleep", "whoop_remSleep",
         "whoop_lightSleep", "whoop_awakeTime", "whoop_sleepEff", "whoop_sleepPerf", "whoop_sleepNeed"],
        ["weight", "bmi", "bodyfat", "leanMass", "whoop_weight"],
        ["bpSys", "bpDia"],
    ]

    private static func isTrivial(_ a: String, _ b: String,
                                  filterTwins: Bool, filterFamilies: Bool) -> Bool {
        if filterTwins, twinGroups.contains(where: { $0.contains(a) && $0.contains(b) }) { return true }
        if filterFamilies, familyGroups.contains(where: { $0.contains(a) && $0.contains(b) }) { return true }
        return false
    }

    struct ScanResult {
        let findings: [Finding]
        let hiddenTrivial: Int      // filtre yüzünden gizlenen çift sayısı (şeffaflık için)
    }

    /// Tüm çiftleri tara. Filtreler ve eşikler kullanıcı ayarlarından gelir.
    static func scan(series: [String: [MetricSample]],
                     settings: EngineSettings) -> ScanResult {
        let lags = settings.discoveryScanNextDay ? [0, 1] : [0]
        let ids = series.keys.sorted()
        var out: [Finding] = []
        var hidden = 0

        for lag in lags {
            for (i, a) in ids.enumerated() {
                for (j, b) in ids.enumerated() {
                    if a == b { continue }
                    if lag == 0 && j <= i { continue }        // aynı gün: (a,b)==(b,a), tekrar etme
                    if isTrivial(a, b,
                                 filterTwins: settings.discoveryFilterTwins,
                                 filterFamilies: settings.discoveryFilterFamilies) {
                        hidden += 1; continue
                    }
                    guard let sa = series[a], let sb = series[b] else { continue }
                    let pts = pair(sa, sb, lag: lag)
                    guard pts.count >= settings.discoveryMinN, let r = Stats.pearson(pts) else { continue }
                    out.append(Finding(xId: a, yId: b, lag: lag, r: r, n: pts.count))
                }
            }
        }
        return ScanResult(findings: out.sorted { abs($0.r) > abs($1.r) }, hiddenTrivial: hidden)
    }

    private static func pair(_ a: [MetricSample], _ b: [MetricSample], lag: Int) -> [PairedPoint] {
        Stats.pair(a, b, lagDays: lag)
    }

    // MARK: Etiket → metrik bulgusu
    struct TagFinding: Identifiable {
        let tagId: String, metricId: String
        let on: Double, off: Double
        let n: Int
        let lag: Int
        var id: String { "\(tagId)>\(metricId)@\(lag)" }
        var delta: Double { on - off }
        var deltaPct: Double { off == 0 ? 0 : (on - off) / abs(off) * 100 }
    }

    /// Etiketli günler ile diğer günlerin ortalamasını her metrik için karşılaştır.
    /// tagDates: etiket id -> o etiketin işaretlendiği günler (gün başı)
    static func scanTags(series: [String: [MetricSample]],
                         tagDates: [String: Set<Date>],
                         settings: EngineSettings,
                         minN: Int = 3) -> [TagFinding] {
        let cal = Calendar.current
        let lags = settings.discoveryScanNextDay ? [0, 1] : [0]
        var out: [TagFinding] = []
        for (tagId, days) in tagDates where !days.isEmpty {
            for lag in lags {
                // lag = 1 → etiketin ERTESİ günü etkile
                let shifted: Set<Date> = lag == 0 ? days : Set(days.compactMap {
                    cal.date(byAdding: .day, value: lag, to: $0).map { cal.startOfDay(for: $0) }
                })
                for (mid, s) in series where !s.isEmpty {
                    var on: [Double] = [], off: [Double] = []
                    for v in s {
                        if shifted.contains(cal.startOfDay(for: v.date)) { on.append(v.value) }
                        else { off.append(v.value) }
                    }
                    guard on.count >= minN, off.count >= minN else { continue }
                    let onAvg = on.reduce(0,+) / Double(on.count)
                    let offAvg = off.reduce(0,+) / Double(off.count)
                    out.append(TagFinding(tagId: tagId, metricId: mid,
                                          on: onAvg, off: offAvg, n: on.count, lag: lag))
                }
            }
        }
        return out.sorted { abs($0.deltaPct) > abs($1.deltaPct) }
    }
}
