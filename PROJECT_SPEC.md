# Sağlık Dashboard — Proje Spesifikasyonu

> Bu doküman, projenin **ne olduğunu ve neden yapıldığını** anlatır (Claude Code için bağlam). Teknik çalışma talimatları `CLAUDE.md`'de.

## Amaç

Kişisel bir iOS sağlık dashboard'u. Kullanıcının üç kaynaktan gelen verisini **tek ekranda** birleştirip görselleştirir ve aralarında **korelasyon** kurar (hiçbir tek uygulamanın vermediği şey):

1. **Whoop** → Recovery, Strain, HRV (RMSSD), dinlenme nabzı, SpO2, cilt sıcaklığı, uyku performansı
2. **Cronometer** → kalori, protein, makrolar, mikrobesinler (Apple Health üzerinden)
3. **Akıllı tartı** → kilo, yağ %, yağsız kütle (Apple Health üzerinden)

## Mimari karar (neden böyle)

- **Apple Health = birleştirme noktası.** Cronometer ve tartı zaten oraya yazıyor; Whoop de yazıyor. Native app HealthKit ile hepsini tek kanaldan okur. Backend/CSV/webhook yok.
- **Whoop'un Recovery% ve Strain skorları HealthKit'te YOK** (standart tip değiller) → onlar için ayrıca Whoop API v2 (OAuth 2.0) entegre edildi.
- **Gizlilik:** Tüm veri cihazda kalır (HealthKit izniyle + Keychain'de Whoop token). Hiçbir sunucuya gitmez.

## Kullanıcı bağlamı (metrik seçimleri neden bunlar)

Kullanıcı 40 yaş erkek, kapsamlı sağlık optimizasyonu yapıyor. Öne çıkan tıbbi hedefler dashboard metriklerini belirledi:

- **Kardiyometabolik (en yüksek öncelik):** insülin direnci + atherojenik lipid profili. Bu yüzden **doymuş yağ, sodyum, kalori, protein** öne çıkarıldı.
- **Vestibüler (Meniere/BPPV):** sodyum takibi önemli (endolenfatik basınç).
- **Mikrobesin eksiklikleri:** iyot, çinko, D vitamini, selenyum, magnezyum — bunlar dashboard'da izlenebilir (Cronometer export ediyorsa).
- **Otonom/toparlanma:** HRV (24 civarı, düşük), dinlenme nabzı, Recovery — antrenman-toparlanma dengesi için.
- **Vücut kompozisyonu:** kilo + yağ % + bel çevresi; hedef kas koruyarak yağ kaybı.

Özel korelasyon: **alkolün HRV'ye etkisi** (kullanıcı haftada 1 alkol alıyor; alkol günü vs alkolsüz gün HRV farkı gösteriliyor). Protein tutturma % ve kilo trendi de öne çıkan içgörüler.

## Özellikler

| Özellik | Durum |
|---|---|
| HealthKit ~90 metrik (aktivite, vücut, kalp, solunum, beslenme makro/mineral/vitamin, uyku, lab) | ✅ v1 |
| Whoop API v2 (Recovery/Strain/HRV/sleep) OAuth + PKCE + rotating refresh token | ✅ v1 |
| **Özelleştirilebilir dashboard** — metrik ekle/çıkar/sırala (kalıcı) | ✅ v1 |
| Metrik kartları + mini trend + detay ekranı (7/30/90 gün) | ✅ v1 |
| Korelasyon içgörüleri (alkol→HRV, protein tutturma, kilo trendi) | ✅ v1 |
| Ana ekran widget'ı | ⏳ v2 |
| Cheat günü etiketleme (yerel) | ⏳ v2 |
| Haftalık özet bildirimi | ⏳ v3 |
| CGM (Libre) glukoz-öğün korelasyonu | ⏳ v3 |

## Veri modeli

- `MetricDef` (Shared/Models.swift): bir metriğin kimliği, birimi, kategorisi, kaynağı, toplama şekli (sum/average/latest/sleepHours/whoop), hedefi.
- `MetricSample`: { date, value } — bir günlük değer.
- `HealthMetricCatalog`: tüm metrik tanımları (kategorilere ayrılmış).
- `DataStore`: HealthKit + Whoop verilerini `[metrikId: [MetricSample]]` olarak birleştirir.
- `DashboardConfig`: kullanıcının seçtiği metrik id'lerini UserDefaults'ta saklar.

## Önemli teknik notlar

- **HealthKit simülatörde çalışmaz** — gerçek iPhone şart.
- **Whoop HRV = RMSSD**, Apple Health HRV = SDNN → farklı metrikler (ikisi de ayrı gösteriliyor: `whoop_hrv` vs `hrv`).
- Whoop **rotating refresh token** kullanır: her refresh yeni refresh token döndürür, eskisi geçersiz olur (WhoopAuth bunu yönetir).
- Bazı HealthKit tipleri iOS sürümüne bağlı; mevcut değilse sessizce atlanır.
- Whoop alan adları (score alt-yapıları) canlı API ile doğrulanmalı — Claude Code gerçek yanıtla kontrol etmeli.

## Yol haritası

v1 (bu kod) → çalışır dashboard. v2 → widget + cheat etiketleme + Whoop workout. v3 → bildirimler + CGM. Her adımda gerçek cihazda derle-test-düzelt.
