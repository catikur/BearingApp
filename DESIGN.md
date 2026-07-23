# SaglikDashboard — Tasarım Sistemi Dokümantasyonu

Bu doküman, üretilen UI/UX tasarımlarının SwiftUI bileşenlerine çevrilmesinde alınan kararları ve bileşen kütüphanesinin kullanım kurallarını açıklar. Uygulamanın karakteri **"sakin enstrüman"**dır: veri güvenilir ve okunaklıdır, arayüz kullanıcıyı yormaz, kutlamaz, utandırmaz. Bütün ekranlar saf SwiftUI ile, iOS 26 hedeflenerek yazılmıştır ve tüm görünür metinler Türkçedir.

## Dosya Yapısı

| Dosya | Tasarım karşılığı | İçerik |
|---|---|---|
| `Shared/DesignSystem.swift` | Tüm görseller | `DS` isim alanı: renk semantiği, boşluk/yarıçap ölçekleri, tipografi rolleri, `tr_TR` biçimlendirme yardımcıları, `cardSurface()` |
| `Shared/DesignComponents.swift` | Tüm görseller | Bileşen kütüphanesi: `ConfidenceText`, `EngineCard`, `BigStat`, `ThinBar`, `PlanTimelineRow`, `MetricCard`, `IdentityChip`, `StatusChip`, `EmptyStateView`, `SectionHeader`, `SparklineView` |
| `Plan/TodayView.swift` | Görsel 01 / 05 | "Bugün" sekmesi: gün gezinme, günün özeti, tek dokunuşlu plan zaman çizelgesi |
| `Dashboard/DashboardView.swift` | Görsel 02 | "Panel" sekmesi: eşit olmayan görsel ağırlıkta dört motor kartı, metrik ızgarası |
| `Dashboard/MetricDetailView.swift` | Görsel 03 | Metrik detay: baseline bandı, az-veri segmenti, korelasyon kartları (Swift Charts) |
| `Dashboard/WeightJourneyView.swift` | Görsel 04 | Kilo yolculuğu: ham noktalar + EMA + kesikli projeksiyon + belirsizlik konisi |
| `Plan/WorkoutSessionView.swift` | Görsel 06 | Antrenman seansı: `BigStepper`, "Seti Kaydet", camlı dinlenme sayacı çubuğu |
| `App/RootView.swift` | Görsel 07 | İki sekmeli kök gezinme (Bugün açılış sekmesidir) |

## Temel Kararlar ve Gerekçeleri

### 1. Renk iki ayrı kanal taşır

Renk sisteminin tamamı `DesignSystem.swift` içinde iki ayrı kanala bölünmüştür ve bu ayrım koddaki tip sistemiyle zorlanır. **Kimlik kanalı** (`IdentityColor` enum'u) plan kategorilerini ayırt eder: düşük doygunluklu yedi renk (öğün kum, suplement mor, antrenman adaçayı, boyun/TME mavi-yeşil, sirkadiyen hardal, ölçüm çelik mavi, randevu pudra) sık kullanılır ve hiçbiri diğerinden daha "önemli" görünmez. **Durum kanalı** (`DS.Status`) yüksek doygunluklu ve nadirdir; ekranda bir durum rengi göründüğünde bu her zaman anlam taşır. `DashboardView` bu kuralın canlı örneğidir: bütün ekranda tek durum rengi vardır ("Sodyum: dikkat" amber'ı).

> Kritik kırmızı (`DS.Status.critical`) yalnızca iki bağlamda kullanılabilir: bileşik sapma sinyali ve engelleyici doğrulama uyarısı. Rutin "hedefin altındasın" durumu kritik değildir ve nötr gösterilir. Bu kural kod yorumlarına da gömülmüştür.

### 2. Belirsizliğin görsel dili (imza öğesi)

`ConfidenceLevel` + `ConfidenceText` ikilisi, bir sayının ne kadar güvenilir olduğunu tutarlı bir tipografik dille ifade eder: düşük güven **ince ağırlık + kesikli alt çizgi**, yüksek güven **tam ağırlık + düz alt çizgi**. Aynı dilbilgisi istisnasız her yerde geçerlidir — Panel'deki TDEE değeri (9 günlük veri, düşük güven), korelasyonlarda `n < 10` durumu, kilo projeksiyonundaki tahmini varış tarihi ve grafiklerdeki az-veri segmentleri (kesikli çizgi + içi boş noktalar). Kullanıcı bu deseni bir kez öğrendiğinde uygulamanın hiçbir yerinde yanıltılmaz.

### 3. Kaçırılan öğe utandırmaz, tamamlanan öğe kutlanmaz

`PlanTimelineRow` üç durumu sessiz bir görsel sözlükle ayırır: bekleyen öğe boş halka, tamamlanan öğe sakin teal onay işareti, atlanan öğe ise %50 opaklık + gri tire alır. Kırmızı çarpı, konfeti, rozet patlaması ve suçlayıcı metin yoktur. Seri sayacı ("Seri: 12 gün") `TodayView`'ın özet kartında üçüncül renkte, ekranın kahramanı olmadan durur. Tamamlama animasyonu 150 ms'lik tek bir `easeInOut` geçişi ve hafif haptiktir.

### 4. Liquid Glass yalnızca işlevsel katmanda

iOS 26'nın `glassEffect` API'si kod tabanında tam bir noktada geçer: `WorkoutSessionView`'ın yüzen dinlenme sayacı çubuğu. Tab bar camını sistem kendisi çizer. İçerik kartları ise `cardSurface()` düzenleyicisinden geçer — mat kart yüzeyi, 0,5 pt ayırıcı kenar, `DS.Radius.lg` sürekli köşe. İçeriğe cam uygulanmaması, verinin okunabilirliğinin dekoratif efektlere feda edilmemesi kararıdır.

### 5. Ölçekler serbest sayıyı yasaklar

Boşluklar `DS.Space` (4/8/12/16/24/32), köşeler `DS.Radius` (8/12/16/20), dokunma hedefleri `DS.Touch` (44 pt minimum, spor salonu bağlamı için 56 pt konforlu) üzerinden alınır. Tipografi `DS.Font` rolleriyle tanımlıdır ve Dynamic Type ile ölçeklenir; sabit `.system(size:)` çağrısı yoktur. Sayısal değerler `.rounded` tasarım + `monospacedDigit()` kullanır, böylece değer değişirken düzen zıplamaz.

### 6. Türkçe yerelleştirme tek kaynaktan

`DS.locale` (`tr_TR`) ve `DS.decimal / DS.integer / DS.percent / DS.shortDate` yardımcıları bütün sayı ve tarih biçimlendirmesinin tek kaynağıdır: ondalık virgül (82,4), binlik nokta (2.410), yüzde işareti önde (%64), tarih "12 Eylül" biçiminde. `DS.uppercased` Türkçe İ/ı dönüşümünü korur. Ekran kodunda elle biçimlendirilmiş sayı dizesi bulunmaz.

### 7. Grafikler Swift Charts ile ve güven dilbilgisine sadık

`MetricDetailView` kişisel baseline bandını soluk teal `RectangleMark` ile, az-veri segmentini kesikli `LineMark` + içi boş `PointMark` sembolleriyle çizer. `WeightJourneyView` ham tartımları soluk noktalar, EMA'yı tam ağırlıklı düz çizgi, projeksiyonu kesikli çizgi ve genişleyen `AreaMark` belirsizlik konisi olarak katmanlar. Rutin z-skor sapmaları nötr `StatusChip` ile gösterilir; grafikte kırmızı yoktur.

### 8. Hız öncelikli form

`WorkoutSessionView` spor salonu bağlamı için tasarlandı: `BigStepper` 56 pt dokunma hedefli ± butonlarıyla tek elle kullanılır, ağırlık 2,5 kg adımlarla değişir, birincil buton ne yapacağını söyler ("Kaydet" değil "Seti Kaydet"). Set kaydı sakin bir onay üretir: listeye satır eklenir, 90 saniyelik dinlenme sayacı camlı çubukta belirir, konfeti yağmaz.

## Bileşen Kullanım Özeti

| Bileşen | Ne zaman kullanılır | Kural |
|---|---|---|
| `EngineCard` | Panel'deki motor özetleri | Kart kabuğu içerik katmanıdır; cam yok |
| `BigStat` | Büyük sayısal değer + birim | Güven seviyesi zorunlu parametre alışkanlığı edinin |
| `ConfidenceText` | Güveni değişken her sayı | Düşük güvende asla tam ağırlık kullanmayın |
| `ThinBar` | İlerleme gösterimi | Rutin ilerleme teal; kırmızıya asla dönmez |
| `PlanTimelineRow` | Plan öğeleri | Atlanan öğe soluk + gri tire; kırmızı ✗ yasak |
| `IdentityChip` / `StatusChip` | Kategori / durum rozetleri | Kimlik sık, durum nadir |
| `MetricCard` + `SparklineView` | Metrik ızgarası | Mini eğri eğilim bilgisi taşır, süs değildir |
| `EmptyStateView` | Veri yokluğu | Yön gösterir, özür dilemez |
| `BigStepper` | Hızlı sayısal giriş | 56 pt hedef, tek elle erişim |

## Entegrasyon Notları

Ekran dosyalarındaki örnek veriler (`TodayPlanItem.sample`, `WeightSample.sample` vb.) tasarım görselleriyle birebir eşleşecek şekilde hazırlanmıştır ve gerçek motor çıktılarıyla (`PlanEngine`, `Engines.swift`, `HealthKitManager`) değiştirilmek üzere açıkça işaretlenmiştir. Mevcut `EngineCard`, `BigStat`, `ThinBar` ve `MetricCard` API'leri korunmuştur; bu bileşenleri halihazırda çağıran kod değişiklik gerektirmez. `Color.adaptive(light:dark:)` yardımcısı asset kataloğu olmadan çalışır; proje asset kataloğuna geçmek isterseniz yalnızca `DesignSystem.swift` içindeki renk tanımları değişir. Korelasyon güven eşiği (`n < 10`) şu an `CorrelationPair` içinde sabittir; `EngineSettings`'e bağlamak için tek satır değişir.

Her dosyanın sonunda light ve dark önizlemeler tanımlıdır; Xcode canvas'ta iki modu yan yana doğrulayabilirsiniz. Koyu modda zemin saf siyah değil `#12181B`'dir ve kimlik renkleri çamurlaşmayı önlemek için hem biraz daha açık hem biraz daha doygun varyantlara geçer.

---
*Manus AI — SaglikDashboard tasarım sistemi, FAZ 1*
