import Foundation

/// LLM'in yapabileceği görevler. Her görevin kendi talimatı ve bağlam ihtiyacı var.
/// Talimatlar kullanıcı tarafından düzenlenebilir (Ayarlar → Yapay Zekâ → Görevler).
enum AITask: String, Codable, CaseIterable, Identifiable {
    case chat
    case nutritionPlan
    case trainingAdjust
    case planReview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat:           return "Serbest soru"
        case .nutritionPlan:  return "Beslenme planı hazırla"
        case .trainingAdjust: return "Antrenmanı ayarla"
        case .planReview:     return "Planı gözden geçir"
        }
    }

    var icon: String {
        switch self {
        case .chat:           return "bubble.left.and.text.bubble.right"
        case .nutritionPlan:  return "fork.knife"
        case .trainingAdjust: return "figure.strengthtraining.traditional"
        case .planReview:     return "checklist.checked"
        }
    }

    /// Yapılandırılmış öneri (JSON) bekleniyor mu?
    var structured: Bool { self != .chat }

    /// Hangi bağlam bölümleri bu görev için anlamlı
    var needsNutritionDetail: Bool { self == .nutritionPlan || self == .planReview }
    var needsTrainingDetail: Bool { self == .trainingAdjust || self == .planReview }

    var defaultInstruction: String {
        switch self {
        case .chat:
            return """
            Kullanıcının sorusunu, yukarıdaki deterministik anlık görüntüye dayanarak yanıtla.
            Sayı üretme; yalnızca verilen sayıları yorumla.
            """

        case .nutritionPlan:
            return """
            GÖREV: Kullanıcı için günlük beslenme planı öner.

            Uyman gerekenler:
            - Kalori hedefi olarak anlık görüntüdeki "Hedef hız için önerilen alım" değerini kullan. \
            Kendi kalori hesabını yapma. O değer yoksa plan üretme, hangi verinin eksik olduğunu söyle.
            - Kullanıcının guardrail kurallarının HEPSİNE uy (protein, sodyum, doymuş yağ, lif vb.).
            - "KESİN KAÇINILACAKLAR" ve intolerans listesini asla ihlal etme.
            - Mevcut yeme penceresini ve öğün saatlerini koru; değiştireceksen gerekçelendir.
            - Porsiyonları gram cinsinden ver ki takip edilebilsin.
            - Suplement önerme, doz yazma. Suplement kullanıcının klinisyeniyle belirlenir.
            """

        case .trainingAdjust:
            return """
            GÖREV: Mevcut antrenman planını gözden geçir ve ayarla.

            Uyman gerekenler:
            - Kullanıcının haftalık kaç gün antrenman yapabildiğine saygı göster; gün sayısını artırma \
            (kullanıcı açıkça istemedikçe).
            - Kas koruma birinci öncelik; kalori açığı varken hacmi aşırı artırma.
            - Bekleyen klinik onay varsa (ör. kardiyoloji) yoğunluğu o sınırın üstüne çıkarma.
            - Ekipman listesinde olmayan hareket önerme.
            - Baseline sapmaları veya düşük toparlanma varsa yükü artırmak yerine korumayı öner.
            - Her değişiklik için tek cümlelik gerekçe yaz.
            """

        case .planReview:
            return """
            GÖREV: Mevcut planı ve uyum verisini incele; sürdürülebilirliği artıracak öneriler sun.

            Uyman gerekenler:
            - Uyumu düşük olan öğeleri tespit et ve nedenini sorgula; gerekirse basitleştir veya saatini değiştir.
            - Tek değişken kuralına uy: aynı anda en fazla 2 yeni değişken öner.
            - Zaten iyi giden şeyleri değiştirme.
            - Bildirim yükünü artırmamaya çalış.
            """
        }
    }

    /// Yapılandırılmış çıktı şeması — modele birebir verilir
    static let outputSchema = """
    ÇIKTI BİÇİMİ — SADECE geçerli JSON döndür. Markdown, açıklama veya kod bloğu işareti EKLEME.

    {
      "summary": "1-2 cümle özet",
      "rationale": "Neden bu öneri — deterministik sayılara atıfla",
      "targets": {
        "kcal": 0, "proteinG": 0, "carbG": 0, "fatG": 0,
        "sodiumMg": 0, "satFatPctEnergy": 0, "fiberG": 0
      },
      "items": [
        {
          "action": "add",
          "title": "Öğün 1",
          "category": "meal",
          "detail": "180 g tavuk + 200 g sebze + 15 g zeytinyağı",
          "scheduleType": "daily",
          "weekdays": [],
          "times": ["12:00"],
          "phase": 1,
          "note": "gerekçe"
        }
      ],
      "workoutChanges": [
        {
          "templateName": "Kuvvet A",
          "action": "update",
          "exercises": [
            { "name": "Goblet squat", "sets": 3, "reps": "8-10", "targetRPE": 7, "note": "" }
          ],
          "note": "gerekçe"
        }
      ],
      "warnings": ["dikkat edilmesi gereken şeyler"]
    }

    Kurallar:
    - "action": "add" | "update" | "disable"
    - "category": meal | supplement | training | mobility | circadian | measurement | appointment
    - "scheduleType": daily | weekdays | everyNDays | oneOff
    - "weekdays": 1=Pazar … 7=Cumartesi
    - "times": "HH:mm" biçiminde
    - Bilmediğin/gerekmeyen alanı boş bırak veya çıkar; UYDURMA.
    - "targets" içine yalnızca anlık görüntüdeki sayılarla tutarlı değerler yaz.
    """
}
