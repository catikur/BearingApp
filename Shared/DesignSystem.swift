//
//  DesignSystem.swift
//  Bearing
//
//  FAZ 1 — Tasarım sistemi tek kaynağı.
//  Renk semantiği, boşluk/köşe ölçekleri, tipografi rolleri ve
//  temel bileşen stilleri burada tanımlanır.
//
//  KURALLAR (bkz. DESIGN.md):
//  - Renk iki ayrı kanal taşır: Kimlik (düşük doygunluk) ve Durum (yüksek doygunluk).
//  - Kırmızı (.critical) SADECE bileşik sapma sinyali + engelleyici doğrulama uyarısı içindir.
//  - Kodda serbest boşluk/yarıçap sayısı kullanma — DS.Space ve DS.Radius'tan al.
//  - Sabit .system(size:) kullanma — DS.Font rolleri Dynamic Type ile ölçeklenir.
//  - Liquid Glass sadece fonksiyonel katmanda (tab bar, toolbar, yüzen kontroller).
//    İçerik kartlarına cam efekti UYGULANMAZ.
//

import SwiftUI

// MARK: - Namespace

/// Tasarım sistemi kök isim alanı. Tüm ekranlar değerleri buradan alır.
enum DS {

    // MARK: - Boşluk ölçeği (4/8/12/16/24/32)

    /// Boşluk ölçeği. Kodda serbest sayı kalmasın; ara değer gerekiyorsa
    /// önce bu ölçeğe yeni bir adım eklemeyi tartış (DESIGN.md).
    enum Space {
        /// 4pt — ikon/metin arası mikro boşluk
        static let xs: CGFloat = 4
        /// 8pt — satır içi eleman arası
        static let sm: CGFloat = 8
        /// 12pt — kart içi dikey ritim
        static let md: CGFloat = 12
        /// 16pt — kart iç dolgusu, ekran kenar boşluğu
        static let lg: CGFloat = 16
        /// 24pt — bölümler arası
        static let xl: CGFloat = 24
        /// 32pt — büyük bölüm ayrımı
        static let xxl: CGFloat = 32
    }

    // MARK: - Köşe yarıçapı ölçeği (8/12/16/20)

    enum Radius {
        /// 8pt — chip, rozet, küçük kontrol
        static let sm: CGFloat = 8
        /// 12pt — iç içe kart, küçük kart
        static let md: CGFloat = 12
        /// 16pt — standart kart kabuğu
        static let lg: CGFloat = 16
        /// 20pt — sheet, büyük yüzey
        static let xl: CGFloat = 20
    }

    // MARK: - Dokunma alanı

    enum Touch {
        /// Minimum dokunma alanı (HIG)
        static let minTarget: CGFloat = 44
        /// Konforlu hedef — spor salonu gibi tek elle/hareket halinde kullanım (BigStepper, birincil butonlar)
        static let comfortable: CGFloat = 56
    }
}

// MARK: - Renk semantiği

extension DS {

    /// DURUM kanalı — yüksek doygunluk, NADİR kullanım.
    /// Anlam taşır; dekorasyon için kullanılmaz.
    enum Status {
        /// Kritik: SADECE bileşik sapma sinyali + engelleyici doğrulama uyarısı.
        /// Rutin "hedefin altındasın" durumu kritik DEĞİLDİR — nötr gösterilir.
        static let critical = Color.adaptive(light: 0xBF3B2E, dark: 0xD95B4E)

        /// Dikkat: eylem gerektiren ama acil olmayan.
        static let attention = Color.adaptive(light: 0xD98324, dark: 0xE59A47)

        /// Olumlu: onay, kutlama değil. Konfeti yok.
        static let positive = Color.adaptive(light: 0x3E8E6B, dark: 0x5BAA87)

        /// Bilgi: ana vurgu ile aynı ton.
        static let info = Color.adaptive(light: 0x2E6F7E, dark: 0x4E97A8)

        /// Nötr: rutin sapmalar, pasif durumlar.
        static let neutral = Color.adaptive(light: 0x8A9BA3, dark: 0x8FA3AC)
    }

    /// Yüzey ve metin rolleri.
    enum Surface {
        /// Zemin — soft blue-tinted paper / koyu (saf siyah değil)
        static let background = Color.adaptive(light: 0xF5F7F8, dark: 0x12181B)
        /// Kart yüzeyi
        static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x1B2429)
        /// Ayırıcı / kenar
        static let divider = Color.adaptive(light: 0xE3E8EB, dark: 0x2A353B)
        /// Ana vurgu — donuk derin teal
        static let accent = Color.adaptive(light: 0x2E6F7E, dark: 0x4E97A8)
    }

    enum Text {
        /// Birincil — deep slate, saf siyah değil
        static let primary = Color.adaptive(light: 0x1B2B33, dark: 0xE8EDEF)
        /// İkincil
        static let secondary = Color.adaptive(light: 0x5F7178, dark: 0x9FB0B7)
        /// Üçüncül
        static let tertiary = Color.adaptive(light: 0x8A9BA3, dark: 0x71838B)
    }
}

// MARK: - Kimlik kanalı: plan kategorileri + etiketler

/// KİMLİK kanalı — düşük doygunluk, sık kullanım, hepsi aynı görsel ağırlıkta.
/// `PlanCategory.color` ve `TagCatalog.colorHex` bu tek kaynaktan beslenir.
/// Dark varyantlar: biraz daha açık + biraz daha doygun (çamurlaşma önlemi).
enum IdentityColor: String, CaseIterable {
    case meal          // Öğün — soluk kum
    case supplement    // Suplement — soluk mor
    case workout       // Antrenman — adaçayı
    case neckTMJ       // Boyun / TME — soluk mavi-yeşil
    case circadian     // Sirkadiyen — soluk hardal
    case measurement   // Ölçüm — soluk çelik mavi
    case appointment   // Randevu / Lab — toz pudra pembe

    var color: Color {
        switch self {
        case .meal:        return Color.adaptive(light: 0xB98A5E, dark: 0xCFA97E)
        case .supplement:  return Color.adaptive(light: 0x8E7BA8, dark: 0xA795C2)
        case .workout:     return Color.adaptive(light: 0x5E8C74, dark: 0x7BAA92)
        case .neckTMJ:     return Color.adaptive(light: 0x6E9BA8, dark: 0x8BB6C2)
        case .circadian:   return Color.adaptive(light: 0xC2A25C, dark: 0xD6BA7C)
        case .measurement: return Color.adaptive(light: 0x7089A8, dark: 0x8EA5C2)
        case .appointment: return Color.adaptive(light: 0xB07C8E, dark: 0xC697A8)
        }
    }

    /// Türkçe görünen ad
    var displayName: String {
        switch self {
        case .meal:        return "Öğün"
        case .supplement:  return "Suplement"
        case .workout:     return "Antrenman"
        case .neckTMJ:     return "Boyun / TME"
        case .circadian:   return "Sirkadiyen"
        case .measurement: return "Ölçüm"
        case .appointment: return "Randevu / Lab"
        }
    }

    var symbolName: String {
        switch self {
        case .meal:        return "fork.knife"
        case .supplement:  return "pills"
        case .workout:     return "dumbbell"
        case .neckTMJ:     return "figure.flexibility"
        case .circadian:   return "sun.max"
        case .measurement: return "chart.xyaxis.line"
        case .appointment: return "stethoscope"
        }
    }
}

// MARK: - Güven seviyesi (imza öğesi: belirsizliğin görsel dili)

/// Bir sayının ne kadar güvenilir olduğunu tutarlı biçimde ifade eder.
/// Aynı dilbilgisi her yerde geçerli: TDEE güveni, korelasyonda n<10,
/// veri eksik guardrail kuralı, tahmini varış tarihi.
enum ConfidenceLevel {
    /// Yüksek güven: tam ağırlık, düz alt çizgi (veya çizgisiz).
    case high
    /// Orta güven: normal ağırlık, işaret yok.
    case medium
    /// Düşük güven: ince ağırlık + kesikli alt çizgi.
    case low

    var fontWeight: Font.Weight {
        switch self {
        case .high:   return .bold
        case .medium: return .semibold
        case .low:    return .light
        }
    }

    var isDashed: Bool { self == .low }

    /// Türkçe kısa etiket ("Güven: düşük" gibi kullanım için)
    var label: String {
        switch self {
        case .high:   return "yüksek"
        case .medium: return "orta"
        case .low:    return "düşük"
        }
    }
}

// MARK: - Tipografi rolleri

extension DS {
    /// Tipografi rolleri. Sayılarda .rounded + monospacedDigit —
    /// değer değişirken zıplamasın. Dynamic Type ile ölçeklenir;
    /// sabit .system(size:) KULLANMA.
    enum Font {
        /// Büyük sayı (BigStat) — rounded, monospaced digits
        static func bigStat(weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(.largeTitle, design: .rounded, weight: weight).monospacedDigit()
        }
        /// Orta boy sayı (kart içi değer)
        static func stat(weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(.title2, design: .rounded, weight: weight).monospacedDigit()
        }
        /// Başlık
        static let heading: SwiftUI.Font = .system(.headline, design: .default)
        /// Bölüm başlığı
        static let sectionHeader: SwiftUI.Font = .system(.subheadline, design: .default, weight: .semibold)
        /// Gövde
        static let body: SwiftUI.Font = .system(.body, design: .default)
        /// İkincil
        static let secondary: SwiftUI.Font = .system(.subheadline, design: .default)
        /// Etiket / dipnot
        static let caption: SwiftUI.Font = .system(.caption, design: .default)
        /// Zaman / küçük sayısal etiket — monospaced digits
        static let numericCaption: SwiftUI.Font = .system(.subheadline, design: .rounded, weight: .medium).monospacedDigit()
    }
}

// MARK: - Türkçe yerel ayar yardımcıları

extension DS {
    /// Türkçe yerel ayar — sayı ve tarih biçimlendirmesinin tek kaynağı.
    static let locale = Locale(identifier: "tr_TR")

    /// Ondalık virgüllü sayı biçimlendirme: 82,4
    static func decimal(_ value: Double, fraction: Int = 1) -> String {
        value.formatted(
            .number.precision(.fractionLength(fraction)).locale(locale)
        )
    }

    /// Tam sayı, binlik ayraçlı: 2.410
    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(locale))
    }

    /// Yüzde: %64 (Türkçe'de işaret önde)
    static func percent(_ value: Int) -> String { "%\(integer(value))" }

    /// Kısa tarih: "12 Eylül"
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(locale))
    }

    /// Türkçe büyük harf dönüşümü — İ/ı bozulmasın.
    static func uppercased(_ text: String) -> String {
        text.uppercased(with: locale)
    }
}

// MARK: - Color yardımcıları

extension Color {
    /// Hex tabanlı adaptive renk. Asset katalog kullanmadan
    /// light/dark varyantı tek satırda tanımlar.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue:  CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Kart kabuğu (içerik katmanı — cam efekti YOK)

/// Standart kart kabuğu. İçerik katmanıdır; .glassEffect uygulanmaz.
struct CardSurface: ViewModifier {
    var padding: CGFloat = DS.Space.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Surface.divider, lineWidth: 0.5)
            )
    }
}

extension View {
    /// Kart kabuğu uygula. İçerik kartlarının tek arka plan kaynağı.
    func cardSurface(padding: CGFloat = DS.Space.lg) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

// MARK: - Previews

#Preview("Renk kanalları — Light") {
    DSPreviewPalette()
}

#Preview("Renk kanalları — Dark") {
    DSPreviewPalette()
        .preferredColorScheme(.dark)
}

private struct DSPreviewPalette: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Text("Kimlik — düşük doygunluk")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Text.secondary)
                HStack(spacing: DS.Space.sm) {
                    ForEach(IdentityColor.allCases, id: \.self) { identity in
                        VStack(spacing: DS.Space.xs) {
                            Circle().fill(identity.color).frame(width: 32, height: 32)
                            Text(identity.displayName)
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Text.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                }

                Text("Durum — yüksek doygunluk, nadir")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Text.secondary)
                HStack(spacing: DS.Space.lg) {
                    statusSwatch("Kritik", DS.Status.critical)
                    statusSwatch("Dikkat", DS.Status.attention)
                    statusSwatch("Olumlu", DS.Status.positive)
                    statusSwatch("Bilgi", DS.Status.info)
                    statusSwatch("Nötr", DS.Status.neutral)
                }

                Text("Örnek kart")
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(DS.Text.secondary)
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    Text("Kart başlığı")
                        .font(DS.Font.heading)
                        .foregroundStyle(DS.Text.primary)
                    Text("İkincil açıklama metni burada yer alır.")
                        .font(DS.Font.secondary)
                        .foregroundStyle(DS.Text.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
            .padding(DS.Space.lg)
        }
        .background(DS.Surface.background)
    }

    private func statusSwatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: DS.Space.xs) {
            Circle().fill(color).frame(width: 32, height: 32)
            Text(name)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.tertiary)
        }
    }
}

// MARK: - Motor güveni → tasarım güven dilbilgisi
extension Confidence {
    /// Deterministik motorun güven derecesi, tasarımın tipografik güven diline çevrilir.
    var designLevel: ConfidenceLevel {
        switch self {
        case .high:   return .high
        case .medium: return .medium
        case .low:    return .low
        }
    }
}
