import Foundation
import SwiftUI

@MainActor
final class PlanStore: ObservableObject {

    @Published var items: [PlanItem]              { didSet { save(items, "plan_items_v1"); bumpDirty() } }
    @Published var logs: [String: PlanLog]        { didSet { save(Array(logs.values), "plan_logs_v1") } }
    @Published var workouts: [WorkoutTemplate]    { didSet { save(workouts, "plan_workouts_v1") } }
    @Published var workoutLogs: [WorkoutLog]      { didSet { save(workoutLogs, "plan_workout_logs_v1") } }
    @Published var notifSettings: NotificationSettings { didSet { save(notifSettings, "plan_notif_v1"); bumpDirty() } }
    @Published var phaseSettings: PhaseSettings   { didSet { save(phaseSettings, "plan_phase_v1"); bumpDirty() } }
    @Published var unlockedPhase: Int             { didSet { UserDefaults.standard.set(unlockedPhase, forKey: "plan_unlocked_phase"); bumpDirty() } }

    /// Bildirimlerin yeniden kurulması gerektiğini bildiren sayaç
    @Published private(set) var scheduleDirty = 0

    init() {
        let loadedItems = Self.load([PlanItem].self, "plan_items_v1")
        let loadedWorkouts = Self.load([WorkoutTemplate].self, "plan_workouts_v1")

        if let w = loadedWorkouts, let i = loadedItems {
            workouts = w
            items = i
        } else {
            let a = WorkoutSeed.strengthA()
            let b = WorkoutSeed.strengthB()
            workouts = [a, b]
            items = PlanSeed.items(workoutA: a.id, workoutB: b.id)
        }

        let logArray = Self.load([PlanLog].self, "plan_logs_v1") ?? []
        logs = Dictionary(uniqueKeysWithValues: logArray.map { ($0.occurrenceKey, $0) })
        workoutLogs = Self.load([WorkoutLog].self, "plan_workout_logs_v1") ?? []
        notifSettings = Self.load(NotificationSettings.self, "plan_notif_v1") ?? .default
        phaseSettings = Self.load(PhaseSettings.self, "plan_phase_v1") ?? .default
        unlockedPhase = UserDefaults.standard.object(forKey: "plan_unlocked_phase") as? Int ?? 1
    }

    private func bumpDirty() { scheduleDirty &+= 1 }

    // MARK: Plan öğeleri
    func add(_ item: PlanItem) { items.append(item) }
    func update(_ item: PlanItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
    }
    func delete(at offsets: IndexSet, in category: PlanCategory) {
        let ids = items.filter { $0.category == category }.map { $0.id }
        let targets = offsets.compactMap { ids.indices.contains($0) ? ids[$0] : nil }
        items.removeAll { targets.contains($0.id) }
    }
    func resetPlan() {
        let a = WorkoutSeed.strengthA(), b = WorkoutSeed.strengthB()
        workouts = [a, b]
        items = PlanSeed.items(workoutA: a.id, workoutB: b.id)
        unlockedPhase = 1
    }

    // MARK: Tamamlama
    func setStatus(_ status: PlanStatus?, for occ: PlanOccurrence) {
        guard let status else { logs[occ.key] = nil; return }
        logs[occ.key] = PlanLog(itemId: occ.item.id,
                                occurrenceKey: occ.key,
                                day: Calendar.current.startOfDay(for: occ.when),
                                status: status)
    }
    func status(for occ: PlanOccurrence) -> PlanStatus? { logs[occ.key]?.status }

    /// Bildirimden gelen aksiyon (uygulama kapalıyken de çalışır)
    func applyNotificationAction(occurrenceKey: String, actionId: String) {
        guard let itemIdString = occurrenceKey.split(separator: "|").first,
              let itemId = UUID(uuidString: String(itemIdString)) else { return }
        let status: PlanStatus? = actionId == "DONE" ? .done : (actionId == "SKIP" ? .skipped : nil)
        guard let status else { return }
        let dayString = occurrenceKey.split(separator: "|").dropFirst().first.map(String.init) ?? ""
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let day = f.date(from: dayString) ?? Date()
        logs[occurrenceKey] = PlanLog(itemId: itemId, occurrenceKey: occurrenceKey,
                                      day: Calendar.current.startOfDay(for: day), status: status)
    }

    // MARK: Antrenman
    func workout(_ id: UUID?) -> WorkoutTemplate? {
        guard let id else { return nil }
        return workouts.first { $0.id == id }
    }
    func updateWorkout(_ w: WorkoutTemplate) {
        if let i = workouts.firstIndex(where: { $0.id == w.id }) { workouts[i] = w } else { workouts.append(w) }
    }
    func log(for templateId: UUID, on day: Date) -> WorkoutLog? {
        let d = Calendar.current.startOfDay(for: day)
        return workoutLogs.first { $0.templateId == templateId && Calendar.current.isDate($0.day, inSameDayAs: d) }
    }
    func saveWorkoutLog(_ log: WorkoutLog) {
        if let i = workoutLogs.firstIndex(where: { $0.id == log.id }) { workoutLogs[i] = log }
        else { workoutLogs.append(log) }
    }
    /// Bir hareketin en son kaydedilen setleri (geçen sefer ne yaptın?)
    func lastSets(templateId: UUID, exerciseId: UUID, before day: Date) -> [SetLog]? {
        workoutLogs
            .filter { $0.templateId == templateId && $0.day < Calendar.current.startOfDay(for: day) }
            .sorted { $0.day > $1.day }
            .compactMap { $0.entries[exerciseId.uuidString] }
            .first { !$0.isEmpty }
    }

    // MARK: Faz
    func advancePhase() {
        let maxPhase = items.map { $0.phase }.max() ?? 1
        if unlockedPhase < maxPhase { unlockedPhase += 1 }
    }

    // MARK: Kalıcılık
    private func save<T: Codable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
    private static func load<T: Codable>(_ type: T.Type, _ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
}
