//
//  TodayView.swift
//  SaglikDashboard
//
//  "Bugün" ekranı — tasarım görseli 01 (light) / 05 (dark) karşılığı.
//  Öncelik: 3 saniyede okunabilirlik, tek dokunuşla işaretleme.
//
//  Not: Veriler PlanEngine'den gelir; bu dosya yalnızca sunum katmanıdır.
//  Örnek model (TodayPlanItem) gerçek PlanModels tipleriyle değiştirilebilir.
//

import SwiftUI

// MARK: - Sunum modeli (PlanEngine çıktısına bağlanır)

struct TodayPlanItem: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let identity: IdentityColor
    var state: PlanItemState
    /// Antrenman gibi seans başlatılabilen öğeler için
    var sessionAction: Bool = false
}

// MARK: - TodayView

struct TodayView: View {
    @State private var items: [TodayPlanItem] = TodayPlanItem.sample
    @State private var dayOffset = 0

    // Bu değerler PlanEngine'den gelir — burada örnek.
    private let completedCount = 8
    private let totalCount = 13
    private let phaseName = "Keşif"
    private let streakDays = 12

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.lg) {
                    summaryCard
                    timeline
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xxl)
            }
            .background(DS.Surface.background)
            .safeAreaInset(edge: .top) { dayNavigator }
        }
    }

    // MARK: Gün gezinme

    private var dayNavigator: some View {
        HStack {
            Button {
                dayOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: DS.Touch.minTarget, height: DS.Touch.minTarget)
            }
            .accessibilityLabel("Önceki gün")

            Spacer()

            VStack(spacing: 0) {
                Text(dayTitle)
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                Text(daySubtitle)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.secondary)
            }

            Spacer()

            Button {
                dayOffset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: DS.Touch.minTarget, height: DS.Touch.minTarget)
            }
            .disabled(dayOffset >= 0)
            .accessibilityLabel("Sonraki gün")
        }
        .foregroundStyle(DS.Surface.accent)
        .padding(.horizontal, DS.Space.sm)
        .background(DS.Surface.background)
    }

    private var currentDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
    }

    private var dayTitle: String {
        let prefix = dayOffset == 0 ? "Bugün · " : ""
        return prefix + DS.shortDate(currentDate)
    }

    private var daySubtitle: String {
        currentDate.formatted(.dateTime.weekday(.wide).locale(DS.locale))
    }

    // MARK: Günün özeti

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Günün özeti")
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                Spacer()
                StatusChip(text: "Faz: \(phaseName)", status: DS.Status.info)
            }

            ThinBar(progress: Double(completedCount) / Double(max(totalCount, 1)))

            HStack {
                Text("\(DS.integer(completedCount)) / \(DS.integer(totalCount)) tamamlandı")
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Text.secondary)
                    .monospacedDigit()
                Spacer()
                // Seri sayacı: var ama ekranın kahramanı değil — üçüncül ve sessiz.
                Text("Seri: \(DS.integer(streakDays)) gün")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Text.tertiary)
            }
        }
        .cardSurface()
    }

    // MARK: Zaman çizelgesi

    private var timeline: some View {
        VStack(spacing: DS.Space.md) {
            if items.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.plus",
                    title: "Bugün için plan yok",
                    guidance: "Plan düzenleyiciden öğün, suplement veya antrenman ekleyebilirsin.",
                    actionTitle: "Plan düzenleyiciyi aç",
                    action: {}
                )
                .cardSurface()
            } else {
                ForEach($items) { $item in
                    PlanTimelineRow(
                        time: item.time,
                        title: item.title,
                        identity: item.identity,
                        state: item.state,
                        accessory: item.sessionAction ? {
                            AnyView(
                                Button("Seans başlat") {}
                                    .font(DS.Font.caption)
                                    .buttonStyle(.bordered)
                                    .tint(DS.Surface.accent)
                            )
                        } : nil,
                        onToggle: { toggle(&item) }
                    )
                }
            }
        }
    }

    /// Tek dokunuş: bekliyor → yapıldı → atlandı → bekliyor.
    /// Hafif haptik; Reduce Motion'a saygılı, animasyon abartısız.
    private func toggle(_ item: inout TodayPlanItem) {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch item.state {
            case .upcoming: item.state = .done
            case .done:     item.state = .skipped
            case .skipped:  item.state = .upcoming
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Örnek veri (tasarım görseliyle birebir)

extension TodayPlanItem {
    static let sample: [TodayPlanItem] = [
        .init(time: "07:30", title: "Sabah suplementleri", identity: .supplement, state: .done),
        .init(time: "08:00", title: "Kahvaltı — protein ağırlıklı", identity: .meal, state: .done),
        .init(time: "09:15", title: "Boyun mobilite rutini", identity: .neckTMJ, state: .skipped),
        .init(time: "12:30", title: "Öğle yemeği", identity: .meal, state: .done),
        .init(time: "15:00", title: "Gün ışığı molası", identity: .circadian, state: .upcoming),
        .init(time: "18:00", title: "Kuvvet antrenmanı — Alt vücut", identity: .workout, state: .upcoming, sessionAction: true),
        .init(time: "21:30", title: "Magnezyum + gevşeme", identity: .supplement, state: .upcoming),
        .init(time: "22:30", title: "Ekran kısma hatırlatması", identity: .circadian, state: .upcoming),
    ]
}

// MARK: - Previews

#Preview("Bugün — Light") {
    TodayView()
}

#Preview("Bugün — Dark") {
    TodayView()
        .preferredColorScheme(.dark)
}
