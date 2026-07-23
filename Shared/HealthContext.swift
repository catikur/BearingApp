import Foundation

/// Uygulamanın ölçemediği ama LLM'in bilmesi gereken bağlam.
/// Tamamen kullanıcı tarafından yazılır; hiçbir kısmı otomatik doldurulmaz.
struct HealthContext: Codable, Equatable {

    /// Aktif durumlar / tanılar (kullanıcının kendi ifadesiyle)
    var conditions: [String] = []

    /// Kesin kaçınılacaklar — LLM bunları ihlal eden öneri veremez
    var avoid: [String] = []

    /// Gıda intoleransı / tetikleyici
    var intolerances: [String] = []

    /// Sevilen / tercih edilen yiyecekler, mutfak
    var preferences: [String] = []

    /// Antrenman ekipmanı ve erişim
    var equipment: [String] = []

    /// Zaman kısıtları (iş saatleri, antrenman uygunluğu)
    var scheduleNotes: String = ""

    /// Kilit lab değerleri — serbest metin çiftleri ("Apo B", "138 mg/dL · Nis 2025")
    var keyLabs: [LabNote] = []

    /// Uzman yönlendirmeleri / bekleyen onaylar
    var pendingClinical: [String] = []

    /// Serbest not
    var freeNotes: String = ""

    struct LabNote: Codable, Equatable, Identifiable {
        var id = UUID()
        var name: String
        var value: String
        var note: String = ""
    }

    var isEmpty: Bool {
        conditions.isEmpty && avoid.isEmpty && intolerances.isEmpty && preferences.isEmpty
            && equipment.isEmpty && scheduleNotes.isEmpty && keyLabs.isEmpty
            && pendingClinical.isEmpty && freeNotes.isEmpty
    }

    /// LLM'e giden bölüm — başlıklandırılmış, amaca yönelik
    func promptBlock() -> String {
        guard !isEmpty else { return "" }
        var b: [String] = ["\n## Kişisel bağlam (kullanıcının kendi beyanı)"]
        func list(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            b.append("**\(title):** " + items.joined(separator: " · "))
        }
        list("Aktif durumlar", conditions)
        list("KESİN KAÇINILACAKLAR", avoid)
        list("İntolerans / tetikleyici", intolerances)
        list("Tercihler", preferences)
        list("Antrenman ekipmanı", equipment)
        if !scheduleNotes.isEmpty { b.append("**Zaman kısıtları:** \(scheduleNotes)") }
        if !keyLabs.isEmpty {
            b.append("**Kilit lab değerleri:**")
            for l in keyLabs {
                b.append("- \(l.name): \(l.value)" + (l.note.isEmpty ? "" : " — \(l.note)"))
            }
        }
        list("Bekleyen uzman onayı", pendingClinical)
        if !freeNotes.isEmpty { b.append("**Not:** \(freeNotes)") }
        return b.joined(separator: "\n")
    }
}
