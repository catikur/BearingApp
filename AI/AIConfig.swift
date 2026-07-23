import Foundation
import SwiftUI
import Security

// MARK: - Keychain (API anahtarı UserDefaults'a YAZILMAZ)
enum Keychain {
    static func save(_ value: String, key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q; add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
    static func read(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Hafıza katmanı
struct MemoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date: Date = Date()
    var pinned: Bool = false
    var auto: Bool = false        // motor tarafından otomatik yakalandıysa
}

@MainActor
final class AIMemory: ObservableObject {
    @Published var items: [MemoryItem] { didSet { persist() } }
    private let key = "ai_memory_v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let a = try? JSONDecoder().decode([MemoryItem].self, from: d) { items = a } else { items = [] }
    }

    func add(_ text: String, auto: Bool = false) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.insert(MemoryItem(text: text, auto: auto), at: 0)
    }
    func delete(at offsets: IndexSet) { items.remove(atOffsets: offsets) }
    func togglePin(_ item: MemoryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].pinned.toggle() }
    }
    func clearAuto() { items.removeAll { $0.auto && !$0.pinned } }

    /// Prompta girecek blok: sabitlenenler önce, sonra en yeniler
    func promptBlock(limit: Int) -> String {
        let ordered = items.sorted { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }
        let picked = ordered.prefix(limit)
        guard !picked.isEmpty else { return "(hafıza boş)" }
        return picked.map { "- \($0.text)" }.joined(separator: "\n")
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - OpenRouter yapılandırması
@MainActor
final class AIConfig: ObservableObject {
    @Published var enabled: Bool          { didSet { UserDefaults.standard.set(enabled, forKey: "ai_enabled") } }
    @Published var model: String          { didSet { UserDefaults.standard.set(model, forKey: "ai_model") } }
    @Published var temperature: Double    { didSet { UserDefaults.standard.set(temperature, forKey: "ai_temp") } }
    @Published var maxTokens: Int         { didSet { UserDefaults.standard.set(maxTokens, forKey: "ai_maxtok") } }
    @Published var systemPrompt: String   { didSet { UserDefaults.standard.set(systemPrompt, forKey: "ai_sysprompt") } }
    @Published var memoryLimit: Int       { didSet { UserDefaults.standard.set(memoryLimit, forKey: "ai_memlimit") } }

    // Bağlama neyin girdiğini kullanıcı seçer
    @Published var sendProfile: Bool      { didSet { UserDefaults.standard.set(sendProfile, forKey: "ai_send_profile") } }
    @Published var sendEngines: Bool      { didSet { UserDefaults.standard.set(sendEngines, forKey: "ai_send_engines") } }
    @Published var sendRules: Bool        { didSet { UserDefaults.standard.set(sendRules, forKey: "ai_send_rules") } }
    @Published var sendMetrics: Bool      { didSet { UserDefaults.standard.set(sendMetrics, forKey: "ai_send_metrics") } }
    @Published var sendLabels: Bool       { didSet { UserDefaults.standard.set(sendLabels, forKey: "ai_send_labels") } }
    @Published var sendMemory: Bool       { didSet { UserDefaults.standard.set(sendMemory, forKey: "ai_send_memory") } }

    /// Görev bazlı talimatlar — kullanıcı düzenleyebilir
    @Published var taskInstructions: [String: String] { didSet {
        if let d = try? JSONEncoder().encode(taskInstructions) {
            UserDefaults.standard.set(d, forKey: "ai_task_instructions")
        }
    } }

    @Published var hasKey: Bool = false
    private let keyName = "openrouter_api_key"

    /// Öneri listesi — kullanıcı istediği model kimliğini elle de yazabilir
    static let presetModels = [
        "anthropic/claude-sonnet-4.5",
        "anthropic/claude-opus-4.1",
        "openai/gpt-4.1",
        "google/gemini-2.5-pro",
        "meta-llama/llama-3.3-70b-instruct",
        "deepseek/deepseek-chat",
    ]

    init() {
        let d = UserDefaults.standard
        enabled      = d.object(forKey: "ai_enabled") as? Bool ?? false
        model        = d.string(forKey: "ai_model") ?? AIConfig.presetModels[0]
        temperature  = d.object(forKey: "ai_temp") as? Double ?? 0.3
        maxTokens    = d.object(forKey: "ai_maxtok") as? Int ?? 1200
        memoryLimit  = d.object(forKey: "ai_memlimit") as? Int ?? 20
        systemPrompt = d.string(forKey: "ai_sysprompt") ?? AIConfig.defaultSystemPrompt
        sendProfile  = d.object(forKey: "ai_send_profile") as? Bool ?? true
        sendEngines  = d.object(forKey: "ai_send_engines") as? Bool ?? true
        sendRules    = d.object(forKey: "ai_send_rules") as? Bool ?? true
        sendMetrics  = d.object(forKey: "ai_send_metrics") as? Bool ?? true
        sendLabels   = d.object(forKey: "ai_send_labels") as? Bool ?? true
        sendMemory   = d.object(forKey: "ai_send_memory") as? Bool ?? true
        if let d = UserDefaults.standard.data(forKey: "ai_task_instructions"),
           let m = try? JSONDecoder().decode([String: String].self, from: d) {
            taskInstructions = m
        } else {
            taskInstructions = [:]
        }
        hasKey = Keychain.read(keyName) != nil
    }

    func instruction(for task: AITask) -> String {
        taskInstructions[task.rawValue] ?? task.defaultInstruction
    }
    func setInstruction(_ text: String, for task: AITask) {
        taskInstructions[task.rawValue] = text
    }
    func resetInstruction(for task: AITask) {
        taskInstructions[task.rawValue] = nil
    }

    var apiKey: String? { Keychain.read(keyName) }
    func setKey(_ k: String) {
        let t = k.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { Keychain.delete(keyName); hasKey = false }
        else { Keychain.save(t, key: keyName); hasKey = true }
    }
    func clearKey() { Keychain.delete(keyName); hasKey = false }
    func resetPrompt() { systemPrompt = AIConfig.defaultSystemPrompt }

    /// ANA SINIRLAYICI — kullanıcı düzenleyebilir ama varsayılan bu.
    static let defaultSystemPrompt = """
    Sen bir sağlık verisi YORUMLAMA asistanısın. Kullanıcının kendi cihazındaki uygulama, \
    tüm sayısal hesapları deterministik olarak kendisi yapar ve sonuçları sana hazır verir.

    KATI KURALLAR:
    1. HESAP YAPMA. Sana verilen anlık görüntüdeki sayıları yeniden hesaplama, tahmin etme, \
       türetme veya düzeltme. Bir sayı görüntüde yoksa "bu veri bende yok" de.
    2. Sayı uydurma. Referans aralığı, yüzde, kalori, hedef vb. hiçbir değeri kafandan üretme.
    3. TANI KOYMA. "X hastalığın var" deme; "X mekanizmasıyla uyumlu bir örüntü" dilini kullan.
    4. REÇETELİ İLAÇ DOZU VERME. İlaç kararları ve dozları hekime aittir.
    5. Her önemli iddiada kanıt seviyesini etiketle: [Meta-analiz] [RKÇ] [Gözlemsel] \
       [Mekanizma] [Düşük güven].
    6. Belirsizliği gizleme. Veri eksikse, örneklem küçükse veya güven düşükse açıkça söyle.
    7. Korelasyonu nedensellik gibi sunma.
    8. Kullanıcının profiline ve hedefine uygun konuş; kendi hedefini dayatma.
    9. Türkçe, yoğun ve eyleme dönük yaz. Gereksiz giriş cümlesi kurma.

    Rolün: deterministik çıktıları bağlama oturtmak, örüntüleri ilişkilendirmek, \
    kullanıcının ne yapabileceğini ve neyi uzmana sormasını gerektiğini netleştirmek.
    """
}
