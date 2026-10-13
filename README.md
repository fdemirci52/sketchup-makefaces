# Yüzey Oluştur (Make Faces) — SketchUp eklentisi

Üç iş yapar:

1. **Yüzey oluşturma** — s4a `makeFace` ile aynı iş: kapalı ve düzlemsel kenar
   döngülerini bulup eksik yüzeyleri üretir.
2. **Kenar temizliği** — iki tarafındaki yüzeyler aynı düzlemde olan, yani
   yüzeyi boş yere bölen ayırıcı çizgileri siler.
3. **Hacim birleştirme** — ayrı ayrı push/pull yapılmış bitişik parçaların
   arasında kalan iç bölücü yüzeyleri siler, sonra kalan çizgileri temizler.

SketchUp Pro 2021 hedeflenerek yazıldı (SketchUp 2017+ ile uyumludur).

## Kurulum

**Yöntem 1 — .rbz ile (önerilen)**
1. SketchUp → `Window` (Pencere) → `Extension Manager`
2. Sol alttaki `Install Extension` düğmesi
3. `dist/MakeFaces-1.5.0.rbz` dosyasını seç → `Yes` / `Evet`
4. SketchUp'ı yeniden başlat

Eski sürüm kuruluysa üzerine kurmadan önce Extension Manager'dan kaldırmak
gerekmez; aynı klasörün üzerine yazar.

**Yöntem 2 — elle kopyalama**
`src/` içindeki `mf_make_faces.rb` dosyasını ve `mf_make_faces` klasörünü şuraya kopyala:

```
C:\Users\<kullanıcı>\AppData\Roaming\SketchUp\SketchUp 2021\SketchUp\Plugins\
```

## Kullanım

- Araç çubuğu: `Yüzey Oluştur`
- Menü: `Extensions` → `Yüzey Oluştur (Make Faces)`
- Sağ tık menüsü (seçim varken): üç komut da orada

### Komutlar

| Komut | Ne yapar |
|---|---|
| **Seçimden Yüzey Oluştur** | Seçili kenar/yüzeylerden yüzey üretir |
| **Aktif Bağlamın Tamamında** | Seçim gerekmez; bağlamdaki tüm kenarları işler |
| **Gereksiz Çizgileri Temizle** | Aynı düzlemdeki yüzeyleri bölen çizgileri siler |
| **Bitişik Hacimleri Birleştir** | İç bölücü yüzeyleri siler + kenar temizliği yapar |
| **Seçili Çizgileri Birleştir** | Sen hangi çizgilerin gideceğini seçersin, eklenti doğru sırayla yok eder |
| **Yüzey Oluştur + Temizle** | Yüzeyleri kurar, sonra çizgileri temizler |

Son üç komut **seçim varsa seçimde, yoksa aktif bağlamın tamamında** çalışır.
Her komut tek bir işlemdir; `Ctrl+Z` ile bir kerede geri alınır.

### Ayarlar (menüden açılıp kapanır, kalıcıdır)

| Ayar | Varsayılan | Ne yapar |
|---|---|---|
| **Grup / Bileşen İçine Gir** | açık | Grup/bileşenlerin içindeki geometri de işlenir |
| **Malzeme / Tag Farkını Koru** | açık | Farklı malzeme/tag taşıyan yüzeyler birleştirilmez |
| **Boştaki Çizgileri de Sil** | kapalı | Hiçbir yüzeye ait olmayan tek çizgileri de siler |
| **Yeni Yüzeyleri Seç** | kapalı | İşlem sonunda oluşan yüzeyler seçili kalır |

## Neden iki ayrı temizlik komutu var?

**Gereksiz Çizgileri Temizle** sadece kenarlara bakar. Bir çizgi yalnızca şu
şartların hepsini sağlıyorsa silinir:

- İki tarafında **tam olarak 2** yüzey var (ve bunlar farklı yüzeyler)
- Bu iki yüzey aynı düzlemde **ve aynı yöne bakıyor**
- Strict ayarı açıkken: ön yüz malzemesi, arka yüz malzemesi ve tag'i aynı

Ama iki parça **ayrı ayrı push/pull** edildiyse aralarında bir bölücü yüzey
kalır. Dıştan görünen ayırıcı çizginin 2 değil **3 yüzeyi** olur, bu yüzden
yukarıdaki kural ona dokunamaz — önce iç yüzeyin gitmesi gerekir.

**Bitişik Hacimleri Birleştir** bunu yapar. Bir yüzeyi "iç bölücü" sayması için:

- Yüzeyin **hiçbir kenarı açık olmamalı** — her kenarında en az 2 yüzey
  bulunmalı, yani yüzey her tarafından başka geometriye gömülü olmalı. Tek
  başına duran bir bölme duvarının serbest kenarları (1 yüzey) bunu geçemez.
- **En az bir** kenarda, diğer yüzeyler arasında eş düzlemli ve aynı yöne bakan
  bir çift olmalı — yani bu yüzey gerçekten sürekli bir yüzeyi bölüyor olmalı.
- Yüzeyin kendisi o eş düzlemli çiftle **aynı düzlemde olmamalı**; öyleyse bu
  bir çakışık (üst üste binmiş) yüzeydir, dokunulmaz.
- Strict ayarı açıkken o eş düzlemli çiftler birleştirilebilir olmalı.

İç yüzeyler silindikten sonra kenar temizliği otomatik olarak çalışır.

## Otomatik kural yetmezse: Seçili Çizgileri Birleştir

Otomatik testin kaçırdığı çizgiler için **sen seçersin**:

1. Gitmesini istediğin çizgileri seç
2. `Seçili Çizgileri Birleştir` (araç çubuğu, menü ya da sağ tık)
3. Kaç çizginin gideceğini ve bunun için kaç yüzeyin silineceğini söyler, onay ister

> **Delete tuşuna basma.** 2'den fazla yüzeyi olan bir çizgiyi doğrudan silmek,
> o çizgiye dayanan bütün yüzeylerin sınırını bozar — komşu geometri dağılır.
> Bu komut doğru sırayı uygular: önce aradaki yüzeyi siler, sonra çizgiyi.
> Aradaki yüzey gittiği için çizgi artık 2 eş düzlemli yüzey arasında kalır ve
> temiz şekilde silinebilir.

Atlananları da raporlar (gerçek köşeler, eş düzlemli çifti olmayanlar vb.),
böylece neyin neden kaldığını görürsün.

### Bilerek dokunulmayan durumlar

- **Farklı yükseklikteki bitişik duvarlar**: bölücü yüzey silinir, ama tepedeki
  içbükey köşe çizgisi (yatay üst yüzey ile dikey yan yüzey arasındaki) korunur.
  Doğru olan da budur.
- **Çakışık yüzeyler**: aynı yerde üst üste duran iki yüzey (ör. bir kutunun
  alt yüzü ile üzerinde durduğu döşemenin üst yüzü) birleştirilmez.
- **Ters yönlü eş düzlem yüzeyler**: aynı düzlemde ama biri ön biri arka
  bakıyorsa birleştirilmez. Önce `Sağ tık → Orient Faces`.
- **Ayrı gruplar/bileşenler**: farklı gruplardaki geometri birbirine
  kaynaşmaz — bu SketchUp'ın kuralı. Önce `Explode` gerekir.

## Teşhis

Bir çizgi silinmediğinde nedenini tahmin etmek yerine sorabilirsin. İki komut
var, ikisinin raporu da `Window → Ruby Console`'a yazılır (kopyalamak için).

### Teşhis: Kalan Çizgi Raporu

Seçim yoksa tüm bağlamdaki **bütün** çizgileri tarar ve "neden duruyor"
kategorilerine ayırıp sayar:

```
Gerçek köşe (farklı düzlem).................  980   -> normal, kalmalı
Serbest kenar (tek yüzey)...................   12
Aynı düzlem ama TERS YÖN....................   47   -> Orient Faces
Eş düzlemli, malzeme/tag farklı.............    0   -> ayarı kapat
Silinmeliydi (eş düzlemli, uygun)...........    0   -> temizliği çalıştır
3+ yüzeyli (arada iç bölücü var)............  195   -> birleştirme gerekir
```

Ayrıca 3+ yüzeyli çizgilerdeki yüzeylerin iç bölücü testini **hangi şartta**
kaybettiğini de sayar. Sonunda şüpheli çizgileri seçmeyi teklif eder, böylece
modelde nerede olduklarını görürsün.

### Teşhis: Seçili Çizgi

Tek bir çizgiyi enine boyuna inceler: kaç yüzeyi var, her yüzeyin normali /
malzemesi / tag'i / bağlamı, yüzey çiftleri eş düzlemli mi, kenar temizliğinin
neden çalışmadığı, her yüzeyin iç bölücü testini hangi kenarda kaybettiği.

Birden çok çizgi seçiliyse rastgele ilkini değil, **şüpheli olan ilkini**
inceler (gerçek köşeleri ve serbest kenarları atlar). Hiçbiri şüpheli değilse
bunu söyler.

## Notlar

- Yüzey oluşmuyorsa: döngü kapalı değildir (küçük bir boşluk vardır), kenarlar
  aynı düzlemde değildir, ya da farklı grup/bileşenlerin içindedir.
- Aynı bileşen tanımı birden çok yerleştirilmişse tanım bir kez işlenir;
  sonuç tüm kopyalarda görünür.

## Dosyalar

```
src/
  mf_make_faces.rb        # eklenti kaydı (SketchupExtension) + sürüm numarası
  mf_make_faces/
    main.rb               # tüm kod
    icons/*.png           # araç çubuğu ikonları
dist/
  MakeFaces-<sürüm>.rbz   # kurulum paketi
build.ps1                 # src/ içinden .rbz üretir
```

## Yeni sürüm paketlemek

1. `src/mf_make_faces.rb` içinde `PLUGIN_VERSION` değerini artır
2. Paketi üret:

```bash
powershell -ExecutionPolicy Bypass -File build.ps1
```

3. `dist/` altındaki eski `.rbz` dosyasını sil, yenisini commit et
