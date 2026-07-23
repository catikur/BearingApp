import Foundation
import SwiftUI

/// Profil + motor parametreleri + guardrail kuralları. Hepsi kullanıcıya ait, cihazda saklanır.
@MainActor
final class ProfileStore: ObservableObject {

    @Published var profile: UserProfile { didSet { save(profile, pKey) } }
    @Published var settings: EngineSettings { didSet { save(settings, sKey) } }
    @Published var rules: [GuardrailRule] { didSet { save(rules, rKey) } }
    @Published var context: HealthContext { didSet { save(context, cKey) } }

    private let pKey = "user_profile_v1"
    private let sKey = "engine_settings_v1"
    private let rKey = "guardrail_rules_v1"
    private let cKey = "health_context_v1"

    init() {
        profile  = Self.load(UserProfile.self, "user_profile_v1")     ?? UserProfile()
        settings = Self.load(EngineSettings.self, "engine_settings_v1") ?? .default
        rules    = Self.load([GuardrailRule].self, "guardrail_rules_v1") ?? GuardrailRule.starterSet
        context  = Self.load(HealthContext.self, "health_context_v1") ?? HealthContext()
    }

    // MARK: Kural yönetimi
    func addRule(_ r: GuardrailRule) { rules.append(r) }
    func updateRule(_ r: GuardrailRule) {
        if let i = rules.firstIndex(where: { $0.id == r.id }) { rules[i] = r }
    }
    func deleteRules(at offsets: IndexSet) { rules.remove(atOffsets: offsets) }
    func moveRules(from s: IndexSet, to d: Int) { rules.move(fromOffsets: s, toOffset: d) }
    func resetRules() { rules = GuardrailRule.starterSet }
    func resetSettings() { settings = .default }

    /// Motorların ihtiyaç duyduğu metrikler — dashboard'da etkin olmasalar bile yüklenmeli
    var requiredMetricIds: [String] {
        var ids: Set<String> = ["weight", "calories"]
        ids.formUnion(settings.baselineMetricIds)
        ids.formUnion(settings.compositeMetricIds)
        for r in rules where r.enabled {
            if r.kind == .metricThreshold || r.kind == .percentOfEnergy { ids.insert(r.targetId) }
            if r.kind == .percentOfEnergy { ids.insert("calories") }
        }
        return Array(ids)
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
