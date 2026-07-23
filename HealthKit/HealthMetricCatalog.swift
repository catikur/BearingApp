import Foundation
import HealthKit

/// Apple Health'ten okunabilecek TÜM önemli veri tipleri + Whoop skorları.
/// Not: Bazı tipler yalnız iOS 16/17/18+'da vardır; cihazda mevcut değilse HealthKitManager sessizce atlar.
///
/// HEDEFLER (`target:`) HAKKINDA: Buradaki gömülü hedefler artık yalnızca YEDEK
/// katmandır. Bir metriğin kanonik günlük hedefi `GuardrailRule`'dan (kullanıcının
/// kendi kuralı) gelir; kural yoksa kalori için TDEE motorundan, o da yoksa buradaki
/// katalog değerinden. Bu öncelik `TargetEngine.resolve` içinde uygulanır.
/// Kullanıcı farklı bir hedef istiyorsa buradaki sayıyı DEĞİL, bir kural oluşturur —
/// düzenlenebilirliğin yolu budur. Bu yüzden gömülü hedefler silinmez.
enum HealthMetricCatalog {

    // Kısayol kurucu (HealthKit)
    private static func q(_ id: String, _ title: String, _ unit: String, _ cat: String,
                          _ agg: Aggregation, _ hk: HKQuantityTypeIdentifier, _ hkUnit: String,
                          target: Double? = nil, higher: Bool = true, scale: Double = 1) -> MetricDef {
        MetricDef(id: id, title: title, unit: unit, category: cat, source: .healthKit,
                  aggregation: agg, target: target, higherIsBetter: higher,
                  hkIdentifier: hk, hkUnitString: hkUnit, scale: scale)
    }

    // Kısayol kurucu (Whoop)
    private static func w(_ id: String, _ title: String, _ unit: String,
                          target: Double? = nil, higher: Bool = true) -> MetricDef {
        MetricDef(id: id, title: title, unit: unit, category: "Whoop",
                  source: .whoop, aggregation: .whoop, target: target, higherIsBetter: higher)
    }

    static let all: [MetricDef] = {
        var m: [MetricDef] = []

        // MARK: Kalp & Dolaşım
        m += [
            q("hrv","HRV (SDNN)","ms","Kalp & Dolaşım",.average,.heartRateVariabilitySDNN,"ms",target:35,higher:true),
            q("rhr","Dinlenme Nabzı","bpm","Kalp & Dolaşım",.average,.restingHeartRate,"count/min",target:62,higher:false),
            q("hr","Kalp Atışı (ort)","bpm","Kalp & Dolaşım",.average,.heartRate,"count/min",higher:false),
            q("walkingHR","Yürüyüş Nabzı","bpm","Kalp & Dolaşım",.average,.walkingHeartRateAverage,"count/min",higher:false),
            q("hrRecovery","1dk Nabız Toparlanma","bpm","Kalp & Dolaşım",.average,.heartRateRecoveryOneMinute,"count/min",higher:true),
            q("bpSys","Kan Basıncı (Sistolik)","mmHg","Kalp & Dolaşım",.average,.bloodPressureSystolic,"mmHg",target:120,higher:false),
            q("bpDia","Kan Basıncı (Diyastolik)","mmHg","Kalp & Dolaşım",.average,.bloodPressureDiastolic,"mmHg",target:80,higher:false),
            q("afib","Atriyal Fibrilasyon Yükü","%","Kalp & Dolaşım",.average,.atrialFibrillationBurden,"%",higher:false,scale:100),
        ]

        // MARK: Solunum & Vital
        m += [
            q("respRate","Solunum Hızı","/dk","Solunum & Vital",.average,.respiratoryRate,"count/min",higher:false),
            q("spo2","Kan Oksijeni (SpO2)","%","Solunum & Vital",.average,.oxygenSaturation,"%",target:95,higher:true,scale:100),
            q("bodyTemp","Vücut Sıcaklığı","°C","Solunum & Vital",.average,.bodyTemperature,"degC",higher:true),
            q("basalTemp","Bazal Vücut Sıcaklığı","°C","Solunum & Vital",.average,.basalBodyTemperature,"degC",higher:true),
            q("wristTemp","Uyku Bilek Sıcaklığı","°C","Solunum & Vital",.average,.appleSleepingWristTemperature,"degC",higher:true),
            q("vo2max","VO2 Max","mL/kg·dk","Solunum & Vital",.latest,.vo2Max,"mL/kg*min",target:40,higher:true),
        ]

        // MARK: Vücut Ölçüleri
        m += [
            q("weight","Kilo","kg","Vücut Ölçüleri",.latest,.bodyMass,"kg",target:90,higher:false),
            q("bmi","BMI","","Vücut Ölçüleri",.latest,.bodyMassIndex,"count",target:25,higher:false),
            q("bodyfat","Yağ %","%","Vücut Ölçüleri",.latest,.bodyFatPercentage,"%",target:25,higher:false,scale:100),
            q("leanMass","Yağsız Kütle","kg","Vücut Ölçüleri",.latest,.leanBodyMass,"kg",higher:true),
            q("height","Boy","cm","Vücut Ölçüleri",.latest,.height,"cm",higher:true),
            q("waist","Bel Çevresi","cm","Vücut Ölçüleri",.latest,.waistCircumference,"cm",target:94,higher:false),
        ]

        // MARK: Aktivite
        m += [
            q("steps","Adım","adım","Aktivite",.sum,.stepCount,"count",target:8000,higher:true),
            q("activeEnergy","Aktif Kalori","kcal","Aktivite",.sum,.activeEnergyBurned,"kcal",target:500,higher:true),
            q("basalEnergy","Bazal Kalori","kcal","Aktivite",.sum,.basalEnergyBurned,"kcal",higher:true),
            q("exerciseTime","Egzersiz Süresi","dk","Aktivite",.sum,.appleExerciseTime,"min",target:30,higher:true),
            q("standTime","Ayakta Süre","dk","Aktivite",.sum,.appleStandTime,"min",higher:true),
            q("distanceWalk","Yürüme/Koşu Mesafesi","km","Aktivite",.sum,.distanceWalkingRunning,"km",higher:true),
            q("distanceCycle","Bisiklet Mesafesi","km","Aktivite",.sum,.distanceCycling,"km",higher:true),
            q("flights","Merdiven Kat","kat","Aktivite",.sum,.flightsClimbed,"count",higher:true),
            q("physicalEffort","Fiziksel Efor","MET","Aktivite",.average,.physicalEffort,"kcal/hr*kg",higher:true),
            q("walkSteadiness","Yürüyüş Dengesi","%","Aktivite",.average,.appleWalkingSteadiness,"%",target:70,higher:true,scale:100),
        ]

        // MARK: Beslenme — Makro
        m += [
            q("calories","Kalori (alım)","kcal","Beslenme — Makro",.sum,.dietaryEnergyConsumed,"kcal",target:2300,higher:false),
            q("protein","Protein","g","Beslenme — Makro",.sum,.dietaryProtein,"g",target:175,higher:true),
            q("carbs","Karbonhidrat","g","Beslenme — Makro",.sum,.dietaryCarbohydrates,"g",target:150,higher:false),
            q("fat","Yağ (toplam)","g","Beslenme — Makro",.sum,.dietaryFatTotal,"g",target:78,higher:false),
            q("satFat","Doymuş Yağ","g","Beslenme — Makro",.sum,.dietaryFatSaturated,"g",target:18,higher:false),
            q("monoFat","Tekli Doymamış Yağ","g","Beslenme — Makro",.sum,.dietaryFatMonounsaturated,"g",higher:true),
            q("polyFat","Çoklu Doymamış Yağ","g","Beslenme — Makro",.sum,.dietaryFatPolyunsaturated,"g",higher:true),
            q("cholesterol","Kolesterol (diyet)","mg","Beslenme — Makro",.sum,.dietaryCholesterol,"mg",higher:false),
            q("fiber","Lif","g","Beslenme — Makro",.sum,.dietaryFiber,"g",target:30,higher:true),
            q("sugar","Şeker","g","Beslenme — Makro",.sum,.dietarySugar,"g",higher:false),
            q("water","Su","L","Beslenme — Makro",.sum,.dietaryWater,"L",target:3,higher:true),
            q("caffeine","Kafein","mg","Beslenme — Makro",.sum,.dietaryCaffeine,"mg",target:200,higher:false),
        ]

        // MARK: Beslenme — Mineraller
        m += [
            q("sodium","Sodyum","mg","Beslenme — Mineral",.sum,.dietarySodium,"mg",target:2000,higher:false),
            q("potassium","Potasyum","mg","Beslenme — Mineral",.sum,.dietaryPotassium,"mg",target:3500,higher:true),
            q("calcium","Kalsiyum","mg","Beslenme — Mineral",.sum,.dietaryCalcium,"mg",target:1000,higher:true),
            q("iron","Demir","mg","Beslenme — Mineral",.sum,.dietaryIron,"mg",target:8,higher:true),
            q("magnesium","Magnezyum","mg","Beslenme — Mineral",.sum,.dietaryMagnesium,"mg",target:400,higher:true),
            q("zinc","Çinko","mg","Beslenme — Mineral",.sum,.dietaryZinc,"mg",target:11,higher:true),
            q("iodine","İyot","µg","Beslenme — Mineral",.sum,.dietaryIodine,"mcg",target:150,higher:true),
            q("selenium","Selenyum","µg","Beslenme — Mineral",.sum,.dietarySelenium,"mcg",target:55,higher:true),
            q("copper","Bakır","mg","Beslenme — Mineral",.sum,.dietaryCopper,"mg",higher:true),
            q("manganese","Manganez","mg","Beslenme — Mineral",.sum,.dietaryManganese,"mg",higher:true),
            q("phosphorus","Fosfor","mg","Beslenme — Mineral",.sum,.dietaryPhosphorus,"mg",higher:true),
            q("chromium","Krom","µg","Beslenme — Mineral",.sum,.dietaryChromium,"mcg",higher:true),
        ]

        // MARK: Beslenme — Vitaminler
        m += [
            q("vitA","A Vitamini","µg","Beslenme — Vitamin",.sum,.dietaryVitaminA,"mcg",higher:true),
            q("vitC","C Vitamini","mg","Beslenme — Vitamin",.sum,.dietaryVitaminC,"mg",target:90,higher:true),
            q("vitD","D Vitamini","µg","Beslenme — Vitamin",.sum,.dietaryVitaminD,"mcg",target:15,higher:true),
            q("vitE","E Vitamini","mg","Beslenme — Vitamin",.sum,.dietaryVitaminE,"mg",higher:true),
            q("vitK","K Vitamini","µg","Beslenme — Vitamin",.sum,.dietaryVitaminK,"mcg",higher:true),
            q("vitB6","B6 Vitamini","mg","Beslenme — Vitamin",.sum,.dietaryVitaminB6,"mg",higher:true),
            q("vitB12","B12 Vitamini","µg","Beslenme — Vitamin",.sum,.dietaryVitaminB12,"mcg",target:2.4,higher:true),
            q("folate","Folat","µg","Beslenme — Vitamin",.sum,.dietaryFolate,"mcg",target:400,higher:true),
            q("niacin","Niasin","mg","Beslenme — Vitamin",.sum,.dietaryNiacin,"mg",higher:true),
            q("riboflavin","Riboflavin","mg","Beslenme — Vitamin",.sum,.dietaryRiboflavin,"mg",higher:true),
            q("thiamin","Tiamin","mg","Beslenme — Vitamin",.sum,.dietaryThiamin,"mg",higher:true),
            q("pantothenic","Pantotenik Asit","mg","Beslenme — Vitamin",.sum,.dietaryPantothenicAcid,"mg",higher:true),
        ]

        // MARK: Uyku & Zihin
        m += [
            MetricDef(id:"sleep",title:"Uyku",unit:"sa",category:"Uyku & Zihin",source:.healthKit,
                      aggregation:.sleepHours,target:5.75,higherIsBetter:true),
        ]

        // MARK: Laboratuvar & Diğer
        m += [
            q("glucose","Kan Şekeri","mg/dL","Laboratuvar & Diğer",.average,.bloodGlucose,"mg/dL",target:90,higher:false),
            q("alcoholBev","Alkollü İçecek","adet","Laboratuvar & Diğer",.sum,.numberOfAlcoholicBeverages,"count",higher:false),
            q("uvExposure","UV Maruziyeti","","Laboratuvar & Diğer",.average,.uvExposure,"count",higher:false),
            q("daylight","Gün Işığı Süresi","dk","Laboratuvar & Diğer",.sum,.timeInDaylight,"min",target:30,higher:true),
            q("headphoneAudio","Kulaklık Ses Maruziyeti","dBASPL","Laboratuvar & Diğer",.average,.headphoneAudioExposure,"dBASPL",higher:false),
        ]

        // MARK: Whoop (HealthKit'te olmayan skorlar — Whoop v2 API'den)
        m += [
            // Recovery
            w("whoop_recovery","Recovery","%",target:60,higher:true),
            w("whoop_hrv","Whoop HRV (RMSSD)","ms",target:40,higher:true),
            w("whoop_rhr","Whoop Dinlenme Nabzı","bpm",target:62,higher:false),
            w("whoop_spo2","Whoop SpO2","%",target:95,higher:true),
            w("whoop_skinTemp","Whoop Cilt Sıcaklığı","°C",higher:true),
            // Cycle (gün geneli)
            w("whoop_strain","Strain","",target:12,higher:true),
            w("whoop_calories","Whoop Kalori (gün)","kcal",higher:true),
            w("whoop_avgHR","Whoop Gün Ort. Nabız","bpm",higher:false),
            w("whoop_maxHR","Whoop Gün Maks. Nabız","bpm",higher:false),
            // Uyku (skorlar + evre kırılımı; süreye dokunmuyoruz, sadece kaliteyi izliyoruz)
            w("whoop_sleepPerf","Uyku Performansı","%",target:80,higher:true),
            w("whoop_sleepEff","Uyku Verimliliği","%",target:85,higher:true),
            w("whoop_sleepConsistency","Uyku Tutarlılığı","%",target:70,higher:true),
            w("whoop_sleepNeed","Uyku İhtiyacı Karşılama","%",target:90,higher:true),
            w("whoop_sleepDuration","Uyku Süresi","sa",target:5.75,higher:true),
            w("whoop_deepSleep","Derin Uyku (SWS)","sa",higher:true),
            w("whoop_remSleep","REM Uyku","sa",higher:true),
            w("whoop_lightSleep","Hafif Uyku","sa",higher:true),
            w("whoop_awakeTime","Uyanık Süre","sa",higher:false),
            w("whoop_respRate","Whoop Solunum Hızı","/dk",higher:false),
            w("whoop_disturbances","Uyku Bölünmesi","sayı",higher:false),
            // Antrenman (gün bazında toplanmış)
            w("whoop_workoutCount","Antrenman Sayısı","adet",higher:true),
            w("whoop_workoutKj","Antrenman Kalorisi","kcal",higher:true),
            w("whoop_workoutStrain","Antrenman Strain (maks)","",higher:true),
            // Profil
            w("whoop_weight","Whoop Kilo","kg",target:90,higher:false),
        ]

        return m
    }()

    static func byId(_ id: String) -> MetricDef? { all.first { $0.id == id } }

    static var categories: [String] {
        var seen = Set<String>(); var order: [String] = []
        for m in all where !seen.contains(m.category) { seen.insert(m.category); order.append(m.category) }
        return order
    }

    static func metrics(in category: String) -> [MetricDef] { all.filter { $0.category == category } }

    /// Dashboard'da varsayılan görünecek metrikler (kullanıcı sonra değiştirir)
    static let defaultEnabled: [String] = [
        "whoop_recovery","hrv","rhr","sleep","weight","bodyfat","calories","protein",
        "whoop_strain","steps","satFat","sodium","zinc","iron"
    ]
}
