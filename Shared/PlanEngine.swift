import Foundation

// =====================================================================
// PLAN MOTORU — deterministik. LLM burada da hesap yapmaz.
// =====================================================================
enum PlanEngine {

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func key(_ item: PlanItem, _ day: Date, _ time: TimeOfDay) -> String {
        "\(item.id.uuidString)|\(dayFmt.string(from: day))|\(time.label)"
    }

    // MARK: Bir öğe belirli bir günde düşer mi?
    static func occurs(_ item: PlanItem, on day: Date, allItems: [PlanItem]) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        guard item.isActive else { return false }
        if d < cal.startOfDay(for: item.startDate) { return false }
        if let e = item.endDate, d > cal.startOfDay(for: e) { return false }

        switch item.schedule {
        case .daily:
            return true
        case .weekdays(let days):
            return days.contains(cal.component(.weekday, from: d))
        case .everyNDays(let n):
            guard n > 0 else { return false }
            let diff = cal.dateComponents([.day], from: cal.startOfDay(for: item.startDate), to: d).day ?? 0
            return diff >= 0 && diff % n == 0
        case .oneOff(let target):
            return cal.isDate(d, inSameDayAs: target)
        case .relativeTo(let anchorId, let offset):
            guard let anchor = allItems.first(where: { $0.id == anchorId }),
                  case .oneOff(let anchorDate) = anchor.schedule,
                  let target = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: anchorDate))
            else { return false }
            return cal.isDate(d, inSameDayAs: target)
        }
    }

    // MARK: Bir günün tüm örnekleri (saate göre sıralı)
    static func occurrences(on day: Date,
                            items: [PlanItem],
                            unlockedPhase: Int,
                            phaseEnabled: Bool) -> [PlanOccurrence] {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        var out: [PlanOccurrence] = []
        for item in items {
            if phaseEnabled && item.phase > unlockedPhase { continue }
            guard occurs(item, on: d, allItems: items) else { continue }
            let times = item.times.isEmpty ? [TimeOfDay(hour: 9, minute: 0)] : item.times
            for t in times {
                out.append(PlanOccurrence(item: item, when: t.date(on: d), key: key(item, d, t)))
            }
        }
        return out.sorted { $0.when < $1.when }
    }

    // MARK: Uyum
    struct Adherence {
        let category: PlanCategory?      // nil = genel
        let done: Int
        let skipped: Int
        let total: Int                   // geçmiş (bugün dahil, gelecek hariç) örnek sayısı
        var pct: Double { total > 0 ? Double(done) / Double(total) * 100 : 0 }
        var hasData: Bool { total > 0 }
    }

    /// Son `days` gün için uyum. Gelecekteki örnekler paydaya girmez.
    static func adherence(items: [PlanItem],
                          logs: [String: PlanLog],
                          days: Int,
                          category: PlanCategory? = nil,
                          unlockedPhase: Int,
                          phaseEnabled: Bool) -> Adherence {
        let cal = Calendar.current
        let now = Date()
        var done = 0, skipped = 0, total = 0

        for offset in 0..<max(1, days) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let occ = occurrences(on: day, items: items,
                                  unlockedPhase: unlockedPhase, phaseEnabled: phaseEnabled)
            for o in occ {
                if let c = category, o.item.category != c { continue }
                guard o.when <= now else { continue }        // henüz gelmemiş → sayma
                total += 1
                switch logs[o.key]?.status {
                case .done:    done += 1
                case .skipped: skipped += 1
                case nil:      break
                }
            }
        }
        return Adherence(category: category, done: done, skipped: skipped, total: total)
    }

    /// Kategori kırılımı
    static func adherenceByCategory(items: [PlanItem],
                                    logs: [String: PlanLog],
                                    days: Int,
                                    unlockedPhase: Int,
                                    phaseEnabled: Bool) -> [Adherence] {
        PlanCategory.allCases.compactMap { c in
            let a = adherence(items: items, logs: logs, days: days, category: c,
                              unlockedPhase: unlockedPhase, phaseEnabled: phaseEnabled)
            return a.hasData ? a : nil
        }
    }

    /// Kesintisiz gün serisi: o günün tüm örneklerinin tamamlandığı ardışık gün sayısı
    static func streak(items: [PlanItem],
                       logs: [String: PlanLog],
                       unlockedPhase: Int,
                       phaseEnabled: Bool,
                       maxLookback: Int = 120) -> Int {
        let cal = Calendar.current
        var streak = 0
        for offset in 1...maxLookback {           // dünden geriye (bugün henüz bitmedi)
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { break }
            let occ = occurrences(on: day, items: items,
                                  unlockedPhase: unlockedPhase, phaseEnabled: phaseEnabled)
            if occ.isEmpty { continue }
            let allDone = occ.allSatisfy { logs[$0.key]?.status == .done }
            if allDone { streak += 1 } else { break }
        }
        return streak
    }

    // MARK: Faz kilidi (tek değişken kuralı)
    struct PhaseState {
        let unlocked: Int
        let nextPhase: Int?
        let daysInCurrent: Int
        let adherenceInCurrent: Double
        let readyToAdvance: Bool
        let daysRemaining: Int
    }

    /// Mevcut fazın yeterince sürdürülüp sürdürülmediğini değerlendirir.
    static func phaseState(items: [PlanItem],
                           logs: [String: PlanLog],
                           settings: PhaseSettings,
                           unlockedPhase: Int) -> PhaseState {
        let maxPhase = items.map { $0.phase }.max() ?? 1
        let next: Int? = unlockedPhase < maxPhase ? unlockedPhase + 1 : nil

        // Mevcut fazdaki en eski başlangıçtan bu yana geçen gün
        let phaseItems = items.filter { $0.phase == unlockedPhase && $0.enabled }
        let earliest = phaseItems.map { $0.startDate }.min() ?? Date()
        let daysIn = Calendar.current.dateComponents([.day],
                        from: Calendar.current.startOfDay(for: earliest),
                        to: Calendar.current.startOfDay(for: Date())).day ?? 0

        let a = adherence(items: phaseItems, logs: logs, days: max(1, min(daysIn, settings.minDaysPerPhase)),
                          unlockedPhase: unlockedPhase, phaseEnabled: true)

        let ready = settings.enabled
            && next != nil
            && daysIn >= settings.minDaysPerPhase
            && a.pct >= settings.minAdherence

        return PhaseState(unlocked: unlockedPhase,
                          nextPhase: next,
                          daysInCurrent: daysIn,
                          adherenceInCurrent: a.pct,
                          readyToAdvance: ready,
                          daysRemaining: max(0, settings.minDaysPerPhase - daysIn))
    }

    // MARK: Korelasyon taramasına besleme
    /// Bir kategorinin tamamlandığı günler — korelasyon motoruna etiket gibi girer.
    static func completionDates(items: [PlanItem],
                                logs: [String: PlanLog],
                                category: PlanCategory,
                                days: Int,
                                unlockedPhase: Int,
                                phaseEnabled: Bool) -> Set<Date> {
        let cal = Calendar.current
        var out = Set<Date>()
        for offset in 0..<max(1, days) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let d = cal.startOfDay(for: day)
            let occ = occurrences(on: d, items: items,
                                  unlockedPhase: unlockedPhase, phaseEnabled: phaseEnabled)
                .filter { $0.item.category == category }
            guard !occ.isEmpty else { continue }
            if occ.allSatisfy({ logs[$0.key]?.status == .done }) { out.insert(d) }
        }
        return out
    }

    /// Tarama kimliği → okunabilir ad ("plan:supplement" → "Plan · Suplement")
    static let scanPrefix = "plan:"
    static func scanId(_ c: PlanCategory) -> String { scanPrefix + c.rawValue }
    static func displayName(forScanId id: String) -> String? {
        guard id.hasPrefix(scanPrefix) else { return nil }
        let raw = String(id.dropFirst(scanPrefix.count))
        return PlanCategory(rawValue: raw).map { "Plan · \($0.label)" }
    }
}
