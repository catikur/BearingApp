# ADR-0003 — Telemetrisiz/logsuz çalışma (gözlemlenebilirlik ertelemesi)

| Alan | Değer |
|---|---|
| Durum | Kabul edildi |
| Tarih | 2026-07-26 |
| Saptığı kural | Anayasa v1.0 §1 (TelemetryDeck + MetricKit), Aşama 5 "analytics core event'leri", §7 kapı kanıtı "analytics event'leri düşüyor" |

## Karar

Bearing şimdilik **hiçbir telemetri, crash raporlama veya yapılandırılmış log** içermez (envanter: TelemetryDeck/MetricKit/os_log/print = 0).

## Gerekçe

- Tek kullanıcı = geliştirici; "kullanıcı davranışı" telemetrisinin öğreteceği şey yok.
- Sağlık verisi işleyen kişisel araçta privacy-first varsayılanın en güçlü hali: hiçbir şey toplamamak.
- Saha hatası ayıklama ihtiyacı şu an cihaz başında yaşanıyor (geliştirici = kullanıcı).

## Sonuçlar / riskler

- Cihazda geçmişe dönük hata teşhisi imkânsız (ör. Whoop senkron sorunları yalnız Ayarlar'daki tanı paneliyle görülür).
- **Hafifletme (backlog, düşük öncelik):** kişisel veri içermeyen, cihazda kalan halka-log (os_log/Logger) — telemetri değildir, §5 log kurallarına uyar.

## Geri dönüş tetikleyicileri

1. TestFlight'a çıkma kararı → TelemetryDeck + MetricKit **zorunlu** olur (Aşama 5/7 kapı kanıtı); `docs/ANALYTICS.md` event sözlüğü ile birlikte gelir.
2. Tekrarlayan, cihaz başında yakalanamayan saha hatası → önce yerel os_log katmanı.
