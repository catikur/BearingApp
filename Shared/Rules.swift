import Foundation

enum RuleKind: String, Codable, CaseIterable, Identifiable {
    case metricThreshold      // metrik günlük değeri eşikle karşılaştır
    case percentOfEnergy      // makro → toplam kalorinin yüzdesi (ör. doymuş yağ ≤ %7)
    case tagFrequency         // etiket haftalık sıklık (ör. alkol ≤ 1/hafta)
    case planAdherence        // plan kategorisi uyum yüzdesi (ör. suplement ≥ %80)

    var id: String { rawValue }
    var label: String {
        switch self {
        case .metricThreshold: return "Metrik eşiği"
        case .percentOfEnergy: return "Enerji yüzdesi"
        case .tagFrequency:    return "Etiket sıklığı"
        case .planAdherence:   return "Plan uyumu"
        }
    }
}

enum RuleOperator: String, Codable, CaseIterable, Identifiable {
    case atLeast, atMost, between
    var id: String { rawValue }
    var label: String {
        switch self {
        case .atLeast: return "en az"
        case .atMost:  return "en fazla"
        case .between: return "arasında"
        }
    }
    var symbol: String {
        switch self {
        case .atLeast: return "≥"
        case .atMost:  return "≤"
        case .between: return "↔"
        }
    }
}

/// Kullanıcının kendi belirlediği kural. Hiçbiri kodda sabit değil — hepsi düzenlenebilir/silinebilir.
struct GuardrailRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var kind: RuleKind = .metricThreshold
    var targetId: String                      // metrik id veya etiket id
    var op: RuleOperator = .atMost
    var value: Double
    var value2: Double? = nil                 // "arasında" için üst sınır
    var kcalPerGram: Double = 9               // percentOfEnergy için (yağ 9, protein/karb 4)
    var weight: Double = 1                    // toplam skordaki ağırlığı
    var enabled: Bool = true
    var note: String = ""                     // kullanıcı gerekçesi (LLM bağlamına da girer)

    /// İnsan-okur özet: "Sodyum ≤ 2000 mg"
    func summary() -> String {
        let unit: String = {
            switch kind {
            case .percentOfEnergy: return "% enerji"
            case .tagFrequency:    return "gün/hafta"
            case .planAdherence:   return "% uyum"
            case .metricThreshold: return HealthMetricCatalog.byId(targetId)?.unit ?? ""
            }
        }()
        if op == .between, let v2 = value2 {
            return "\(name): \(fmt(value))–\(fmt(v2)) \(unit)"
        }
        return "\(name): \(op.symbol) \(fmt(value)) \(unit)"
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

extension GuardrailRule {
    /// İlk kurulumda önerilen başlangıç seti — kullanıcı hepsini değiştirebilir/silebilir.
    /// (Sıfırla dediğinde bu sete döner.)
    static var starterSet: [GuardrailRule] {
        [
            GuardrailRule(name: "Protein", kind: .metricThreshold, targetId: "protein",
                          op: .atLeast, value: 150, weight: 1.5,
                          note: "Açıkta kas koruma"),
            GuardrailRule(name: "Sodyum", kind: .metricThreshold, targetId: "sodium",
                          op: .atMost, value: 2000, weight: 1.5,
                          note: "Vestibüler semptom yönetimi"),
            GuardrailRule(name: "Doymuş yağ", kind: .percentOfEnergy, targetId: "satFat",
                          op: .atMost, value: 7, kcalPerGram: 9, weight: 1.5,
                          note: "Apo B / LDL hedefi"),
            GuardrailRule(name: "Lif", kind: .metricThreshold, targetId: "fiber",
                          op: .atLeast, value: 30, weight: 1,
                          note: "Mikrobiyom + insülin duyarlılığı"),
            GuardrailRule(name: "Su", kind: .metricThreshold, targetId: "water",
                          op: .atLeast, value: 2.5, weight: 1,
                          note: "Ürat atılımı"),
            GuardrailRule(name: "Şeker", kind: .metricThreshold, targetId: "sugar",
                          op: .atMost, value: 25, weight: 1,
                          note: "Fruktoz → ürik asit / insülin"),
            GuardrailRule(name: "Alkol", kind: .tagFrequency, targetId: "alcohol",
                          op: .atMost, value: 1, weight: 1.5,
                          note: "HRV + ürik asit + karaciğer"),
            GuardrailRule(name: "Suplement uyumu", kind: .planAdherence,
                          targetId: PlanCategory.supplement.rawValue,
                          op: .atLeast, value: 80, weight: 1,
                          note: "Planı sürdürebilme — faz ilerlemesi buna bağlı"),
            GuardrailRule(name: "Boyun/TME rutini", kind: .planAdherence,
                          targetId: PlanCategory.mobility.rawValue,
                          op: .atLeast, value: 70, weight: 1,
                          note: "4 haftalık rutin sürdürülmezse etkisi ölçülemez"),
        ]
    }
}
