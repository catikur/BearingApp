# Kurulum — Sağlık Dashboard iOS App

## 1) Xcode projesi
1. Xcode → File → New → Project → **iOS → App** → Next
2. Name: `Bearing` · Interface: **SwiftUI** · Language: **Swift**
3. Xcode'un oluşturduğu `ContentView.swift` ve `BearingApp.swift`'i **sil** (bizimkiler var).
4. Bu klasördeki tüm `.swift` dosyalarını (App, Shared, HealthKit, Whoop, Dashboard, Config) proje ağacına sürükle → "Copy items if needed" işaretli.

## 2) Ayarlar
- **Signing & Capabilities** → Team = Apple ID'n; **+ Capability → HealthKit**.
- **Deployment target = iOS 17.0** (veya üstü).
- **Info** sekmesi → Add Row: `Privacy - Health Share Usage Description` → açıklama gir.
- **Info → URL Types** → Identifier: `whoop`, URL Schemes: `bearing`.

## 3) Whoop (opsiyonel ama Recovery/Strain için gerekli)
1. developer.whoop.com → giriş → **Create App**.
2. Redirect URI: `bearing://whoop-callback`
3. Scopes: recovery, cycles, sleep, workout, profile, body_measurement, offline
4. `Config/Secrets.example.swift`'i kopyala → `Secrets.swift`; client ID/secret gir.
5. `Secrets.swift`'i `.gitignore`'a ekle.

## 4) Çalıştır
- **Gerçek iPhone** bağla (HealthKit simülatörde çalışmaz).
- Xcode'da cihazını seç → ▶ Run.
- iPhone → Ayarlar → Genel → VPN & Cihaz Yönetimi → geliştiriciye güven ver (ilk sefer).
- App'te HealthKit izni ver; menüden "Whoop'a bağlan".

## 5) Veri kaynaklarını doğrula
Apple Health → Paylaşım → Uygulamalar:
- Cronometer bağlı (beslenme yazıyor)
- Whoop bağlı (HRV/RHR/uyku yazıyor)
- Tartı bağlı (kilo/yağ %)

Veri yoksa app boş görünür — kaynak bağlantısı sorunudur, kod değil.

## 6) Claude Code ile geliştir
Proje klasöründe Claude Code'u aç. `CLAUDE.md` ve `PROJECT_SPEC.md` bağlamı verir. İlk komut:

> "Projeyi gerçek iPhone hedefiyle derle, hataları düzelt. Sonra Whoop v2 alan adlarını canlı API yanıtıyla doğrula. Ardından ana ekran widget'ı ekle."

## Özelleştirme (dashboard'a metrik ekle/çıkar)
App içinde sağ üstteki **kaydırıcı ikonu** → "Metrikleri Düzenle":
- Üstteki listeden çıkar (dokun) veya sürükleyip sırala
- Kategorilerden yeni metrik ekle (dokun)
- 90+ metrik mevcut: beslenme makro/mineral/vitamin, kalp, solunum, aktivite, uyku, Whoop skorları

---

## Yeni katmanlar (v2)

### Ayarlar
Ana ekran → sol üst `⋯` → **Ayarlar**. Buradan değiştirilebilenler:
- Profil (yaş, boy, cinsiyet) ve hedef (hedef kilo, hedef hız, başlangıç kilosu, amaç notu)
- Adaptif TDEE: pencere, minimum gün, kcal/kg, minimum log kapsaması
- Kilo trendi: EMA yarı ömrü, hız penceresi
- Baseline: pencere, z eşiği, minimum örneklem, izlenecek metrikler, bileşik sinyal metrikleri
- Guardrail: pencere, "iyi" skor eşiği, kural listesi

Hiçbir eşik kodda sabit değildir. "Sıfırla" seçenekleri başlangıç setine döner.

### Guardrail kuralları
Ayarlar → Guardrail uyumu → Kuralları düzenle. Üç kural tipi:
- **Metrik eşiği** — ör. Protein ≥ 150 g
- **Enerji yüzdesi** — ör. Doymuş yağ ≤ %7 (gram × kcal/g ÷ toplam kalori)
- **Etiket sıklığı** — ör. Alkol ≤ 1 gün/hafta (yerel etiketleri kullanır)

Her kuralın skordaki ağırlığı ayarlanabilir; gerekçe notu yapay zekâ bağlamına da girer.

### Yapay zekâ (opsiyonel, varsayılan KAPALI)
Ayarlar → Yapay Zekâ:
1. openrouter.ai'den API anahtarı al, gir (Keychain'e yazılır, yedeğe çıkmaz)
2. Model seç (hazır liste) veya kimliği elle yaz
3. Sistem promptunu istersen düzenle — varsayılan sınırlayıcı: hesap yapma, sayı uydurma,
   tanı koyma, ilaç dozu verme, kanıt seviyesi etiketle
4. Modele neyin gönderileceğini tek tek aç/kapat
5. Kalıcı hafıza: kendi notlarını ekle, önemlileri sabitle (📌)

Sohbet: ana ekran sağ üst ✨. Menüden **"Gönderilen bağlamı gör"** ile modele giden metnin
tamamı birebir okunabilir.

**Ağ:** yapay zekâ katmanı `openrouter.ai` adresine bağlanır. Kapalıyken uygulama tamamen
çevrimdışı ve deterministik çalışır.

### Keşif filtreleri
Ayarlar → Korelasyon keşfi → **Keşif filtreleri** (veya keşif ekranındaki "… çift gizlendi" satırı).
Burada hangi metrik çiftlerinin listeden çıkarıldığı birebir listelenir ve iki filtre de kapatılabilir:
- **İkizler** — iki kaynak aynı şeyi ölçüyor (Apple HRV ↔ Whoop HRV gibi)
- **Aileler** — biri diğerinin parçası (derin uyku ↔ toplam uyku, kilo ↔ BMI ↔ yağ %)

Ayrıca minimum ortak gün, listelenecek bulgu sayısı ve ertesi gün taraması buradan ayarlanır.
Filtreler hiçbir veriyi silmez; yalnızca sıralamayı temizler.

---

## Plan ve bildirimler (v3)

### Xcode kurulumu — ek adım
Bildirimler için **Signing & Capabilities → + Capability → Push Notifications** gerekmez
(yerel bildirim kullanıyoruz), ancak uygulama ilk açılışta bildirim izni ister. İzni
reddedersen plan çalışır, sadece hatırlatma gelmez; Ayarlar → Bildirimler'den tekrar isteyebilirsin.

### Kullanım
- **Bugün** sekmesi: günün zaman çizelgesi. Sağdaki daireye dokun → Yaptım / Atladım / işareti kaldır.
  Oklarla geçmiş günlere gidip geriye dönük işaretleyebilirsin.
- **Bildirimden loglama:** bildirimi aşağı çekince **Yaptım · Atladım · 30 dk ertele** çıkar.
  Uygulamayı açmadan işaretlenir.
- **Antrenman:** plan satırındaki "seansı aç" ile hareket listesi açılır; kg × tekrar girip
  set işaretlersin. Geçen seferki değerlerin altında görünür.
- **Plan düzenleme:** Bugün sekmesi sağ üst ikon veya Ayarlar → Plan öğeleri.
  Zamanlama tipleri: her gün · haftanın günleri · N günde bir · tek sefer · **bir tarihe göreli**
  (ör. "kan testinden 3 gün önce biotini kes").

### Faz (tek değişken kuralı)
Plan öğeleri faz numarası taşır. Faz 2 ancak faz 1 belirlenen gün sayısı ve uyum eşiğini
geçince açılır. Ayarlar → Bildirimler → Faz kuralı'ndan süre ve eşik değiştirilebilir,
tamamen kapatılabilir.

### Entegrasyon
- Guardrail'e yeni kural tipi: **Plan uyumu** (ör. "Suplement uyumu ≥ %80")
- Korelasyon taramasına plan girer: "rutini tamamladığım günler → ertesi gün HRV"
- Yapay zekâ bağlamına bugünün planı, uyum yüzdeleri ve seri eklenir

---

## Yapay zekâ ile plan üretimi (v4)

### Önce bağlamı doldur
**Ayarlar → Kişisel bağlam.** Uygulamanın ölçemediği ama modelin bilmesi gereken şeyler:
aktif durumlar, **kesin kaçınılacaklar**, intoleranslar, tercihler, antrenman ekipmanı,
zaman kısıtları, kilit lab değerleri, bekleyen uzman onayları. Boş bırakılan alan gönderilmez.

### Görevler
Asistan ekranında (✨) üstteki şeritten görev seçilir:
- **Serbest soru** — normal sohbet, yorum
- **Beslenme planı hazırla** — yapılandırılmış öneri döner
- **Antrenmanı ayarla** — şablon revizyonu önerir
- **Planı gözden geçir** — uyum verisine bakıp sadeleştirme önerir

Her görevin talimatı **Ayarlar → Yapay Zekâ → Görev talimatları**'ndan düzenlenebilir.

### Öneri akışı — hiçbir şey otomatik uygulanmaz
1. Model JSON öneri döndürür
2. **Motor doğrular:** kalori hedefi TDEE hesabıyla uyumlu mu, guardrail kuralları ihlal
   ediliyor mu, kaçınılacaklar listesinden bir şey geçiyor mu, tek değişken kuralı aşılıyor mu,
   sessiz saatlere düşen bildirim var mı, bildirim yükü ne kadar artıyor
3. Uyarılar 🔴 engelleyici / 🟠 uyarı / ℹ️ bilgi olarak listelenir
4. Sen **tek tek seçip** uygularsın; seçmediklerin plana girmez

Uygulanan yeni öğeler **bildirimi kapalı** gelir — planda görüp saatini ayarladıktan sonra açarsın.
