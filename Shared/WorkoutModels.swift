import Foundation

// MARK: - Hareket
struct Exercise: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sets: Int = 3
    var reps: String = "8-10"          // aralık olabilir
    var targetRPE: Double? = 7
    var restSeconds: Int = 90
    var tempo: String = ""
    var note: String = ""
    var progression: String = ""       // ilerleme kuralı
}

// MARK: - Seans şablonu
struct WorkoutTemplate: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var focus: String = ""
    var exercises: [Exercise] = []
    var note: String = ""
    var estimatedMinutes: Int = 45
}

// MARK: - Log
struct SetLog: Codable, Identifiable, Equatable {
    var id = UUID()
    var setIndex: Int
    var weight: Double? = nil
    var reps: Int? = nil
    var rpe: Double? = nil
    var done: Bool = false
}

struct WorkoutLog: Codable, Identifiable, Equatable {
    var id = UUID()
    var templateId: UUID
    var day: Date                              // gün başı
    var entries: [String: [SetLog]] = [:]      // exercise.id.uuidString -> setler
    var note: String = ""
    var durationMinutes: Int? = nil
    var completedAt: Date? = nil

    var completedSets: Int { entries.values.flatMap { $0 }.filter { $0.done }.count }
    var totalVolume: Double {
        entries.values.flatMap { $0 }
            .compactMap { s -> Double? in
                guard s.done, let w = s.weight, let r = s.reps else { return nil }
                return w * Double(r)
            }
            .reduce(0, +)
    }
}

// MARK: - Başlangıç şablonları
/// 3–4 günlük yapı: 2 kuvvet + mevcut Muay Thai + yürüyüş.
/// Kardiyak güvenlik notu gereği orta yoğunlukta (RPE ≤ 7-8), Valsalva'sız kurgulandı.
enum WorkoutSeed {

    static func strengthA() -> WorkoutTemplate {
        WorkoutTemplate(
            name: "Kuvvet A",
            focus: "Alt gövde + itme",
            exercises: [
                Exercise(name: "Goblet squat", sets: 3, reps: "8-10", targetRPE: 7, restSeconds: 90,
                         note: "Topuk yerde, göğüs açık", progression: "3×10 RPE 7 olduğunda ağırlığı artır"),
                Exercise(name: "Dumbbell bench press", sets: 3, reps: "8-10", targetRPE: 7, restSeconds: 90,
                         progression: "Üst tekrar hedefine ulaşınca +2 kg"),
                Exercise(name: "Romanian deadlift (hafif)", sets: 3, reps: "10-12", targetRPE: 6, restSeconds: 90,
                         note: "Sırt nötr, dizler hafif bükük — hamstring gerginliğinde dur"),
                Exercise(name: "Seated row", sets: 3, reps: "10-12", targetRPE: 7, restSeconds: 75,
                         note: "Kürek kemiklerini birleştir — forward head postür için değerli"),
                Exercise(name: "Plank", sets: 3, reps: "30-45 sn", targetRPE: 6, restSeconds: 60),
                Exercise(name: "Band pull-apart", sets: 2, reps: "15", targetRPE: 5, restSeconds: 45,
                         note: "Postür yardımcısı"),
            ],
            note: "Kardiyoloji onayı gelene kadar RPE 8 üstüne çıkma, nefes tutup ıkınma (Valsalva).",
            estimatedMinutes: 45)
    }

    static func strengthB() -> WorkoutTemplate {
        WorkoutTemplate(
            name: "Kuvvet B",
            focus: "Alt gövde + çekme",
            exercises: [
                Exercise(name: "Trap bar / dumbbell deadlift", sets: 3, reps: "6-8", targetRPE: 7, restSeconds: 120,
                         note: "Sırt nötr, kalçadan başlat", progression: "Form bozulmadan 3×8 → ağırlık artır"),
                Exercise(name: "Lat pulldown", sets: 3, reps: "8-10", targetRPE: 7, restSeconds: 90),
                Exercise(name: "Bulgar split squat", sets: 3, reps: "8 / bacak", targetRPE: 7, restSeconds: 75,
                         note: "Denge zorlanırsa destek al"),
                Exercise(name: "Overhead press (hafif)", sets: 3, reps: "8-10", targetRPE: 6, restSeconds: 90,
                         note: "Omuz/boyun rahatsızlık verirse aralığı kısalt"),
                Exercise(name: "Face pull", sets: 3, reps: "15", targetRPE: 6, restSeconds: 60,
                         note: "Servikal postür için en yararlı hareketlerden"),
                Exercise(name: "Dead bug", sets: 3, reps: "10 / taraf", targetRPE: 5, restSeconds: 45),
            ],
            note: "Baş pozisyonu hızlı değişen hareketlerden kaçın (BPPV tetikleyebilir).",
            estimatedMinutes: 45)
    }
}
