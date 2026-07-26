# CLAUDE.md — Claude Code Çalışma Talimatları

Bu bir **SwiftUI + HealthKit + Whoop API** kişisel iOS sağlık dashboard'u. Proje bağlamı için `PROJECT_SPEC.md`'yi oku.

> **Önce oku:** `docs/DECISIONS.md` (D1–D6 kararları + sapma ADR'leri) ve güncel denetim `docs/DENETIM-2026-07-26.md`. Kalıcı kararlar aynı gün repo'ya işlenir (ADR/docs) — sohbet bellek değildir.

## Kurulum / Build

- Bu dosyalar bir Xcode projesine eklenmeli (henüz `.xcodeproj` yok — kullanıcı Xcode'da "iOS App / SwiftUI" projesi oluşturup bu dosyaları ekleyecek, VEYA sen bir Xcode projesi/Swift Package iskeleti oluştur).
- **Deployment target: iOS 17+** (Swift Charts + modern HealthKit API'leri için).
- **Capabilities:** HealthKit (Signing & Capabilities → + HealthKit).
- **Info.plist:** `NSHealthShareUsageDescription` zorunlu.
- **URL Type:** Whoop redirect için custom scheme `bearing` (Info → URL Types).
- **Secrets:** Repo'da ve binary'de sır YOK. Whoop client ID/secret ve OpenRouter anahtarı Keychain'de tutulur, uygulama içinden girilir (Ayarlar → Veri kaynakları / Yapay Zekâ). Koda sır gömme; `Secrets.swift` kalıbı kaldırıldı (docs/adr/0002).
- **HealthKit gerçek iPhone gerektirir** — simülatörde veri yoktur. Build'i gerçek cihaz hedefiyle doğrula.

## Dosya haritası

```
Shared/DesignSystem.swift        TASARIM SİSTEMİ: DS token'ları (renk/boşluk/tipografi), kimlik+durum kanalları, ConfidenceLevel
Shared/DesignComponents.swift    bileşen kütüphanesi: EngineCard/BigStat/ThinBar/MetricCard/PlanTimelineRow/BigStepper/…
Shared/Models.swift              MetricDef, MetricSample, enum'lar
HealthKit/HealthMetricCatalog    71 HealthKit metriği + 24 Whoop metriği (katalog)
HealthKit/HealthKitManager       yetki + HKStatisticsCollectionQuery + uyku
Whoop/WhoopModels                v2 Codable modeller
Whoop/WhoopAuth                  OAuth2 + PKCE + Keychain + rotating refresh
Whoop/WhoopAPI                   REST client + WhoopStore (MetricSample'a dönüştürür)
Config/DashboardConfig           kullanıcının seçtiği metrikler (UserDefaults)
Config/LabelStore                YEREL ETİKETLEME: günlük etiket+not (UserDefaults)
Shared/DayLabel                  etiket modeli + TagCatalog (alkol/serbest öğün/oruç…)
Shared/Correlation               KORELASYON: Pearson/regresyon + otomatik örüntü tarama
(Secrets dosyası YOK — Whoop/OpenRouter kimlik bilgileri Keychain'de, uygulama içinden girilir)
App/BearingApp                   app girişi + DataStore (HealthKit+Whoop birleştirir)
Dashboard/DashboardView          ana ekran
Dashboard/MetricCard             kart + InsightCard
Dashboard/MetricDetailView       detay (trend + istatistik)
Dashboard/MetricPickerView       ÖZELLEŞTİRME: metrik ekle/çıkar/sırala
Dashboard/DayLabelSheet          YEREL ETİKETLEME: günü etiketle (chip'ler + not)
Dashboard/CorrelationView        KORELASYON KEŞFİ: elle çift + otomatik tarama
Shared/Profile                   PARAMETRİK: kullanıcı profili + tüm motor ayarları
Shared/Rules                     PARAMETRİK: kullanıcı tanımlı guardrail kuralları
Shared/Engines                   DETERMİNİSTİK MOTORLAR: TDEE, trend, baseline, guardrail
Config/ProfileStore              profil + ayarlar + kurallar kalıcılığı
Dashboard/EngineCards            motor özet kartları (EngineCard/BigStat/ThinBar)
Dashboard/TDEEDetailView         adaptif TDEE detayı
Dashboard/WeightJourneyView      kilo trendi (EMA) + hedefe varış
Dashboard/BaselineView           z-skor sapmaları + bileşik sinyal
Dashboard/GuardrailsView         kural kural uyum skoru
Settings/SettingsView            tüm parametrelerin düzenlendiği yer
Settings/RuleEditorView          kural listesi + kural formu
Settings/AISettingsView          OpenRouter ayarları + sistem promptu + hafıza
AI/AIConfig                      Keychain + AI ayarları + hafıza katmanı
AI/OpenRouterClient              LLM istemcisi + deterministik bağlam üretici
AI/AIAssistantView               sohbet ekranı + gönderilen bağlam önizlemesi
Shared/PlanModels                PLAN: kategori, zamanlama, PlanItem, bildirim/faz ayarları
Shared/WorkoutModels             antrenman şablonu, hareket, seans logu
Shared/PlanEngine                DETERMİNİSTİK: occurrence çözümleme, uyum, faz kilidi
Config/PlanStore                 plan + log + şablon kalıcılığı
Notifications/NotificationManager  yerel bildirim kurulumu + aksiyonlar (64 sınırı yönetimi)
App/RootView                     sekmeli kök (Bugün / Panel) + bildirim tazeleme
Plan/TodayView                   günün zaman çizelgesi, tik atma, faz kartı
Plan/PlanEditorView              plan öğesi listesi + formu
Plan/WorkoutSessionView          seans loglama + şablon/hareket düzenleyici
Settings/NotificationSettingsView  izin, sessiz saat, kategori, faz kuralı
Shared/HealthContext             kullanıcı beyanı bağlam (durum, intolerans, ekipman, lab)
AI/AITasks                       görev tanımları + düzenlenebilir talimatlar + JSON şeması
AI/AIProposal                    öneri modeli + toleranslı JSON ayrıştırma + DOĞRULAYICI
AI/ProposalReviewView            öneriyi inceleme, doğrulama uyarıları, seçerek uygulama
Settings/HealthContextView       kişisel bağlam editörü
```

## LLM PLAN ÜRETİMİ — kritik kural
LLM plan önerebilir ama **hiçbir öneri doğrudan uygulanmaz**. Akış:
`LLM → JSON öneri → ProposalValidator (deterministik) → kullanıcı seçimi → PlanStore`.
`ProposalValidator` kalori hedefini motorun `recommendedIntake` değeriyle, makro/mineral
hedeflerini kullanıcının `GuardrailRule`'larıyla, içeriği `HealthContext.avoid` listesiyle
karşılaştırır; ihlalleri `blocker` olarak işaretler. Bu doğrulamayı LLM'e devretme.
Öneriden gelen yeni öğeler `notify: false` ile eklenir.

## BİLDİRİM MİMARİSİ — dikkat
iOS uygulama başına **64 bekleyen bildirim** sınırı koyar. Bu yüzden tekrarlayan trigger
KULLANILMIYOR; `NotificationManager.reschedule` yalnızca `horizonDays` kadar ileriyi kurar ve
uygulama her `.active` olduğunda yeniden doldurulur. `maxScheduled` (varsayılan 60) sınırın
altında pay bırakır. Yeni bildirim tipi eklerken bu yuvarlanan pencere mantığını bozma.

## MİMARİ KURAL — bunu bozma
Hesaplama ve çıkarım **yalnızca** `Shared/Engines.swift` ve `Shared/PlanEngine.swift` içinde, deterministik olarak yapılır.
LLM katmanı (`AI/`) hiçbir sayı üretmez, hesaplamaz, düzeltmez — sadece `AIContext.snapshot`
ile verilen hazır çıktıları yorumlar. Yeni bir metrik/çıkarım eklerken önce motora ekle,
sonra bağlam üreticisine yansıt. Sabit eşik/hedef kodlama; her parametre
`EngineSettings` veya `GuardrailRule` üzerinden kullanıcıya açık olmalı.

## Öncelikli görevler (sırayla, her adımda derlemeyi doğrula)

1. **Derle ve hataları düzelt** (gerçek iPhone hedefi). Muhtemel noktalar: iOS sürümüne özel HealthKit tip adları, `HKUnit(from:)` string'leri, Swift Charts API farkları.
2. **Whoop alan adlarını doğrula:** `WhoopModels` içindeki `score` alt-yapıları canlı v2 yanıtıyla eşleşmeli. Gerçek bir API çağrısı yapıp JSON'u kontrol et; uyuşmazsa modelleri güncelle. Whoop dokümanı: developer.whoop.com. Artık 5 endpoint çekiliyor (recovery, cycle, sleep, **workout**, **body measurement**) ve 24 metriğe genişletildi. Özellikle şu yeni alanları doğrula: workout `sport_name` (v2) vs `sport_id` (v1), workout `zone_duration` alt-alan adları, sleep `stage_summary` içindeki `sleep_cycle_count`/`disturbance_count`, body measurement path'i (`/v2/user/measurement/body`) tekil obje mi sayfalı mı.
3. **Whoop pagination parametresi** (`nextToken` vs `next_token`) canlı API ile doğrula.
4. **Eksik veri durumları:** bir metrik için HealthKit veri döndürmezse kart "—" göstermeli (zaten yapılıyor); kontrol et.

## Sonraki özellikler (kullanıcı isteyince)

- **Widget:** WidgetKit target ekle → bugünkü Recovery + HRV + protein.
- **Cheat günü etiketleme:** HealthKit'te yok → SwiftData veya UserDefaults ile yerel; grafiklerde turuncu nokta (alkol moru gibi).
- **Whoop workout endpoint** (`/v2/activity/workout`) → antrenman yükü.
- **Bildirim:** haftalık özet.
- **CGM (Libre):** ayrı entegrasyon; glukoz-öğün korelasyonu.

## Konvansiyonlar

- Tüm UI metinleri **Türkçe**.
- **Tasarım sistemi:** UI, `Shared/DesignSystem.swift`'teki `DS` token'larını kullanır (serbest boşluk/renk/font yok). Kurallar kök dizindeki `DESIGN.md`'de. Özet: renk iki kanal (kimlik soluk/sık, durum doygun/nadir); kırmızı YALNIZCA bileşik sapma sinyali + engelleyici doğrulama uyarısında; belirsiz sayılar `ConfidenceLevel` dilbilgisiyle (ince+kesikli = düşük güven); içerik kartlarına cam efekti uygulanmaz (`glassEffect` sadece işlevsel katman); sayı/tarih biçimlendirme `DS.decimal/integer/percent/shortDate`.
- `@MainActor` sınıflar; async/await; `withCheckedContinuation` HealthKit sorgularında.
- Yeni metrik eklemek = sadece `HealthMetricCatalog.all`'a bir satır (katalog-güdümlü mimari; UI otomatik yansır).
- Gizlilik: veri cihazdan çıkmaz. Whoop token yalnız Keychain'de.

## Test

- **Otomatik testler:** `Tests/EngineTests.swift` (Swift Testing, 26 test) motorları sınar. Koş: `xcodebuild test -project Bearing.xcodeproj -scheme Bearing -destination 'platform=iOS Simulator,name=Bearing Test iPhone'`. Motor davranışı değişen her PR test günceller.
- **AI eval:** prompt/model değişikliği = `python3 docs/prompts/eval.py --offline --sync-check` yeşil + canlı koşu (README'deki komut). Güvenlik kategorilerinde 0 tolerans.
- Gerçek iPhone'da çalıştır, HealthKit iznini ver, Whoop'a bağlan.
- Cronometer/Whoop/tartının Apple Health'e bağlı olduğunu doğrula (veri yoksa app boş görünür — kaynak sorunu, kod değil).
