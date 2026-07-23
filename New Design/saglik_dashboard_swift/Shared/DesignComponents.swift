//
//  DesignComponents.swift
//  SaglikDashboard
//
//  FAZ 1 — Bileşen kütüphanesi.
//  Kart kabuğu, büyük istatistik, ilerleme çubuğu, chip/rozet, boş durum,
//  bölüm başlığı, liste satırı, güven göstergesi.
//
//  Mevcut EngineCard / BigStat / ThinBar API'leri korunarak buraya taşındı;
//  çağıran ekranlar değişiklik gerektirmez.
//

import SwiftUI

// MARK: - ConfidenceText (imza öğesi)

/// Belirsizliğin görsel dili — sayı ne kadar güvenilir?
/// Düşük güven: ince ağırlık + kesikli alt çizgi.
/// Yüksek güven: tam ağırlık + düz ince alt çizgi (isteğe bağlı).
///
/// Aynı dilbilgisi her yerde: TDEE, korelasyon n<10, eksik veri, tahmini tarih.
struct ConfidenceText: View {
    let text: String
    let confidence: ConfidenceLevel
    var font: Font = DS.Font.bigStat()
    var showsUnderline: Bool = true
    var color: Color = DS.Text.primary

    var body: some View {
        Text(text)
            .font(font)
            .fontWeight(confidence.fontWeight)
            .foregroundStyle(confidence == .low ? DS.Text.secondary : color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .overlay(alignment: .bottom) {
                if showsUnderline {
                    ConfidenceUnderline(isDashed: confidence.isDashed)
                        .offset(y: DS.Space.xs)
                }
            }
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        "\(text), güven seviyesi \(confidence.label)"
    }
}

/// Güven alt çizgisi: kesikli (düşük) veya düz (yüksek).
struct ConfidenceUnderline: View {
    let isDashed: Bool

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(
                DS.Text.tertiary,
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: .round,
                    dash: isDashed ? [5, 5] : []
                )
            )
        }
        .frame(height: 1.5)
    }
}

/// Küçük güven etiketi: "Güven: düşük · 9 günlük veri"
struct ConfidenceCaption: View {
    let confidence: ConfidenceLevel
    var detail: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Text("Güven: \(confidence.label)")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.xs)
                .background(DS.Surface.divider.opacity(0.6), in: Capsule())
            if let detail {
                Text("· \(detail)")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
            }
        }
    }
}

// MARK: - EngineCard (mevcut API korunarak taşındı)

/// Motor özet kartı kabuğu: ikon + başlık + rozet + içerik alanı.
/// İçerik katmanı — cam efekti uygulanmaz.
struct EngineCard<Content: View, Badge: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var badge: Badge
    @ViewBuilder var content: Content

    init(
        icon: String,
        title: String,
        @ViewBuilder badge: () -> Badge = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.badge = badge()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: icon)
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Surface.accent)
                Text(title)
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: DS.Space.sm)
                badge
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - BigStat (mevcut API korunarak taşındı)

/// Büyük değer + birim + alt açıklama. Güven seviyesi tipografik olarak ifade edilir.
struct BigStat: View {
    let value: String
    let unit: String
    var caption: String? = nil
    var confidence: ConfidenceLevel = .high

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                ConfidenceText(
                    text: value,
                    confidence: confidence,
                    font: DS.Font.bigStat(weight: confidence.fontWeight)
                )
                Text(unit)
                    .font(DS.Font.stat(weight: .regular))
                    .foregroundStyle(DS.Text.secondary)
            }
            if let caption {
                Text(caption)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - ThinBar (mevcut API korunarak taşındı)

/// İnce ilerleme çubuğu. Rutin ilerleme nötr/teal görünür — kırmızı YOK.
struct ThinBar: View {
    /// 0...1
    let progress: Double
    var tint: Color = DS.Surface.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.Surface.divider)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geo.size.width * progress.clamped01))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((progress.clamped01 * 100).rounded())) yüzde")
    }
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}

// MARK: - Chip / Rozet

/// Kimlik chip'i: kategori/etiket için soluk, sakin rozet.
struct IdentityChip: View {
    let text: String
    let identity: IdentityColor

    var body: some View {
        Text(text)
            .font(DS.Font.caption)
            .foregroundStyle(identity.color)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .background(identity.color.opacity(0.14), in: Capsule())
    }
}

/// Durum chip'i: nadir kullanılan, anlam taşıyan rozet.
struct StatusChip: View {
    let text: String
    var status: Color = DS.Status.neutral

    var body: some View {
        Text(text)
            .font(DS.Font.caption)
            .foregroundStyle(status)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .background(status.opacity(0.12), in: Capsule())
    }
}

// MARK: - Bölüm başlığı

/// Bölüm başlığı + isteğe bağlı sağ aksiyon. Buton ne yapacağını yazar.
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Text.primary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Surface.accent)
            }
        }
        .padding(.horizontal, DS.Space.xs)
    }
}

// MARK: - Boş durum

/// Boş durum: yön gösterir, ruh hali yansıtmaz. Tüm ekranlarda tek biçim.
struct EmptyStateView: View {
    let icon: String
    let title: String
    /// Ne olduğunu ve ne yapılacağını söyler; özür dilemez.
    let guidance: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(DS.Text.tertiary)
            Text(title)
                .font(DS.Font.heading)
                .foregroundStyle(DS.Text.primary)
            Text(guidance)
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .tint(DS.Surface.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Space.xxl)
    }
}

// MARK: - Liste satırı (plan zaman çizelgesi)

/// Plan öğesi durumu. Kaçırılan öğe utandırmaz: soluk ve sessiz, kırmızı ✗ yok.
enum PlanItemState {
    case upcoming
    case done
    case skipped
}

/// Zaman çizelgesi satırı: kategori renk şeridi + saat + ikon + başlık + durum.
/// Tek dokunuşla işaretleme `onToggle` ile yapılır.
struct PlanTimelineRow: View {
    let time: String
    let title: String
    let identity: IdentityColor
    let state: PlanItemState
    var accessory: (() -> AnyView)? = nil
    var onToggle: () -> Void = {}

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: DS.Space.md) {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(identity.color)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)

                Text(time)
                    .font(DS.Font.numericCaption)
                    .foregroundStyle(DS.Text.secondary)

                Image(systemName: identity.symbolName)
                    .font(DS.Font.secondary)
                    .foregroundStyle(identity.color)
                    .frame(width: DS.Space.xl)

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(title)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Text.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                    if let accessory {
                        accessory()
                    }
                }

                Spacer(minLength: DS.Space.sm)

                stateIndicator
            }
            .padding(.vertical, DS.Space.md)
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: DS.Touch.minTarget)
            .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .opacity(state == .skipped ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(time), \(title), \(stateAccessibilityLabel)")
        .accessibilityHint("İşaretlemek için dokun")
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .upcoming:
            Circle()
                .strokeBorder(DS.Surface.divider, lineWidth: 2)
                .frame(width: 26, height: 26)
        case .done:
            // Onay, kutlama değil: sakin teal, konfeti yok.
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(DS.Surface.accent)
        case .skipped:
            // Soluk ve sessiz — kırmızı ✗ değil.
            Image(systemName: "minus.circle.fill")
                .font(.title3)
                .foregroundStyle(DS.Text.tertiary)
        }
    }

    private var stateAccessibilityLabel: String {
        switch state {
        case .upcoming: return "bekliyor"
        case .done:     return "yapıldı"
        case .skipped:  return "atlandı"
        }
    }
}

// MARK: - MetricCard (mevcut API korunarak taşındı)

/// Izgara metrik kartı: ad + değer + birim + mini eğri. Nötr, durum rengi yok.
struct MetricCard: View {
    let name: String
    let value: String
    let unit: String
    var sparkline: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(name)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(value)
                    .font(DS.Font.stat())
                    .foregroundStyle(DS.Text.primary)
                Text(unit)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
            }
            if !sparkline.isEmpty {
                SparklineView(values: sparkline)
                    .frame(height: 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: DS.Space.md)
    }
}

/// Mini eğri — dekoratif değil, eğilim bilgisi taşır.
struct SparklineView: View {
    let values: [Double]
    var tint: Color = DS.Surface.accent

    var body: some View {
        GeometryReader { geo in
            if values.count > 1,
               let minV = values.min(), let maxV = values.max() {
                let range = max(maxV - minV, 0.0001)
                Path { path in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((v - minV) / range))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Bileşenler — Light") {
    ComponentGallery()
}

#Preview("Bileşenler — Dark") {
    ComponentGallery()
        .preferredColorScheme(.dark)
}

private struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.lg) {
                EngineCard(icon: "flame", title: "Ölçülmüş Metabolizma", badge: {
                    StatusChip(text: "nötr")
                }) {
                    BigStat(value: "2.410", unit: "kcal",
                            caption: "9 günlük veri", confidence: .low)
                    ConfidenceCaption(confidence: .low, detail: "9 günlük veri")
                }

                EngineCard(icon: "scalemass", title: "Kilo Yolculuğu") {
                    BigStat(value: "82,4", unit: "kg",
                            caption: "−0,35 kg/hafta · hedefe %64", confidence: .high)
                    ThinBar(progress: 0.64)
                }

                PlanTimelineRow(time: "09:15", title: "Boyun mobilite rutini",
                                identity: .neckTMJ, state: .skipped)
                PlanTimelineRow(time: "12:30", title: "Öğle yemeği",
                                identity: .meal, state: .done)
                PlanTimelineRow(time: "18:00", title: "Kuvvet antrenmanı — Alt vücut",
                                identity: .workout, state: .upcoming)

                HStack(spacing: DS.Space.md) {
                    MetricCard(name: "HRV", value: "48", unit: "ms",
                               sparkline: [44, 47, 43, 50, 46, 52, 48])
                    MetricCard(name: "Dinlenik Nabız", value: "56", unit: "atım/dk",
                               sparkline: [58, 57, 58, 56, 55, 57, 56])
                }

                EmptyStateView(
                    icon: "chart.dots.scatter",
                    title: "Henüz korelasyon yok",
                    guidance: "En az 10 günlük veri toplandığında otomatik tarama burada görünür.",
                    actionTitle: "Veri kaynaklarını aç",
                    action: {}
                )
                .cardSurface()
            }
            .padding(DS.Space.lg)
        }
        .background(DS.Surface.background)
    }
}
