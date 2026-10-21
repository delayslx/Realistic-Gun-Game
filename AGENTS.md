# AGENTS.md - RealisticGunGame

Bu dosya bu repo'da çalışan tüm agent'lar için geçerlidir.

## 1. MCP Kullanımı (Zorunlu)

- Godot ile ilgili her işlemde her zaman `godot-ai` MCP tool'larını kullan.
- Tahminle dosya yazma, sahne / node / script durumunu varsayma. Önce MCP ile doğrula:
  - `session_manage (op=list)` ile aktif oturumu bul
  - `scene_list / scene_get / node_list` ile sahne yapısını oku
  - `script_read` ile mevcut script'i okumadan düzenleme yapma
- Değişiklik sonrası `scene_save`, `script_write` sonrası gerekirse `play_start` + `console_get` ile doğrula.
- MCP tool'u başarısız olursa dur, hatayı kullanıcıya göster, varsayımla devam etme.
- `shell`, `read`, `edit` ile Godot editör state'ini değiştirmeye çalışma; tek kaynak MCP'dir.

## 2. Soru Sorma Kuralı

Belirsiz durumlarda kod yazmadan ÖNCE `question` tool'u ile sor:

- Hangi sahne / node / script hedefleniyor belli değilse
- Birden fazla geçerli implementasyon yolu varsa (örn: GDScript vs sahne ayarı, input map değişsin mi?)
- Silme, overwrite, input map / project.godot değişikliği, büyük refactor gerekiyorsa
- Kullanıcı isteği "mcp'de ne yapması" gibi eksik / yazım hatalı ise ve niyet çıkarılamıyorsa

Soru sormadan devam edilebilecek tek durum: tek dosyalık küçük fix ve hedef + kapsam net ise.

## 3. Doğrulama

- Çözümü mümkünse çalıştırarak doğrula: `play_start` -> `console_get` -> hata varsa düzelt.
- Dosya referansı verirken `dosya: satır` formatını kullan.
- Kısa, teknik, Türkçe cevap ver. Emin olmadığın URL'yi uydurma.
