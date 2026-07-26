# ADR-0001 — Bulut AI'ya proxy'siz doğrudan erişim (K2 kuralından bilinçli sapma)

| Alan | Değer |
|---|---|
| Durum | Kabul edildi |
| Tarih | 2026-07-26 |
| Saptığı kural | Anayasa v1.0 §8.2 "Bulut çağrıları yalnızca kendi proxy'n üzerinden" + §5 "LLM anahtarları asla client'a gömülmez" |

## Karar

Bearing, OpenRouter'a cihazdan **doğrudan** bağlanır (`AI/OpenRouterClient.swift` → `https://openrouter.ai/api/v1/chat/completions`). Araya sunucu (K2 proxy) konmaz.

## Gerekçe

- Tek kullanıcılı kişisel araç; anahtar **kullanıcının kendi OpenRouter anahtarı**, uygulamaya gömülü değil, kullanıcı tarafından girilip **yalnız Keychain'de** tutuluyor (`AIConfig.apiKey`). §5'in yasakladığı "geliştiricinin anahtarını client'a gömme" durumu yok.
- Proxy'nin koruduğu şeyler (anahtar gizliliği, kota, kimlik) tek kullanıcıda anlamını yitiriyor; işletme maliyeti ve yeni bir arıza noktası ekliyor.
- AI katmanı varsayılan KAPALI; açılmadan uygulama tamamen çevrimdışı.

## Sonuçlar / riskler

- İstek başına kimlik, sunucu tarafı rate-limit ve merkezi maliyet tavanı YOK → maliyet tavanı istemci tarafında uygulanmalı (backlog: günlük token bütçesi).
- Prompt trafiği OpenRouter üzerinden seçilen sağlayıcıya gider; zero-retention garantisi isteğe eklenmiyor (backlog).

## Geri dönüş tetikleyicileri (K2'ye zorunlu geçiş)

1. Uygulamanın Atilla dışında herhangi bir kullanıcıya dağıtımı (TestFlight dahil).
2. Anahtarın uygulamayla birlikte sağlanması ihtiyacı (kullanıcıdan anahtar istememe).
3. Merkezi kota/maliyet yönetimi ihtiyacı.
