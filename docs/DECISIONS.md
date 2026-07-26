# Project Decisions: Bearing

> Aşama 0 karar matrisi — **geriye dönük** dolduruldu (proje anayasadan önce başladı; denetim: `docs/DENETIM-2026-07-26.md`). Anayasadan sapmalar `docs/adr/` altında ADR ister.

| Decision | Choice | Rationale | Date |
|---|---|---|---|
| D1 Design track | **B (Code-First)** | Solo + AI ajanları; kod içi `Shared/DesignSystem.swift` + `DESIGN.md` tek kaynak; Figma yok. Fiilî durumla uyumlu. | 2026-07-26 |
| D2 Monetization | **none (şimdilik)** | Kişisel araç; gelir modeli yok. **Yeniden değerlendirme tetikleyicisi:** TestFlight/Store kararı alınırsa fiyat hipotezi + paywall vertical slice kapsamına girer. | 2026-07-26 |
| D3 Backend tier | **K0 (local-only)** + sapma | Veri cihazda (HealthKit + UserDefaults + Keychain); sunucu yok. **Sapma:** bulut AI, K2 proxy'siz doğrudan çağrılıyor → `adr/0001`. CloudKit ihtimali düşük; doğarsa şema sync-uyumluluğu ADR ile ele alınır. | 2026-07-26 |
| D4 Platforms | **iPhone-only** | `TARGETED_DEVICE_FAMILY = 1`; core loop telefon bağlamı. iPad/macOS gündemde değil. | 2026-07-26 |
| D5 AI features | **yes — cloud (OpenRouter)** | Deterministik motor çıktısını yorumlama + plan önerisi; sayı üretimi yasak (mimari kural). Model: kullanıcı seçimli (varsayılan liste `AIConfig.presetModels`). On-device Foundation Models değerlendirilmedi → backlog. Bölüm 8 eksikleri: golden set/eval, maliyet tavanı, prompt versiyonlama → `DENETIM` backlog. | 2026-07-26 |
| D6 Mode | **solo + AI ajanları (hafif mod)** | Tek geliştirici; kod ajanı Claude Code + Xcode içi Claude (küçük işler). Kapı/kanıt disiplini bu denetimle başlatıldı. | 2026-07-26 |

Deviations from the constitution require an ADR in `docs/adr/`.

## Ürün ufku

Kalıcı kişisel araç olarak doğdu; **Store ihtimali açık** (kullanıcı kararı, 2026-07-26). Bu yüzden store-önkoşulları (PrivacyInfo.xcprivacy, entitlement daraltma, telemetri, ikon, monetizasyon kararı) N/A değil, `DENETIM` backlog'unda tetikleyiciye bağlı maddelerdir.
