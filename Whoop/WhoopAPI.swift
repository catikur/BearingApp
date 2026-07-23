import Foundation

/// WHOOP v2 REST client. Bearer token WhoopAuth'tan gelir; sayfalama + basit hata yönetimi.
/// Hatalar yutulmaz: `errors` içinde toplanır, WhoopStore Ayarlar'daki tanı paneline taşır.
@MainActor
final class WhoopAPI {
    private let base = "https://api.prod.whoop.com/developer"
    private let auth = WhoopAuth.shared

    /// Son fetch turunda biriken uç bazlı hatalar (tanı paneli için)
    private(set) var errors: [String] = []
    func resetDiagnostics() { errors = [] }
    private func note(_ path: String, _ msg: String) {
        errors.append("\(path.replacingOccurrences(of: "/v2/", with: "")): \(msg)")
    }

    private func get<T: Codable>(_ path: String, query: [URLQueryItem] = []) async -> T? {
        guard let token = await auth.validAccessToken() else {
            note(path, auth.authError ?? "geçerli token yok — Whoop'a yeniden bağlanmak gerekebilir")
            return nil
        }
        var comp = URLComponents(string: base + path)!
        if !query.isEmpty { comp.queryItems = query }
        guard let url = comp.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data.prefix(160), encoding: .utf8) ?? ""
                note(path, "HTTP \(code) \(body)")
                return nil
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                // DecodingError açıklaması alan adı uyuşmazlığını birebir gösterir
                note(path, "decode: \(String(describing: error).prefix(220))")
                return nil
            }
        } catch {
            note(path, "ağ: \(error.localizedDescription)")
            return nil
        }
    }

    /// Belirli bir tipi sayfalayarak son `days` gün için topla
    private func page<T: Codable>(_ path: String, days: Int) async -> [T] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let iso = ISO8601DateFormatter()
        var items: [T] = []
        var token: String? = nil
        var pageCount = 0
        // ~25 kayıt/sayfa; workout gibi günde birden çok kayıt olabilen uçlara pay bırak
        let maxPages = max(20, days / 6)
        repeat {
            var query: [URLQueryItem] = [
                .init(name: "start", value: iso.string(from: start)),
                .init(name: "limit", value: "25"),
            ]
            if let token = token { query.append(.init(name: "nextToken", value: token)) }
            guard let pageData: WhoopPage<T> = await get(path, query: query) else { break }
            items += pageData.records
            token = pageData.next_token
            pageCount += 1
        } while token != nil && pageCount < maxPages
        return items
    }

    func recoveries(days: Int) async -> [WhoopRecovery] { await page("/v2/recovery", days: days) }
    func cycles(days: Int)     async -> [WhoopCycle]    { await page("/v2/cycle", days: days) }
    func sleeps(days: Int)     async -> [WhoopSleep]    { await page("/v2/activity/sleep", days: days) }
    func workouts(days: Int)   async -> [WhoopWorkout]  { await page("/v2/activity/workout", days: days) }

    /// Tekil kayıt (sayfasız): profil vücut ölçüleri
    func bodyMeasurement() async -> WhoopBodyMeasurement? { await get("/v2/user/measurement/body") }
}

/// Whoop verisini MetricSample serilerine dönüştürüp DataStore'a besler.
/// Not: Whoop tüm skorları "gün" bazına indirger; workout'lar gün içinde toplanır.
@MainActor
final class WhoopStore: ObservableObject {
    private let api = WhoopAPI()

    /// Tanı: son çekimin uç başına kayıt sayısı, hataları ve zamanı (Ayarlar → Veri kaynakları)
    @Published var lastCounts: [(String, Int)] = []
    @Published var lastErrors: [String] = []
    @Published var lastSync: Date?

    // Whoop damgaları milisaniyeli gelir ("2026-07-22T04:12:33.123Z");
    // ISO8601DateFormatter varsayılanı bunu ÇÖZEMEZ — iki biçimi de kabul et.
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private func parseDate(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        return Self.isoFrac.date(from: s) ?? Self.isoPlain.date(from: s)
    }

    private let kjToKcal = 0.239006
    private func hrs(_ milli: Double?) -> Double? { milli.map { $0 / 3_600_000.0 } }

    /// metrik id -> günlük değerler (whoop_*)
    func fetchAll(days: Int) async -> [String: [MetricSample]] {
        api.resetDiagnostics()
        var out: [String: [MetricSample]] = [:]
        let cal = Calendar.current

        func day(_ s: String?) -> Date? {
            guard let d = parseDate(s) else { return nil }
            return cal.startOfDay(for: d)
        }
        func push(_ key: String, _ arr: [MetricSample]) {
            out[key] = arr.sorted { $0.date < $1.date }
        }

        // MARK: Recovery
        let recs = await api.recoveries(days: days)
        var recovery: [MetricSample] = [], whrv: [MetricSample] = [], wrhr: [MetricSample] = []
        var wspo2: [MetricSample] = [], wskin: [MetricSample] = []
        for r in recs {
            guard let d = day(r.created_at), let sc = r.score else { continue }
            if let v = sc.recovery_score      { recovery.append(.init(date: d, value: v)) }
            if let v = sc.hrv_rmssd_milli      { whrv.append(.init(date: d, value: v)) }
            if let v = sc.resting_heart_rate   { wrhr.append(.init(date: d, value: v)) }
            if let v = sc.spo2_percentage      { wspo2.append(.init(date: d, value: v)) }
            if let v = sc.skin_temp_celsius    { wskin.append(.init(date: d, value: v)) }
        }
        push("whoop_recovery", recovery)
        push("whoop_hrv", whrv)
        push("whoop_rhr", wrhr)
        push("whoop_spo2", wspo2)
        push("whoop_skinTemp", wskin)

        // MARK: Cycle (strain + gün geneli enerji/nabız)
        let cycles = await api.cycles(days: days)
        var strain: [MetricSample] = [], wcal: [MetricSample] = []
        var wavg: [MetricSample] = [], wmax: [MetricSample] = []
        for c in cycles {
            guard let d = day(c.start), let sc = c.score else { continue }
            if let v = sc.strain             { strain.append(.init(date: d, value: v)) }
            if let v = sc.kilojoule          { wcal.append(.init(date: d, value: v * kjToKcal)) }
            if let v = sc.average_heart_rate { wavg.append(.init(date: d, value: v)) }
            if let v = sc.max_heart_rate     { wmax.append(.init(date: d, value: v)) }
        }
        push("whoop_strain", strain)
        push("whoop_calories", wcal)
        push("whoop_avgHR", wavg)
        push("whoop_maxHR", wmax)

        // MARK: Sleep (gece uykusu; nap hariç)
        let sleeps = await api.sleeps(days: days)
        var perf: [MetricSample] = [], need: [MetricSample] = [], eff: [MetricSample] = []
        var cons: [MetricSample] = [], resp: [MetricSample] = [], dur: [MetricSample] = []
        var deep: [MetricSample] = [], rem: [MetricSample] = [], light: [MetricSample] = []
        var awake: [MetricSample] = [], dist: [MetricSample] = []
        for s in sleeps where !(s.nap ?? false) {
            guard let d = day(s.start), let sc = s.score else { continue }
            if let v = sc.sleep_performance_percentage { perf.append(.init(date: d, value: v)) }
            if let v = sc.sleep_efficiency_percentage  { eff.append(.init(date: d, value: v)) }
            if let v = sc.sleep_consistency_percentage { cons.append(.init(date: d, value: v)) }
            if let v = sc.respiratory_rate             { resp.append(.init(date: d, value: v)) }
            let st = sc.stage_summary
            if let v = hrs(st?.total_slow_wave_sleep_time_milli) { deep.append(.init(date: d, value: v)) }
            if let v = hrs(st?.total_rem_sleep_time_milli)       { rem.append(.init(date: d, value: v)) }
            if let v = hrs(st?.total_light_sleep_time_milli)     { light.append(.init(date: d, value: v)) }
            if let v = hrs(st?.total_awake_time_milli)           { awake.append(.init(date: d, value: v)) }
            if let c = st?.disturbance_count { dist.append(.init(date: d, value: Double(c))) }
            if let inBed = st?.total_in_bed_time_milli, let aw = st?.total_awake_time_milli,
               let v = hrs(max(0, inBed - aw)) { dur.append(.init(date: d, value: v)) }
            if let base = sc.sleep_needed?.baseline_milli, base > 0,
               let inBed = st?.total_in_bed_time_milli, let aw = st?.total_awake_time_milli {
                let asleep = max(0, inBed - aw)
                need.append(.init(date: d, value: min(100, asleep / base * 100)))
            }
        }
        push("whoop_sleepPerf", perf)
        push("whoop_sleepEff", eff)
        push("whoop_sleepConsistency", cons)
        push("whoop_respRate", resp)
        push("whoop_sleepDuration", dur)
        push("whoop_deepSleep", deep)
        push("whoop_remSleep", rem)
        push("whoop_lightSleep", light)
        push("whoop_awakeTime", awake)
        push("whoop_disturbances", dist)
        push("whoop_sleepNeed", need)

        // MARK: Workout (gün bazında topla — çoklu antrenman/gün olabilir)
        let workouts = await api.workouts(days: days)
        var kjByDay: [Date: Double] = [:], cntByDay: [Date: Double] = [:], maxStrainByDay: [Date: Double] = [:]
        for w in workouts {
            guard let d = day(w.start) else { continue }
            cntByDay[d, default: 0] += 1
            if let kj = w.score?.kilojoule { kjByDay[d, default: 0] += kj * kjToKcal }
            if let st = w.score?.strain    { maxStrainByDay[d] = max(maxStrainByDay[d] ?? 0, st) }
        }
        push("whoop_workoutCount",  cntByDay.map { .init(date: $0.key, value: $0.value) })
        push("whoop_workoutKj",     kjByDay.map { .init(date: $0.key, value: $0.value) })
        push("whoop_workoutStrain", maxStrainByDay.map { .init(date: $0.key, value: $0.value) })

        // MARK: Body measurement (tek değer — bugüne yaz)
        let bm = await api.bodyMeasurement()
        if let bm = bm {
            let today = cal.startOfDay(for: Date())
            if let w = bm.weight_kilogram { push("whoop_weight", [.init(date: today, value: w)]) }
        }

        // Tanı panelini güncelle
        lastCounts = [("Recovery", recs.count), ("Cycle", cycles.count),
                      ("Sleep", sleeps.count), ("Workout", workouts.count),
                      ("Vücut ölçüsü", bm == nil ? 0 : 1)]
        lastErrors = api.errors
        lastSync = Date()

        return out
    }
}
