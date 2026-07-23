//
//  WorkoutSessionView.swift
//  SaglikDashboard
//
//  "Antrenman Seansı" ekranı — tasarım görseli 06 karşılığı.
//  Hız öncelikli form: tek elle kullanılabilir büyük ±stepper'lar,
//  "Seti Kaydet" (ne yapacağını söyleyen buton), önceki setler listesi.
//  Cam efekti YALNIZCA alttaki yüzen dinlenme sayacı çubuğunda —
//  içerik kartlarında asla.
//

import SwiftUI

// MARK: - Sunum modelleri

struct WorkoutSet: Identifiable {
    let id = UUID()
    let index: Int
    let weightKg: Double
    let reps: Int
}

// MARK: - WorkoutSessionView

struct WorkoutSessionView: View {
    let exerciseName: String
    let targetDescription: String

    @State private var weightKg: Double = 60
    @State private var reps: Int = 8
    @State private var completedSets: [WorkoutSet] = [
        .init(index: 1, weightKg: 60, reps: 8),
        .init(index: 2, weightKg: 60, reps: 8),
    ]
    @State private var restRemaining: Int? = 78   // saniye; nil → sayaç gizli
    @Environment(\.dismiss) private var dismiss

    private let restTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.lg) {
                exerciseHeader
                inputCard
                saveButton
                completedList
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, 120)   // yüzen çubuk için alan
        }
        .background(DS.Surface.background)
        .navigationTitle("Kuvvet — Alt Vücut")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Seansı bitir") { dismiss() }
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Surface.accent)
            }
        }
        .safeAreaInset(edge: .bottom) { restBar }
        .onReceive(restTimer) { _ in
            guard let r = restRemaining, r > 0 else { return }
            restRemaining = r - 1
        }
    }

    // MARK: Egzersiz başlığı

    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: IdentityColor.workout.symbolName)
                    .foregroundStyle(IdentityColor.workout.color)
                Text(exerciseName)
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Text.primary)
                Spacer()
                IdentityChip(text: "Set \(completedSets.count + 1) / 4", identity: .workout)
            }
            Text(targetDescription)
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: Giriş kartı — büyük stepper'lar

    private var inputCard: some View {
        VStack(spacing: DS.Space.lg) {
            BigStepper(
                label: "Ağırlık",
                valueText: "\(DS.decimal(weightKg, fraction: weightKg.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) kg",
                onDecrement: { weightKg = max(0, weightKg - 2.5) },
                onIncrement: { weightKg += 2.5 }
            )
            Divider().overlay(DS.Surface.divider)
            BigStepper(
                label: "Tekrar",
                valueText: DS.integer(reps),
                onDecrement: { reps = max(1, reps - 1) },
                onIncrement: { reps += 1 }
            )
        }
        .cardSurface()
    }

    /// Ne yapacağını söyleyen birincil buton: "Kaydet" değil, "Seti Kaydet".
    private var saveButton: some View {
        Button {
            saveSet()
        } label: {
            Text("Seti Kaydet")
                .font(DS.Font.heading)
                .frame(maxWidth: .infinity, minHeight: DS.Touch.comfortable)
        }
        .buttonStyle(.borderedProminent)
        .tint(DS.Surface.accent)
    }

    private func saveSet() {
        // Onay sakindir: hafif haptik, konfeti yok.
        withAnimation(.easeInOut(duration: 0.15)) {
            completedSets.append(
                WorkoutSet(index: completedSets.count + 1, weightKg: weightKg, reps: reps)
            )
            restRemaining = 90
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Tamamlanan setler

    private var completedList: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Tamamlanan setler")
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Text.primary)

            if completedSets.isEmpty {
                Text("Henüz set kaydedilmedi. İlk seti yukarıdan kaydet.")
                    .font(DS.Font.secondary)
                    .foregroundStyle(DS.Text.tertiary)
            } else {
                ForEach(completedSets) { set in
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.Surface.accent)
                        Text("Set \(DS.integer(set.index))")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Text.primary)
                        Spacer()
                        Text("\(DS.decimal(set.weightKg, fraction: set.weightKg.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) kg × \(DS.integer(set.reps))")
                            .font(DS.Font.numericCaption)
                            .foregroundStyle(DS.Text.secondary)
                    }
                    .padding(.vertical, DS.Space.sm)
                    if set.id != completedSets.last?.id {
                        Divider().overlay(DS.Surface.divider)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: Dinlenme sayacı — cam efekti SADECE burada (işlevsel katman)

    @ViewBuilder
    private var restBar: some View {
        if let remaining = restRemaining, remaining > 0 {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "timer")
                    .foregroundStyle(DS.Surface.accent)
                Text("Dinlenme: \(formattedRest(remaining))")
                    .font(DS.Font.numericCaption)
                    .foregroundStyle(DS.Text.primary)
                    .monospacedDigit()
                Spacer()
                Button("+30 sn") { restRemaining = remaining + 30 }
                    .font(DS.Font.caption)
                    .buttonStyle(.bordered)
                    .tint(DS.Surface.accent)
                Button("Atla") { restRemaining = nil }
                    .font(DS.Font.caption)
                    .buttonStyle(.bordered)
                    .tint(DS.Text.secondary)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
            .glassEffect(.regular, in: Capsule())   // iOS 26 Liquid Glass — işlevsel katman
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.sm)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func formattedRest(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - BigStepper

/// Tek elle kullanım için büyük dokunma hedefli ± kontrol.
/// Spor salonunda ter/eldivenle bile isabetli: hedefler 56 pt.
struct BigStepper: View {
    let label: String
    let valueText: String
    var onDecrement: () -> Void
    var onIncrement: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Text.secondary)

            HStack(spacing: DS.Space.lg) {
                stepButton(system: "minus", action: onDecrement)
                    .accessibilityLabel("\(label) azalt")

                Text(valueText)
                    .font(DS.Font.stat(weight: .semibold))
                    .foregroundStyle(DS.Text.primary)
                    .monospacedDigit()
                    .frame(minWidth: 110)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                stepButton(system: "plus", action: onIncrement)
                    .accessibilityLabel("\(label) artır")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title2.weight(.medium))
                .foregroundStyle(DS.Surface.accent)
                .frame(width: DS.Touch.comfortable, height: DS.Touch.comfortable)
                .background(DS.Surface.accent.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Antrenman Seansı — Light") {
    NavigationStack {
        WorkoutSessionView(
            exerciseName: "Bulgarian Split Squat",
            targetDescription: "Hedef: 4 set × 8 tekrar · 60 kg · RPE 7–8"
        )
    }
}

#Preview("Antrenman Seansı — Dark") {
    NavigationStack {
        WorkoutSessionView(
            exerciseName: "Bulgarian Split Squat",
            targetDescription: "Hedef: 4 set × 8 tekrar · 60 kg · RPE 7–8"
        )
    }
    .preferredColorScheme(.dark)
}
