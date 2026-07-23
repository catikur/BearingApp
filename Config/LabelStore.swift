import Foundation
import SwiftUI

/// Günlük yerel etiketleri kalıcı saklar (UserDefaults, JSON). Veri cihazdan çıkmaz.
@MainActor
final class LabelStore: ObservableObject {
    @Published private(set) var labels: [String: DayLabel] = [:]   // dateKey -> label

    private let key = "day_labels_v1"
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([DayLabel].self, from: data) {
            labels = Dictionary(uniqueKeysWithValues: arr.map { ($0.dateKey, $0) })
        }
    }

    // MARK: Okuma
    static func keyFor(_ date: Date) -> String { fmt.string(from: date) }
    func label(for date: Date) -> DayLabel? { labels[Self.keyFor(date)] }
    func tags(for date: Date) -> [String] { label(for: date)?.tags ?? [] }
    func hasAny(_ date: Date) -> Bool {
        guard let l = label(for: date) else { return false }
        return !l.tags.isEmpty || !l.note.isEmpty
    }

    /// Belirli etiketi taşıyan günlerin (gün başı) kümesi — korelasyon/overlay için.
    func dates(withTag tagId: String) -> Set<Date> {
        let cal = Calendar.current
        return Set(labels.values
            .filter { $0.tags.contains(tagId) }
            .compactMap { Self.fmt.date(from: $0.dateKey) }
            .map { cal.startOfDay(for: $0) })
    }

    /// Herhangi etiketi olan günler -> etiket id'leri (grafik işaretçisi için).
    func labeledDays() -> [Date: [String]] {
        let cal = Calendar.current
        var out: [Date: [String]] = [:]
        for l in labels.values where !l.tags.isEmpty {
            if let d = Self.fmt.date(from: l.dateKey) { out[cal.startOfDay(for: d)] = l.tags }
        }
        return out
    }

    // MARK: Yazma
    func toggleTag(_ tagId: String, for date: Date) {
        let k = Self.keyFor(date)
        var l = labels[k] ?? DayLabel(dateKey: k, tags: [], note: "")
        if let i = l.tags.firstIndex(of: tagId) { l.tags.remove(at: i) } else { l.tags.append(tagId) }
        write(k, l)
    }

    func setNote(_ note: String, for date: Date) {
        let k = Self.keyFor(date)
        var l = labels[k] ?? DayLabel(dateKey: k, tags: [], note: "")
        l.note = note
        write(k, l)
    }

    func clear(_ date: Date) {
        labels[Self.keyFor(date)] = nil
        persist()
    }

    private func write(_ k: String, _ l: DayLabel) {
        if l.tags.isEmpty && l.note.isEmpty { labels[k] = nil } else { labels[k] = l }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(labels.values)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
