# Release ve CI Kapıları (anayasa §7 — F10)

## Xcode Cloud kurulumu (App Store Connect'te bir kez, kullanıcı yapar)

Repo sırsız derlenir (ADR-0002) — CI için hiçbir environment variable veya `ci_scripts/` GEREKMEZ.

**Workflow 1 — "PR":** her pull request / branch push'unda
1. Action: **Build** — scheme `Bearing`, platform iOS
2. Action: **Test** — scheme `Bearing` (BearingTests dahili), en güncel iPhone simülatörü

**Workflow 2 — "Main":** `main`'e merge'de
1. Build + Test (aynısı)
2. (TestFlight'a geçilirse) Archive + Internal TestFlight dağıtımı

**Workflow 3 — "Release":** `release/*` tag'inde — Archive + production kontrolü + External TestFlight.

## Yerel kapı komutları (her PR öncesi)

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Bearing.xcodeproj -scheme Bearing -destination 'platform=iOS Simulator,name=Bearing Test iPhone'
python3 docs/prompts/eval.py --offline --sync-check
```

## Release kuralları (Store'a gidilirse)

- Phased release varsayılan; kritik hata üçlüsü tasarlanmadan gönderim yok: kill switch/feature flag envanteri + hazır hotfix hattı + önceki veri şemasıyla uyumluluk.
- Data migration provası release candidate üzerinde (UserDefaults şema anahtarları: `engine_settings_v1`, `dashboard_enabled_metrics_v1`, `fetch_window_days_v1`, plan/log anahtarları — sürüm ekinde migration notu tut).
- Store Readiness Gate öz-denetimi: `docs/DENETIM-2026-07-26.md` §3/Aşama 8 satırı + anayasa Aşama 8 tablosu.
- Her store release'i sonrası 30 dk retro → DENETIM dokümanına ek (anayasa §12).
