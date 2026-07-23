import Foundation

// WHOOP v2 API yanıt modelleri.
// Kaynak: developer.whoop.com (v2). Alan adları API'ye göre DOĞRULANMALI (Claude Code canlı yanıtla kontrol etsin).
// Özellikle şüpheli: sayfalama param'ı (nextToken) + yanıt alanı (next_token);
// workout: sport_name vs sport_id, zone_duration alt-alan adları; body measurement path'i.

// Sayfalı yanıt sarmalayıcı
struct WhoopPage<T: Codable>: Codable {
    let records: [T]
    let next_token: String?
}

// MARK: Recovery
struct WhoopRecovery: Codable {
    let cycle_id: Int?
    let sleep_id: String?
    let user_id: Int?
    let created_at: String?
    let updated_at: String?
    let score_state: String?
    let score: Score?

    struct Score: Codable {
        let user_calibrating: Bool?
        let recovery_score: Double?
        let resting_heart_rate: Double?
        let hrv_rmssd_milli: Double?
        let spo2_percentage: Double?
        let skin_temp_celsius: Double?
    }
}

// MARK: Cycle (Strain + gün geneli enerji/nabız)
struct WhoopCycle: Codable {
    let id: Int?
    let user_id: Int?
    let created_at: String?
    let start: String?
    let end: String?
    let timezone_offset: String?
    let score_state: String?
    let score: Score?

    struct Score: Codable {
        let strain: Double?
        let kilojoule: Double?
        let average_heart_rate: Double?
        let max_heart_rate: Double?
    }
}

// MARK: Sleep (gece uykusu + evre kırılımı)
struct WhoopSleep: Codable {
    let id: String?
    let user_id: Int?
    let start: String?
    let end: String?
    let nap: Bool?
    let score_state: String?
    let score: Score?

    struct Score: Codable {
        let sleep_performance_percentage: Double?
        let sleep_consistency_percentage: Double?
        let sleep_efficiency_percentage: Double?
        let respiratory_rate: Double?
        let sleep_needed: SleepNeeded?
        let stage_summary: StageSummary?

        struct SleepNeeded: Codable {
            let baseline_milli: Double?
            let need_from_sleep_debt_milli: Double?
            let need_from_recent_strain_milli: Double?
            let need_from_recent_nap_milli: Double?
        }
        struct StageSummary: Codable {
            let total_in_bed_time_milli: Double?
            let total_awake_time_milli: Double?
            let total_no_data_time_milli: Double?
            let total_light_sleep_time_milli: Double?
            let total_slow_wave_sleep_time_milli: Double?   // derin uyku (SWS)
            let total_rem_sleep_time_milli: Double?
            let sleep_cycle_count: Int?
            let disturbance_count: Int?
        }
    }
}

// MARK: Workout (antrenman bazlı — strain/HR/kalori/zone)
struct WhoopWorkout: Codable {
    let id: String?              // v2 uuid string olabilir; v1'de Int idi
    let user_id: Int?
    let created_at: String?
    let start: String?
    let end: String?
    let timezone_offset: String?
    let sport_name: String?      // v2; v1'de sport_id (Int)
    let sport_id: Int?
    let score_state: String?
    let score: Score?

    struct Score: Codable {
        let strain: Double?
        let average_heart_rate: Double?
        let max_heart_rate: Double?
        let kilojoule: Double?
        let percent_recorded: Double?
        let distance_meter: Double?
        let altitude_gain_meter: Double?
        let altitude_change_meter: Double?
        let zone_duration: ZoneDuration?

        struct ZoneDuration: Codable {
            let zone_zero_milli: Double?
            let zone_one_milli: Double?
            let zone_two_milli: Double?
            let zone_three_milli: Double?
            let zone_four_milli: Double?
            let zone_five_milli: Double?
        }
    }
}

// MARK: Body measurement (profil ölçüleri — tek kayıt)
struct WhoopBodyMeasurement: Codable {
    let height_meter: Double?
    let weight_kilogram: Double?
    let max_heart_rate: Double?
}

// Token saklama
struct WhoopToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var isValid: Bool { Date() < expiresAt.addingTimeInterval(-60) }
}
