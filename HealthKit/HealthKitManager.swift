import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    let store = HKHealthStore()
    @Published var authorized = false
    @Published var errorText: String?

    /// Okunacak tüm HealthKit tipleri (katalogdaki mevcut olanlar + uyku + alkol)
    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        for def in HealthMetricCatalog.all where def.source == .healthKit {
            if let id = def.hkIdentifier, let t = HKObjectType.quantityType(forIdentifier: id) {
                set.insert(t)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        return set
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorText = "Sağlık verisi mevcut değil — gerçek iPhone'da çalıştır (simülatör değil)."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorized = true
        } catch {
            errorText = "HealthKit yetki hatası: \(error.localizedDescription)"
        }
    }

    /// Verilen metrik için son `days` günün günlük değerleri
    func fetch(_ def: MetricDef, days: Int) async -> [MetricSample] {
        switch def.aggregation {
        case .sleepHours: return await sleepHours(days: days)
        case .sum, .average, .latest:
            guard let id = def.hkIdentifier,
                  let type = HKQuantityType.quantityType(forIdentifier: id),
                  let unit = def.hkUnit else { return [] }
            let option: HKStatisticsOptions = {
                switch def.aggregation {
                case .sum: return .cumulativeSum
                case .latest: return .mostRecent
                default: return .discreteAverage
                }
            }()
            guard let coll = await statistics(type: type, options: option, days: days) else { return [] }
            return extract(coll, unit: unit, aggregation: def.aggregation, days: days, scale: def.scale)
        case .whoop:
            return []   // Whoop verisi WhoopStore'dan gelir
        }
    }

    // MARK: - Sorgu yardımcıları

    private func statistics(type: HKQuantityType, options: HKStatisticsOptions, days: Int) async -> HKStatisticsCollection? {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -days, to: anchor) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type,
                                                quantitySamplePredicate: predicate,
                                                options: options,
                                                anchorDate: anchor,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, result, _ in cont.resume(returning: result) }
            store.execute(q)
        }
    }

    private func extract(_ collection: HKStatisticsCollection, unit: HKUnit,
                         aggregation: Aggregation, days: Int, scale: Double) -> [MetricSample] {
        var out: [MetricSample] = []
        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end)) else { return [] }
        collection.enumerateStatistics(from: start, to: end) { stat, _ in
            let q: HKQuantity?
            switch aggregation {
            case .sum: q = stat.sumQuantity()
            case .latest: q = stat.mostRecentQuantity()
            default: q = stat.averageQuantity()
            }
            if let q = q {
                out.append(MetricSample(date: stat.startDate, value: q.doubleValue(for: unit) * scale))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    private func sleepHours(days: Int) async -> [MetricSample] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date())) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                cont.resume(returning: (res as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        var asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
        asleep.insert(HKCategoryValueSleepAnalysis.asleepCore.rawValue)
        asleep.insert(HKCategoryValueSleepAnalysis.asleepDeep.rawValue)
        asleep.insert(HKCategoryValueSleepAnalysis.asleepREM.rawValue)
        var byDay: [Date: TimeInterval] = [:]
        for s in samples where asleep.contains(s.value) {
            let day = cal.startOfDay(for: s.endDate)   // uyanılan güne yaz
            byDay[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }
        return byDay.map { MetricSample(date: $0.key, value: $0.value / 3600.0) }.sorted { $0.date < $1.date }
    }
}
