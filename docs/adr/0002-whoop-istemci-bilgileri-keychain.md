# ADR-0002 — Whoop istemci bilgileri: gömülü Secrets.swift kaldırıldı, Keychain'e geçildi

| Alan | Değer |
|---|---|
| Durum | Kabul edildi (sapma bu kararla GİDERİLDİ) |
| Tarih | 2026-07-26 |
| İlgili kural | Anayasa v1.0 §5 "Secrets repository'ye ve binary'e yazılmaz" |

## Bağlam

Eski kurulum: Whoop `client_id`/`client_secret` gitignore'lu `Config/Secrets.swift` içinde koda gömülüydü. İki sorun: (1) sır binary'ye giriyordu (§5 sapması), (2) dosya repo'da olmadığından **Xcode Cloud checkout'unda derleme kırılıyordu**.

## Karar

`WhoopSecrets` tipi ve `Config/Secrets(.example).swift` dosyaları silindi. İstemci bilgileri artık:

- Uygulama içinden girilir: **Ayarlar → Veri kaynakları → Whoop istemci bilgileri**.
- Yalnız **Keychain**'de saklanır (`whoop_client_id`, `whoop_client_secret`; `WhoopAuth.saveCredentials`), OpenRouter anahtarıyla aynı kalıp.
- `redirectURI` sır değildir; kodda sabittir (`bearing://whoop-callback`, Info.plist URL scheme ile eşleşir).

Repo ve binary artık sırsızdır; her ortam (Xcode Cloud dahil) ek yapılandırmasız derlenir.

## Reddedilen alternatif

`ci_scripts/ci_post_clone.sh` + Xcode Cloud env-var'larından Secrets.swift üretmek: CI'ı düzeltir ama sırrı binary'e gömmeye devam eder ve CI'a sır yönetimi ekler.

## Kalan gerçek / tetikleyici

OAuth token değişimi client_secret'ı cihazdan Whoop'a gönderir (tek kullanıcıda kabul edilebilir). **Dağıtım senaryosunda** (TestFlight/Store) Whoop'un public-client/PKCE-only desteği veya token değişimini yapan minimal proxy zorunlu değerlendirmedir.
