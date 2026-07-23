import Foundation
import SwiftUI

/// Bir güne iliştirilen yerel etiket(ler) + serbest not. Cihazda saklanır, dışarı çıkmaz.
struct DayLabel: Codable, Identifiable {
    var dateKey: String            // "yyyy-MM-dd"
    var tags: [String]             // TagCatalog id'leri
    var note: String
    var id: String { dateKey }
}

/// Önceden tanımlı etiket (emoji + renk + başlık). Kullanıcı ayrıca serbest not ekleyebilir.
struct DayTag: Identifiable, Hashable {
    let id: String
    let title: String
    let emoji: String
    let colorHex: String
    var color: Color { Color(hex: colorHex) }
}

/// Atilla'nın profiline göre seçilmiş etiketler (alkol/serbest öğün/oruç korelasyonları için).
enum TagCatalog {
    static let all: [DayTag] = [
        DayTag(id: "alcohol",    title: "Alkol",           emoji: "🍺", colorHex: "C0392B"),
        DayTag(id: "cheat",      title: "Serbest öğün",    emoji: "🍕", colorHex: "E67E22"),
        DayTag(id: "fasting",    title: "Uzun oruç (24s)", emoji: "⏳", colorHex: "16A085"),
        DayTag(id: "sick",       title: "Hasta",           emoji: "🤒", colorHex: "8E44AD"),
        DayTag(id: "stress",     title: "Yüksek stres",    emoji: "😣", colorHex: "D35400"),
        DayTag(id: "poorSleep",  title: "Kötü uyku",       emoji: "😴", colorHex: "2980B9"),
        DayTag(id: "training",   title: "Ağır antrenman",  emoji: "💪", colorHex: "27AE60"),
        DayTag(id: "travel",     title: "Seyahat",         emoji: "✈️", colorHex: "7F8C8D"),
        DayTag(id: "supplement", title: "Yeni suplement",  emoji: "💊", colorHex: "2C3E50"),
    ]
    static func tag(_ id: String) -> DayTag? { all.first { $0.id == id } }
}

/// Basit hex → Color yardımcısı (etiket renkleri için).
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(.sRGB,
                  red:   Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue:  Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}
