import Foundation

enum BioSex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Erkek" : "Kadın" }
}

/// Kullanıcı profili — tüm motorlar bunu okur. Hiçbir değer kodda sabit değildir.
struct UserProfile: Codable, Equatable {
    var name: String = ""
    var age: Int = 40
    var sex: BioSex = .male
    var heightCm: Double = 183

    // Hedef
    var targetWeightKg: Double = 85
    var targetRateKgPerWeek: Double = 0.6      // hedeflenen haftalık değişim (pozitif = kayıp)
    var startWeightKg: Double? = nil           // boşsa serideki ilk ölçüm kullanılır
    var startDate: Date? = nil

    /// LLM katmanına verilecek amaç/bağlam metni (serbest, kullanıcı yazar)
    var goalNote: String = ""

    /// Mifflin-St Jeor bazal metabolizma — yalnızca referans.
    /// Adaptif TDEE bunu DEĞİL, gerçek ölçümü kullanır.
    func bmr(weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }
}

/// Motor parametreleri — kullanıcı ayarlardan değiştirebilir.
struct EngineSettings: Codable, Equatable {

    // MARK: Adaptif TDEE
    var tdeeWindowDays: Int = 21               // hesap penceresi
    var tdeeMinDays: Int = 14                  // altında hesap yapma
    var kcalPerKg: Double = 7700               // 1 kg vücut ağırlığı ≈ kcal
    var tdeeMinIntakeCoverage: Double = 0.6    // pencerede en az bu oranda gün loglanmış olmalı

    // MARK: Kilo trendi
    var emaHalfLifeDays: Double = 7            // düzleştirme yarı ömrü
    var rateWindowDays: Int = 28               // hız (kg/hafta) regresyon penceresi

    // MARK: Baseline / sapma
    var baselineWindowDays: Int = 30
    var baselineZThreshold: Double = 1.5       // |z| bu eşiği aşarsa sapma sayılır
    var baselineMinSamples: Int = 10
    var baselineMetricIds: [String] = ["hrv", "rhr", "respRate", "wristTemp", "whoop_recovery"]
    var compositeMetricIds: [String] = ["rhr", "respRate", "wristTemp", "hrv"]
    var compositeMinFiring: Int = 3            // kaç metrik aynı anda kötü yönde saparsa bileşik uyarı

    // MARK: Guardrail uyum
    var guardrailWindowDays: Int = 14
    var guardrailGoodScore: Double = 80        // bu skorun üstü "iyi"

    // MARK: Günlük hedef ilerlemesi (Bugün bloğu)
    /// "Bugün" sekmesindeki beslenme ilerleme bloğunda gösterilecek metrikler.
    /// Hedefleri TargetEngine çözer; burada yalnızca hangi metriklerin görüneceği tutulur.
    var todayProgressMetricIds: [String] = ["calories", "protein", "carbs", "fat",
                                            "satFat", "fiber", "water", "sodium"]

    // MARK: Korelasyon keşfi (otomatik tarama)
    var discoveryMinN: Int = 8                 // bir çift için gereken minimum ortak gün
    var discoveryTopCount: Int = 15            // listede gösterilecek bulgu sayısı
    var discoveryScanNextDay: Bool = true      // ertesi gün etkisini de tara (lag 1)
    var discoveryFilterTwins: Bool = true      // aynı şeyi ölçen çiftleri gizle
    var discoveryFilterFamilies: Bool = true   // mekanik olarak birbirinin parçası olanları gizle

    static let `default` = EngineSettings()
}
