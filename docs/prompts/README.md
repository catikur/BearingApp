# AI Prompt & Eval Disiplini (anayasa §8.2 / §8.4)

## Kaynak gerçeği

Çalışma zamanı kaynağı **kod**dur: `AI/AIConfig.defaultSystemPrompt` ve `AI/AITasks.defaultInstruction`.
Bu klasör onların **versiyonlu kopyası + golden set + eval koşucusu**nu tutar.

- `system-prompt-v1.md` — ana sınırlayıcı promptun v1 kopyası
- `task-instructions-v1.md` — görev talimatlarının v1 kopyası
- `golden-set-v1.jsonl` — 25 gerçekçi girdi (güvenlik tuzakları dahil) + beklenen nitelik kontrolleri
- `eval.py` — deterministik kontrol koşucusu (offline / sync-check / live modları)
- `fixtures/` — kontrolcülerin doğru ateşlediğini kanıtlayan örnek çıktılar

## Kurallar

1. **Prompt değişikliği = bu klasörde yeni sürüm + eval koşusu.** `system-prompt-v2.md` aç,
   kodu güncelle, `eval.py --sync-check` yeşil olsun, canlı eval sonucunu commit mesajına yaz.
2. **Güvenlik kategorilerinde 0 tolerans:** `safety_dosage` ve `safety_diagnosis` girdilerinde
   tek başarısızlık bile değişikliği bloklar.
3. Kullanıcı uygulama içinden promptu düzenleyebilir (UserDefaults gölgesi) — bu kişisel
   özelleştirmedir, repo sürümünü değiştirmez. Varsayılana dönüş: Ayarlar → Yapay Zekâ.

## Kullanım

```bash
# Şema + kontrolcü doğrulaması (ağ yok; fixture'larla)
python3 docs/prompts/eval.py --offline

# Kod ↔ doküman senkron kontrolü
python3 docs/prompts/eval.py --sync-check

# Canlı eval (cihaz dışında, kendi anahtarınla)
OPENROUTER_API_KEY=sk-... python3 docs/prompts/eval.py --live --model anthropic/claude-sonnet-4.5
```

Canlı eval bu repo'daki hiçbir gerçek sağlık verisini KULLANMAZ; golden set sentetiktir.
