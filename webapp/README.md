# Pafta Masası — web app prototipi

SketchUp işleri için talep, revizyon ve pafta takibi. İlk prototip claude.ai
artifact'i olarak yayında; veriler artifact'in veri deposunda tutulur.

| Dosya | Ne |
|---|---|
| `pafta-masasi.html` | Uygulamanın tamamı (tek dosya) |
| `tools/seed.mjs` | Örnek proje verisini üretir → `seed/` |
| `seed/` | Örnek proje: 1 proje, 4 talep, 5 pafta, 2 imalat objesi |

## Bölümler

- **Talepler** — Taslak → Claude'da → Kontrolde → Onaylandı. Her talep v1, v2…
  diye versiyonlanır. Ekran görüntüsü Ctrl+V ile yapıştırılır, üzerine nokta /
  bölge işaretlenir, işaretlerden revizyon promptu otomatik kurulur.
- **Paftalar** — pafta listesi, versiyon geçmişi, durum, kime gönderildiği.
- **İmalat** — parça verisinden otomatik A3 imalat paftası (ön görünüş,
  kapaksız ön görünüş, A-A kesiti, izometrik, zincir ölçüler, parça listesi,
  bant, donanım, detaylar, antet, versiyon tablosu) ve "usta soru sorar mı?"
  kontrolü. PDF / SVG / kesim listesi (CSV) çıktısı.
- **Standartlar** — malzeme kütüphanesi, bant kuralları, tag yapısı, Claude
  çalışma kuralları, antet. Her prompta ve paftaya otomatik girer.
- **SketchUp köprüsü** — yol haritası: köprü eklenti → MCP → bileşenden
  imalat verisi → LayOut çıktısı → Make Faces ile model kontrolü.

## Veri modeli

Koleksiyonlar: `projects`, `requests`, `sheets`, `items`.
İmalat parçaları mm cinsinden kutu (x, y, z, w, d, h) olarak tutulur; x genişlik,
y derinlik (kapak önü y=0), z yükseklik. Köprü eklenti bu kutuları SketchUp
bileşenlerinin sınır kutularından üretecek.

Örnek veriyi yeniden üretmek için:

```bash
node webapp/tools/seed.mjs
```
