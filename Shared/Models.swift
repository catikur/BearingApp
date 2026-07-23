import Foundation
import HealthKit

/// Bir metriğin nasıl toplanacağı
enum Aggregation {
    case sum          // günlük toplam (kalori, adım, protein)
    case average      // günlük ortalama (HRV, nabız)
    case latest       // gün içindeki son ölçüm (kilo, yağ %)
    case sleepHours   // uyku kategorisi (özel)
    case whoop        // Whoop API'den gelir (HealthKit değil)
}

enum MetricSource: String, Codable {
    case healthKit = "Apple Health"
    case whoop = "Whoop"
}

/// Katalog tanımı — hangi veri, nereden, nasıl toplanır, hedef nedir
struct MetricDef: Identifiable, Hashable {
    let id: String
    let title: String
    let unit: String
    let category: String
    let source: MetricSource
    let aggregation: Aggregation
    let target: Double?
    let higherIsBetter: Bool
    var hkIdentifier: HKQuantityTypeIdentifier? = nil
    var hkUnitString: String? = nil      // HKUnit(from:) ile parse edilir
    var scale: Double = 1                // ör. yağ %: 0-1 -> 0-100

    static func == (l: MetricDef, r: MetricDef) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var hkUnit: HKUnit? {
        guard let s = hkUnitString else { return nil }
        return HKUnit(from: s)
    }
}

/// Tek bir günlük ölçüm
struct MetricSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
