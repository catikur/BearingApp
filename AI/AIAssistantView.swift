import SwiftUI

struct AIAssistantView: View {
    @EnvironmentObject var client: OpenRouterClient
    @EnvironmentObject var config: AIConfig
    @EnvironmentObject var memory: AIMemory
    @EnvironmentObject var plan: PlanStore
    @EnvironmentObject var profileStore: ProfileStore
    @Environment(\.dismiss) var dismiss

    let contextFor: (AITask) -> String

    /// Öneri doğrulaması için motorun TDEE sonucu
    let tdee: TDEEEngine.Result?

    @State private var input = ""
    @State private var showContext = false
    @State private var task: AITask = .chat
    @State private var showProposal = false

    private var suggestions: [String] {
        switch task {
        case .chat: return [
            "Bu haftaki verimi özetle, dikkatimi nereye vermeliyim?",
            "TDEE ve hedef hızım tutarlı mı?",
            "Kurallarımdan hangisi beni en çok geriye çekiyor?",
        ]
        case .nutritionPlan: return [
            "Bu hedeflere uyan bir günlük beslenme planı hazırla.",
            "Mevcut öğün saatlerimi koruyarak plan çıkar.",
            "Şişkinlik tetikleyicilerimden kaçınan bir gün planla.",
        ]
        case .trainingAdjust: return [
            "Haftalık antrenmanımı mevcut günlerimde optimize et.",
            "Toparlanmam düşükse yükü nasıl ayarlamalıyım?",
            "Kuvvet A'yı ekipmanıma göre revize et.",
        ]
        case .planReview: return [
            "Planımın hangi kısmı sürdürülemiyor, neden?",
            "Uyumu artırmak için en küçük iki değişiklik ne olur?",
        ]
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !config.enabled || !config.hasKey {
                    setupNotice
                } else {
                    taskBar
                    messagesList
                    if let e = client.lastError { errorBar(e) }
                    if let e = client.parseError { errorBar("Öneri okunamadı: \(e)") }
                    if client.lastProposal != nil { proposalBar }
                    inputBar
                }
            }
            .navigationTitle("Yorum Asistanı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showContext = true } label: { Label("Gönderilen bağlamı gör", systemImage: "doc.text.magnifyingglass") }
                        Button(role: .destructive) { client.clear() } label: { Label("Sohbeti temizle", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } }
            }
            .sheet(isPresented: $showContext) { ContextPreview(text: contextFor(task)) }
            .sheet(isPresented: $showProposal) {
                if let p = client.lastProposal {
                    ProposalReviewView(proposal: p, raw: client.lastRawProposal, tdee: tdee)
                        .environmentObject(plan)
                        .environmentObject(profileStore)
                }
            }
        }
    }

    private var setupNotice: some View {
        ContentUnavailableView {
            Label("Yapay zekâ kapalı", systemImage: "sparkles")
        } description: {
            Text("Ayarlar → Yapay Zekâ bölümünden OpenRouter anahtarını ekleyip katmanı aç. Uygulama bu katman olmadan da tam çalışır.")
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    if client.messages.isEmpty { emptyState }
                    ForEach(client.messages) { m in bubble(m) }
                    if client.sending {
                        HStack(spacing: DS.Space.sm) {
                            ProgressView()
                            Text(client.messages.last?.role == "assistant" && !(client.messages.last?.content.isEmpty ?? true)
                                 ? "Akıyor… (durdurabilirsin)" : "Yanıtlıyor…")
                                .font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(DS.Space.lg)
            }
            .background(DS.Surface.background)
            .onChange(of: client.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Bu asistan hesap yapmaz. Uygulamanın hesapladığı sayıları okur ve yorumlar.")
                .font(DS.Font.caption).foregroundStyle(DS.Text.secondary)
            ForEach(suggestions, id: \.self) { s in
                Button { send(s) } label: {
                    HStack {
                        Text(s).font(DS.Font.secondary).foregroundStyle(DS.Text.primary).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.circle").foregroundStyle(DS.Text.tertiary)
                    }
                    .padding(DS.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(DS.Surface.divider, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        let isUser = m.role == "user"
        return VStack(alignment: isUser ? .trailing : .leading, spacing: DS.Space.xs) {
            Text(m.content)
                .font(DS.Font.secondary)
                .foregroundStyle(DS.Text.primary)
                .padding(DS.Space.md)
                .background(isUser ? DS.Surface.accent.opacity(0.15) : DS.Surface.card,
                            in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser {
                Button {
                    memory.add(m.content.prefix(280).description)
                } label: {
                    Label("Hafızaya kaydet", systemImage: "brain").font(DS.Font.caption)
                }
                .buttonStyle(.plain).foregroundStyle(DS.Text.secondary)
            }
        }
    }

    private func errorBar(_ e: String) -> some View {
        Text(e).font(DS.Font.caption).foregroundStyle(DS.Status.critical)
            .padding(DS.Space.md).frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Status.critical.opacity(0.08))
    }

    private var inputBar: some View {
        HStack(spacing: DS.Space.sm) {
            TextField("Sorunu yaz…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            if client.sending {
                // Akış her an durdurulabilir (§8.3); kısmi yanıt ekranda kalır
                Button { client.cancel() } label: {
                    Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(DS.Status.attention)
                }
                .accessibilityLabel("Yanıtı durdur")
            } else {
                Button { send(input) } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(DS.Surface.accent)
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Gönder")
            }
        }
        .padding(DS.Space.md)
        .background(.bar)
    }

    private var taskBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.sm) {
                ForEach(AITask.allCases) { t in
                    Button { task = t } label: {
                        Label(t.label, systemImage: t.icon)
                            .font(DS.Font.caption)
                            .padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.sm)
                            .background(task == t ? DS.Surface.accent.opacity(0.18) : DS.Surface.card,
                                        in: Capsule())
                            .foregroundStyle(task == t ? DS.Surface.accent : DS.Text.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.sm)
        }
        .background(.bar)
    }

    private var proposalBar: some View {
        Button { showProposal = true } label: {
            HStack {
                Image(systemName: "doc.badge.gearshape")
                Text("Öneri hazır — incele ve seçerek uygula").font(DS.Font.caption.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(DS.Font.caption)
            }
            .foregroundStyle(DS.Status.positive)
            .padding(DS.Space.md)
            .background(DS.Status.positive.opacity(0.12))
        }
        .buttonStyle(.plain)
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        input = ""
        Task { await client.send(t, context: contextFor(task), config: config, memory: memory, task: task) }
    }
}

/// Modele gönderilen deterministik bağlamın birebir önizlemesi
struct ContextPreview: View {
    let text: String
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Gönderilen Bağlam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }
}
