import Foundation
import SwiftUI

// MARK: - Kategori
enum PlanCategory: String, Codable, CaseIterable, Identifiable {
    case meal, supplement, training, mobility, circadian, measurement, appointment

    var id: String { rawValue }
    var label: String {
        switch self {
        case .meal:        return "Öğün"
        case .supplement:  return "Suplement"
        case .training:    return "Antrenman"
        case .mobility:    return "Boyun / TME"
        case .circadian:   return "Sirkadiyen"
        case .measurement: return "Ölçüm"
        case .appointment: return "Randevu / Lab"
        }
    }
    var icon: String {
        switch self {
        case .meal:        return "fork.knife"
        case .supplement:  return "pills.fill"
        case .training:    return "figure.strengthtraining.traditional"
        case .mobility:    return "figure.cooldown"
        case .circadian:   return "sun.max.fill"
        case .measurement: return "ruler"
        case .appointment: return "stethoscope"
        }
    }
    /// Tasarım sistemindeki kimlik kanalı karşılığı (DesignSystem.swift).
    /// Kategori rengi tek kaynaktan gelir: düşük doygunluk, hepsi eşit ağırlıkta.
    var identity: IdentityColor {
        switch self {
        case .meal:        return .meal
        case .supplement:  return .supplement
        case .training:    return .workout
        case .mobility:    return .neckTMJ
        case .circadian:   return .circadian
        case .measurement: return .measurement
        case .appointment: return .appointment
        }
    }
    var color: Color { identity.color }
}

// MARK: - Saat
struct TimeOfDay: Codable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    static func < (l: TimeOfDay, r: TimeOfDay) -> Bool {
        l.hour != r.hour ? l.hour < r.hour : l.minute < r.minute
    }
    var label: String { String(format: "%02d:%02d", hour, minute) }
    var minutes: Int { hour * 60 + minute }

    func date(on day: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
    static func from(_ date: Date) -> TimeOfDay {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}

// MARK: - Zamanlama
enum ScheduleKind: Codable, Equatable, Hashable {
    case daily
    case weekdays([Int])                             // 1=Pazar … 7=Cumartesi (Calendar)
    case everyNDays(Int)
    case oneOff(Date)
    case relativeTo(anchorId: UUID, offsetDays: Int) // ters hatırlatma (ör. lab −3 gün)

    var label: String {
        switch self {
        case .daily: return "Her gün"
        case .weekdays(let d):
            let names = ["", "Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"]
            return d.sorted().compactMap { $0 >= 1 && $0 <= 7 ? names[$0] : nil }.joined(separator: ", ")
        case .everyNDays(let n): return "\(n) günde bir"
        case .oneOff(let d): return d.formatted(date: .abbreviated, time: .omitted)
        case .relativeTo(_, let o): return o < 0 ? "\(-o) gün önce" : "\(o) gün sonra"
        }
    }
}

// MARK: - Plan öğesi
struct PlanItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var category: PlanCategory
    var detail: String = ""                 // doz / miktar / kısa açıklama
    var schedule: ScheduleKind = .daily
    var times: [TimeOfDay] = []
    var startDate: Date = Date()
    var endDate: Date? = nil                // "4 hafta" gibi süreli olanlar
    var phase: Int = 1                      // sıralı başlatma (tek değişken kuralı)
    var notify: Bool = true
    var leadMinutes: Int = 0
    var locked: Bool = false                // onay bekliyor → bildirim üretmez
    var lockNote: String = ""
    var workoutTemplateId: UUID? = nil      // antrenman ise
    var enabled: Bool = true
    var note: String = ""

    var isActive: Bool {
        guard enabled else { return false }
        let now = Date()
        if let e = endDate, now > e { return false }
        return true
    }
}

// MARK: - Tamamlama kaydı
enum PlanStatus: String, Codable { case done, skipped }

struct PlanLog: Codable, Identifiable, Equatable {
    var id = UUID()
    var itemId: UUID
    var occurrenceKey: String       // "itemId|yyyy-MM-dd|HH:mm"
    var day: Date                   // gün başı
    var status: PlanStatus
    var loggedAt: Date = Date()
}

/// Belirli bir günün belirli bir saatindeki plan örneği
struct PlanOccurrence: Identifiable, Equatable {
    let item: PlanItem
    let when: Date
    let key: String
    var id: String { key }
}

// MARK: - Bildirim ayarları (parametrik)
struct NotificationSettings: Codable, Equatable {
    var enabled: Bool = true
    var quietStart = TimeOfDay(hour: 0, minute: 0)
    var quietEnd = TimeOfDay(hour: 6, minute: 0)
    var horizonDays: Int = 7            // kaç günlük bildirim önden kurulsun
    var maxScheduled: Int = 60          // iOS sınırı 64 — pay bırakıyoruz
    var categoryEnabled: [String: Bool] = [
        PlanCategory.meal.rawValue: true,
        PlanCategory.supplement.rawValue: true,
        PlanCategory.mobility.rawValue: true,
        PlanCategory.circadian.rawValue: true,
        PlanCategory.training.rawValue: false,
        PlanCategory.measurement.rawValue: false,
        PlanCategory.appointment.rawValue: false,
    ]

    func isQuiet(_ t: TimeOfDay) -> Bool {
        let m = t.minutes, s = quietStart.minutes, e = quietEnd.minutes
        return s <= e ? (m >= s && m < e) : (m >= s || m < e)   // gece yarısını aşan aralık
    }
    func allows(_ c: PlanCategory) -> Bool { categoryEnabled[c.rawValue] ?? true }

    static let `default` = NotificationSettings()
}

// MARK: - Faz ayarları
struct PhaseSettings: Codable, Equatable {
    var enabled: Bool = true
    var minDaysPerPhase: Int = 14         // bir faz en az bu kadar sürdürülmeli
    var minAdherence: Double = 70         // ve uyum bu yüzdenin üstünde olmalı
    static let `default` = PhaseSettings()
}

// MARK: - Başlangıç seti (dosyalardan seed — hepsi düzenlenebilir/silinebilir)
enum PlanSeed {

    private static func t(_ h: Int, _ m: Int) -> TimeOfDay { TimeOfDay(hour: h, minute: m) }

    static func items(workoutA: UUID, workoutB: UUID) -> [PlanItem] {
        var out: [PlanItem] = []

        // ---- Öğün / yeme penceresi (14:10, örnek 12:00–22:00)
        out += [
            PlanItem(title: "Yeme penceresi açılıyor — Öğün 1", category: .meal,
                     detail: "4 yumurta + avokado + peynir + salata",
                     schedule: .daily, times: [t(12, 0)],
                     note: "14:10 penceresi. Saatleri kendi gününe göre kaydır."),
            PlanItem(title: "Ana öğün", category: .meal,
                     detail: "Protein ağırlıklı + pişmiş sebze + zeytinyağı",
                     schedule: .daily, times: [t(16, 30)]),
            PlanItem(title: "Akşam öğünü", category: .meal,
                     detail: "~250 g protein kaynağı + pişmiş sebze",
                     schedule: .daily, times: [t(20, 0)]),
            PlanItem(title: "Yeme penceresi kapanıyor", category: .meal,
                     detail: "Son öğün ile uyku arası en az 3 saat",
                     schedule: .daily, times: [t(22, 0)]),
            PlanItem(title: "Su", category: .meal,
                     detail: "Gün boyu 2.5–3 L hedefi",
                     schedule: .daily, times: [t(11, 0), t(15, 0), t(19, 0)]),
            PlanItem(title: "Haftada 1 gün 18:6", category: .meal,
                     detail: "2 öğün, aynı makro hedefi sıkıştırılmış",
                     schedule: .weekdays([1]), times: [t(9, 0)], notify: false),
        ]

        // ---- Suplement (SIRALI başlatma — tek değişken kuralı)
        out += [
            PlanItem(title: "D3 + K2", category: .supplement,
                     detail: "Yağ içeren öğünle",
                     schedule: .daily, times: [t(12, 15)], phase: 1,
                     note: "🟡 Doz kararı ve gerekliliği klinisyenine ait — burada yalnızca hatırlatılır. 4 hafta sonra D vit ölçümü planlı."),
            PlanItem(title: "Magnezyum glisinat", category: .supplement,
                     detail: "Akşam",
                     schedule: .daily, times: [t(21, 30)], phase: 1,
                     note: "🟡 Doz klinisyenine ait. Amaç: uyku kalitesi, kas tonusu, iç kulak."),
            PlanItem(title: "Kreatin", category: .supplement,
                     detail: "Günlük, saat fark etmez",
                     schedule: .daily, times: [t(12, 20)], phase: 2,
                     note: "🟡 Faz 2 — faz 1 oturduktan sonra açılır (tek değişken kuralı)."),
            PlanItem(title: "Omega-3", category: .supplement,
                     detail: "Öğünle",
                     schedule: .daily, times: [t(20, 15)], phase: 3, enabled: false,
                     note: "🟡 Faz 3 — Omega-3 indeksi ölçüldükten sonra klinisyenle doz belirlenip açılacak."),
        ]

        // ---- Boyun + TME rutini (günde 2×5 dk, 4 hafta)
        let fourWeeks = Calendar.current.date(byAdding: .day, value: 28, to: Date())
        out += [
            PlanItem(title: "Boyun + TME rutini (sabah)", category: .mobility,
                     detail: "Chin tuck · suboksipital release (tenis topu) · skalen germe · üst trapez germe · çene oblique",
                     schedule: .daily, times: [t(8, 0)], endDate: fourWeeks,
                     note: "5 dk. Ağrı üretmeden, yavaş."),
            PlanItem(title: "Boyun + TME rutini (akşam)", category: .mobility,
                     detail: "Aynı sıra + nemli sıcak yastık çene/boyun",
                     schedule: .daily, times: [t(21, 45)], endDate: fourWeeks),
            PlanItem(title: "Postür molası", category: .mobility,
                     detail: "Ayağa kalk, chin tuck ×10, omuz çekme",
                     schedule: .daily, times: [t(11, 0), t(14, 0), t(17, 0)],
                     notify: false, enabled: false,
                     note: "Bilgisayar başı çalışma için. Bildirim yoğunluğunu artırır — istersen aç."),
        ]

        // ---- Sirkadiyen
        out += [
            PlanItem(title: "Sabah ışığı", category: .circadian,
                     detail: "5–10 dk dışarıda / pencere önünde",
                     schedule: .daily, times: [t(8, 15)]),
            PlanItem(title: "Ekran / mavi ışık kesimi", category: .circadian,
                     detail: "Uykudan ~90 dk önce",
                     schedule: .daily, times: [t(22, 30)]),
        ]

        // ---- Antrenman (3–4 gün: 2 kuvvet + Muay Thai + yürüyüş)
        out += [
            PlanItem(title: "Kuvvet A", category: .training, detail: "Alt gövde + itme",
                     schedule: .weekdays([2]), times: [t(19, 0)], notify: false,
                     workoutTemplateId: workoutA),
            PlanItem(title: "Muay Thai", category: .training, detail: "Mevcut dersin",
                     schedule: .weekdays([3]), times: [t(20, 0)], notify: false),
            PlanItem(title: "Kuvvet B", category: .training, detail: "Alt gövde + çekme",
                     schedule: .weekdays([5]), times: [t(19, 0)], notify: false,
                     workoutTemplateId: workoutB),
            PlanItem(title: "Muay Thai", category: .training, detail: "Mevcut dersin",
                     schedule: .weekdays([6]), times: [t(20, 0)], notify: false),
            PlanItem(title: "Yürüyüş", category: .training,
                     detail: "30 dk tempolu — konuşabildiğin hız (Zone 2)",
                     schedule: .daily, times: [t(18, 0)], notify: false,
                     note: "Ayrı 'kardiyo günü' bloklamak zorunda değilsin; güne yay."),
        ]

        // ---- Ölçüm
        out += [
            PlanItem(title: "Haftalık ölçüm", category: .measurement,
                     detail: "Tartı + bel çevresi",
                     schedule: .weekdays([1]), times: [t(9, 0)], notify: false),
            PlanItem(title: "Semptom skoru", category: .measurement,
                     detail: "Tinnitus · şişkinlik · sabah çene yorgunluğu (1–10)",
                     schedule: .weekdays([1]), times: [t(9, 15)], notify: false),
        ]

        // ---- Lab / randevu (tarihleri sen gireceksin)
        let labAnchor = PlanItem(title: "Kan testi (checkup)", category: .appointment,
                                 detail: "Tarihi gir — bağlı hatırlatmalar buna göre kurulur",
                                 schedule: .oneOff(Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()),
                                 times: [t(8, 0)], notify: false)
        out.append(labAnchor)
        out += [
            PlanItem(title: "Biotin içeren takviyeyi kes", category: .appointment,
                     detail: "Tiroid/hormon testlerini bozar",
                     schedule: .relativeTo(anchorId: labAnchor.id, offsetDays: -3),
                     times: [t(9, 0)], notify: false),
            PlanItem(title: "D vitamini kontrolü", category: .appointment,
                     detail: "Takviye başlangıcından 4 hafta sonra",
                     schedule: .oneOff(Calendar.current.date(byAdding: .day, value: 28, to: Date()) ?? Date()),
                     times: [t(9, 0)], notify: false),
            PlanItem(title: "hs-CRP tekrar", category: .appointment,
                     detail: "Diş tedavisi sonrası 8. hafta",
                     schedule: .oneOff(Calendar.current.date(byAdding: .day, value: 56, to: Date()) ?? Date()),
                     times: [t(9, 0)], notify: false),
        ]

        return out
    }
}
