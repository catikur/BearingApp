import SwiftUI

/// Bir günün etiketlerini ve serbest notunu düzenleme sayfası.
struct DayLabelSheet: View {
    @EnvironmentObject var labels: LabelStore
    @Environment(\.dismiss) var dismiss
    @State var date: Date
    @State private var note: String = ""

    private let chipCols = [GridItem(.adaptive(minimum: 110), spacing: DS.Space.sm)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    DatePicker("Gün", selection: $date, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(DS.Surface.accent)

                    Text("Etiketler")
                        .font(DS.Font.heading)
                        .foregroundStyle(DS.Text.primary)
                    LazyVGrid(columns: chipCols, spacing: DS.Space.sm) {
                        ForEach(TagCatalog.all) { tag in
                            let on = labels.tags(for: date).contains(tag.id)
                            Button {
                                labels.toggleTag(tag.id, for: date)
                            } label: {
                                HStack(spacing: DS.Space.xs) {
                                    Text(tag.emoji)
                                    Text(tag.title)
                                        .font(DS.Font.secondary)
                                        .foregroundStyle(DS.Text.primary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, DS.Space.sm).padding(.horizontal, DS.Space.md)
                                .frame(maxWidth: .infinity)
                                .background(on ? tag.color.opacity(0.22) : DS.Surface.card)
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                    .stroke(on ? tag.color : DS.Surface.divider, lineWidth: on ? 1.5 : 0.5))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Not")
                        .font(DS.Font.heading)
                        .foregroundStyle(DS.Text.primary)
                    TextField("Örn. 2 kadeh şarap, geç yattım…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: note) { _, v in labels.setNote(v, for: date) }

                    if labels.hasAny(date) {
                        Button("Bu günün etiketlerini temizle", role: .destructive) {
                            labels.clear(date); note = ""
                        }
                        .padding(.top, DS.Space.sm)
                    }

                    Text("Etiketler grafiklerde işaretçi olarak görünür ve içgörü hesaplarına katılır (ör. alkol → HRV). Veri cihazında kalır.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Text.secondary)
                        .padding(.top, DS.Space.xs)
                }
                .padding(DS.Space.lg)
            }
            .background(DS.Surface.background)
            .navigationTitle("Günü Etiketle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
            .onAppear { note = labels.label(for: date)?.note ?? "" }
            .onChange(of: date) { _, d in note = labels.label(for: d)?.note ?? "" }
        }
    }
}
