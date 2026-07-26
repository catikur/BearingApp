import Testing
import Foundation
@testable import Bearing

// =====================================================================
// DETERMİNİSTİK MOTOR TESTLERİ (anayasa §6 — F2)
// Motorlar `now:`/sabit girdilerle test edilebilir yazılmıştı; bu dosya
// o sözleşmeyi kullanır. UI test edilmez; yalnız sayısal davranış.
// =====================================================================

// MARK: - Yardımcılar

/// Bugünden geriye `values.count` günlük seri üretir (values[son] = bugün).
private func series(_ values: [Double], endingToday: Bool = true) -> [MetricSample] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    return values.enumerated().map { i, v in
        let offset = -(values.count - 1 - i)
        return MetricSample(date: cal.date(byAdding: .day, value: offset, to: today)!, value: v)
    }
}

/// Sabit bir güne öğle saatinde damga (ProgressEngine testleri için).
private func fixedDay(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = hour
    return Calendar.current.date(from: c)!
}

private func approx(_ a: Double, _ b: Double, tol: Double = 0.05) -> Bool { abs(a - b) <= tol }

private func defaultSettings() -> EngineSettings { EngineSettings() }
private func defaultProfile() -> UserProfile { UserProfile() }

// MARK: - Series

@Suite("Series yardımcıları")
struct SeriesTests {
    @Test func meanVeSd() {
        #expect(Series.mean([2, 4, 6]) == 4)
        #expect(Series.mean([]) == nil)
        // Örneklem SD (n-1): [2,4,6] → 2
        #expect(approx(Series.sd([2, 4, 6]) ?? -1, 2))
        #expect(Series.sd([5]) == nil)
    }

    @Test func dogrusalSeridenEgim() {
        // Günde +0,5 artan seri → eğim ≈ 0,5/gün
        let s = series((0..<10).map { Double($0) * 0.5 })
        #expect(approx(Series.slopePerDay(s) ?? -1, 0.5, tol: 0.01))
    }
}

// MARK: - TDEE

@Suite("TDEEEngine")
struct TDEETests {
    @Test func sabitKiloVeAlimda_tdeeAlimaEsit() {
        // 21 gün 2000 kcal + sabit kilo → TDEE = 2000, açık 0
        let intake = series(Array(repeating: 2000, count: 21))
        let weight = series(Array(repeating: 90, count: 21))
        let r = TDEEEngine.compute(intake: intake, weight: weight,
                                   settings: defaultSettings(), profile: defaultProfile())
        #expect(r != nil)
        #expect(approx(r!.tdee, 2000, tol: 1))
        #expect(approx(r!.currentDeficit, 0, tol: 1))
        #expect(r!.confidence == .high)
        // Önerilen alım = TDEE − hedef hız enerjisi (0,6 kg/hafta × 7700 / 7 = 660)
        #expect(approx(r!.recommendedIntake, 2000 - 660, tol: 1))
    }

    @Test func kiloKaybindaTdeeYukselir() {
        // Günde 0,05 kg kayıp + 2000 kcal → TDEE ≈ 2000 + 0,05×7700 = 2385
        let intake = series(Array(repeating: 2000, count: 21))
        let weight = series((0..<21).map { 91 - Double($0) * 0.05 })
        let r = TDEEEngine.compute(intake: intake, weight: weight,
                                   settings: defaultSettings(), profile: defaultProfile())
        #expect(r != nil)
        #expect(approx(r!.tdee, 2385, tol: 15))
        #expect(r!.slopeKgPerDay < 0)
    }

    @Test func yetersizVeriNilDoner() {
        let r = TDEEEngine.compute(intake: series([2000, 2100]),
                                   weight: series(Array(repeating: 90, count: 10)),
                                   settings: defaultSettings(), profile: defaultProfile())
        #expect(r == nil)
    }

    @Test func dusukLogKapsamasiGuveniDusurur() {
        // 21 günlük pencerede yalnız 9 log günü (kapsama ≈ 0,43) → medium
        var vals = Array(repeating: 0.0, count: 21)
        for i in stride(from: 1, to: 21, by: 2) where i < 18 { vals[i] = 2000 }  // 9 gün dolu
        let intake = series(vals)   // 0 değerler compute içinde elenir
        let weight = series(Array(repeating: 90, count: 21))
        let r = TDEEEngine.compute(intake: intake, weight: weight,
                                   settings: defaultSettings(), profile: defaultProfile())
        #expect(r != nil)
        #expect(r!.intakeDays == 9)
        #expect(r!.confidence == .medium)
    }
}

// MARK: - Trend

@Suite("TrendEngine")
struct TrendTests {
    @Test func sabitSeride_hizSifir() {
        let r = TrendEngine.compute(weight: series(Array(repeating: 88, count: 30)),
                                    settings: defaultSettings(), profile: defaultProfile())
        #expect(r != nil)
        #expect(approx(r!.smoothedNow, 88, tol: 0.01))
        #expect(approx(r!.ratePerWeek, 0, tol: 0.01))
        #expect(r!.etaDate == nil)   // hız yok → varış tahmini yok
    }

    @Test func azalanSeride_negatifHizVeEta() {
        // Günde 0,05 azalış, 60 gün: 93 → 90; hedef 85 → doğru yönde hız + ETA var
        let r = TrendEngine.compute(weight: series((0..<60).map { 93 - Double($0) * 0.05 }),
                                    settings: defaultSettings(), profile: defaultProfile())
        #expect(r != nil)
        #expect(r!.ratePerWeek < -0.2)
        #expect(r!.etaDate != nil)
        #expect(r!.remainingKg > 0)
        if let p = r!.progressPct { #expect(p > 0 && p < 100) }
    }

    @Test func projeksiyonKonisiGenisler() {
        let r = TrendEngine.compute(weight: series((0..<60).map { 93 - Double($0) * 0.05 }),
                                    settings: defaultSettings(), profile: defaultProfile())!
        let proj = TrendEngine.projection(from: r, horizonDays: 28)
        #expect(proj.count >= 2)
        // İlk nokta bugünkü düzleştirilmiş değerden başlar
        #expect(approx(proj.first!.expected, r.smoothedNow, tol: 0.01))
        // Koni genişler: son bandın yarı genişliği ilkinden büyük
        let firstSpread = proj.first!.high - proj.first!.low
        let lastSpread = proj.last!.high - proj.last!.low
        #expect(lastSpread > firstSpread)
    }

    @Test func hizYokkenProjeksiyonBos() {
        let r = TrendEngine.compute(weight: series(Array(repeating: 88, count: 30)),
                                    settings: defaultSettings(), profile: defaultProfile())!
        #expect(TrendEngine.projection(from: r, horizonDays: 28).isEmpty)
    }
}

// MARK: - Baseline

@Suite("BaselineEngine")
struct BaselineTests {
    /// 48/52 dalgalı geçmiş (ortalama 50, sd ≈ 2) üstüne bugünkü değer eklenir.
    private func hrvSeries(today: Double) -> [MetricSample] {
        var vals: [Double] = []
        for i in 0..<28 { vals.append(i % 2 == 0 ? 48 : 52) }
        vals.append(today)
        return series(vals)
    }

    @Test func belirginDusus_kaygiVerici() {
        // HRV yüksek-iyi metrik; bugün 30 → z ~ −10 → concerning
        let d = BaselineEngine.deviation(for: "hrv", series: hrvSeries(today: 30),
                                         settings: defaultSettings())
        #expect(d != nil)
        #expect(d!.z < -1.5)
        #expect(d!.concerning)
    }

    @Test func normalGun_kaygiYok() {
        let d = BaselineEngine.deviation(for: "hrv", series: hrvSeries(today: 50),
                                         settings: defaultSettings())
        #expect(d != nil)
        #expect(abs(d!.z) < 1.5)
        #expect(!d!.concerning)
    }

    @Test func iyiYondeSapma_kaygiVericiDegil() {
        // HRV'nin YÜKSELMESİ iyidir — büyük pozitif z concerning olmamalı
        let d = BaselineEngine.deviation(for: "hrv", series: hrvSeries(today: 70),
                                         settings: defaultSettings())
        #expect(d != nil)
        #expect(d!.z > 1.5)
        #expect(!d!.concerning)
    }

    @Test func azOrneklemNilDoner() {
        let d = BaselineEngine.deviation(for: "hrv", series: series([48, 52, 50]),
                                         settings: defaultSettings())
        #expect(d == nil)
    }
}

// MARK: - Target

@Suite("TargetEngine — çözümleme sırası")
struct TargetTests {
    private func tdeeFlat2000() -> TDEEEngine.Result {
        TDEEEngine.compute(intake: series(Array(repeating: 2000, count: 21)),
                           weight: series(Array(repeating: 90, count: 21)),
                           settings: defaultSettings(), profile: defaultProfile())!
    }

    @Test func kullaniciKurali_katalogdanOnceGelir() {
        // Katalog protein hedefi 175; kural 150 diyor → kural kazanır
        let rule = GuardrailRule(name: "Protein", targetId: "protein", op: .atLeast, value: 150)
        let t = TargetEngine.resolve(metricId: "protein", rules: [rule],
                                     tdee: nil, profile: defaultProfile())
        #expect(t != nil)
        #expect(t!.value == 150)
        #expect(t!.source == .guardrailRule)
        #expect(t!.direction == .atLeast)
    }

    @Test func kuralYoksaKatalogYedegi() {
        let t = TargetEngine.resolve(metricId: "sodium", rules: [],
                                     tdee: nil, profile: defaultProfile())
        #expect(t != nil)
        #expect(t!.value == 2000)
        #expect(t!.source == .catalog)
        #expect(t!.direction == .atMost)   // sodyum düşük-iyi → tavan
    }

    @Test func kaloriHedefi_tdeeMotorundan() {
        // Varsayılan profil 0,6 kg/hafta kayıp → alım TAVAN (.atMost), değer = önerilen alım
        let t = TargetEngine.resolve(metricId: "calories", rules: [],
                                     tdee: tdeeFlat2000(), profile: defaultProfile())
        #expect(t != nil)
        #expect(t!.source == .tdeeEngine)
        #expect(t!.direction == .atMost)
        #expect(approx(t!.value, 1340, tol: 2))   // 2000 − 660
    }

    @Test func korumaFazinda_bakimBandi() {
        var p = defaultProfile(); p.targetRateKgPerWeek = 0
        let t = TargetEngine.resolve(metricId: "calories", rules: [],
                                     tdee: tdeeFlat2000(), profile: p)
        #expect(t != nil)
        #expect(t!.direction == .between)
        #expect(t!.upperValue != nil)
        #expect(t!.value < t!.upperValue!)
    }

    @Test func enerjiYuzdesiGramaCevrilir() {
        // Kalori kuralı 2000; doymuş yağ ≤ %7 (9 kcal/g) → 2000×0,07/9 ≈ 15,6 g
        let kcalRule = GuardrailRule(name: "Kalori", targetId: "calories", op: .atMost, value: 2000)
        var satRule = GuardrailRule(name: "Doymuş yağ", kind: .percentOfEnergy,
                                    targetId: "satFat", op: .atMost, value: 7)
        satRule.kcalPerGram = 9
        let t = TargetEngine.resolve(metricId: "satFat", rules: [kcalRule, satRule],
                                     tdee: nil, profile: defaultProfile())
        #expect(t != nil)
        #expect(approx(t!.value, 15.56, tol: 0.1))
        #expect(t!.derivedNote != nil)
    }

    @Test func hedefYoksaUydurmaYok() {
        let t = TargetEngine.resolve(metricId: "boyle_bir_metrik_yok", rules: [],
                                     tdee: nil, profile: defaultProfile())
        #expect(t == nil)
    }
}

// MARK: - Progress

@Suite("ProgressEngine")
struct ProgressTests {
    private let day = fixedDay(2026, 7, 20)

    private func samplesOn(_ base: Date, values: [Double]) -> [MetricSample] {
        values.enumerated().map { i, v in
            MetricSample(date: Calendar.current.date(byAdding: .hour, value: i, to: base)!, value: v)
        }
    }

    @Test func gununDegeri_toplamaTipineGore() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let yesterday = cal.date(byAdding: .day, value: -1, to: start)!
        let s = samplesOn(start, values: [300, 200]) + samplesOn(yesterday, values: [500])
        #expect(ProgressEngine.todayValue(s, aggregation: .sum, now: day) == 500)
        #expect(ProgressEngine.todayValue(s, aggregation: .average, now: day) == 250)
        #expect(ProgressEngine.todayValue(s, aggregation: .latest, now: day) == 200)
        // Veri yoksa 0 (meşru değer, "veri yok" değil)
        #expect(ProgressEngine.todayValue([], aggregation: .sum, now: day) == 0)
    }

    private func target(_ dir: RuleOperator, _ v: Double, upper: Double? = nil) -> TargetEngine.ResolvedTarget {
        TargetEngine.ResolvedTarget(metricId: "protein", value: v, upperValue: upper,
                                    direction: dir, source: .guardrailRule,
                                    unit: "g", derivedNote: nil)
    }

    @Test func enAzHedefi() {
        let s = samplesOn(Calendar.current.startOfDay(for: day), values: [100])
        let dp = ProgressEngine.compute(metricId: "protein", series: s,
                                        target: target(.atLeast, 150),
                                        aggregation: .sum, now: day)
        #expect(dp.state == .belowTarget)
        #expect(dp.remaining == 50)

        let dp2 = ProgressEngine.compute(metricId: "protein",
                                         series: samplesOn(Calendar.current.startOfDay(for: day), values: [160]),
                                         target: target(.atLeast, 150),
                                         aggregation: .sum, now: day)
        #expect(dp2.state == .atTarget)
        #expect(dp2.remaining == 0)
    }

    @Test func enFazlaHedefi_tavanAsimi() {
        let base = Calendar.current.startOfDay(for: day)
        let over = ProgressEngine.compute(metricId: "sodium",
                                          series: samplesOn(base, values: [2100]),
                                          target: target(.atMost, 2000),
                                          aggregation: .sum, now: day)
        #expect(over.state == .overTarget)
        #expect(over.remaining == -100)

        let under = ProgressEngine.compute(metricId: "sodium",
                                           series: samplesOn(base, values: [1500]),
                                           target: target(.atMost, 2000),
                                           aggregation: .sum, now: day)
        #expect(under.state == .atTarget)
        #expect(under.remaining == 500)
    }

    @Test func aralikHedefi() {
        let base = Calendar.current.startOfDay(for: day)
        let below = ProgressEngine.compute(metricId: "calories",
                                           series: samplesOn(base, values: [80]),
                                           target: target(.between, 90, upper: 110),
                                           aggregation: .sum, now: day)
        #expect(below.state == .belowTarget)
        #expect(below.remaining == 10)

        let inside = ProgressEngine.compute(metricId: "calories",
                                            series: samplesOn(base, values: [100]),
                                            target: target(.between, 90, upper: 110),
                                            aggregation: .sum, now: day)
        #expect(inside.state == .atTarget)

        let over = ProgressEngine.compute(metricId: "calories",
                                          series: samplesOn(base, values: [120]),
                                          target: target(.between, 90, upper: 110),
                                          aggregation: .sum, now: day)
        #expect(over.state == .overTarget)
        #expect(over.remaining == -10)
    }

    @Test func hedefYokDurumu() {
        let dp = ProgressEngine.compute(metricId: "x", series: [],
                                        target: nil, aggregation: .sum, now: day)
        #expect(dp.state == .noTarget)
    }

    @Test func gecmisGunOlcumu() {
        // E düzeltmesinin sözleşmesi: `now` olarak GEÇMİŞ gün verilirse o günün toplamı gelir
        let cal = Calendar.current
        let past = fixedDay(2026, 7, 15)
        let pastStart = cal.startOfDay(for: past)
        let s = samplesOn(pastStart, values: [700, 300])
              + samplesOn(cal.startOfDay(for: day), values: [111])
        #expect(ProgressEngine.todayValue(s, aggregation: .sum, now: past) == 1000)
        #expect(ProgressEngine.todayValue(s, aggregation: .sum, now: day) == 111)
    }
}
