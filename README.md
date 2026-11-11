# AtlasRoute

Savaş hocanın **Atlas** algoritmasından ([savastakan/atlas](https://github.com/savastakan/atlas), `1748ccf`) yola çıkan, World of Warcraft için yol planlayıcı. Yürüme, uçuş noktaları (flight path), gemi, zeplin, Deeprun Tram, büyücü ışınlanmaları ve hearthstone'u bir arada hesaba katar.

İki problem çözülüyor:

1. **Görev turu.** Görev kütüğündeki bütün durakları (görevi alma → hedefler → teslim) en kısa sürede dolaşan sıra.
2. **Kenar kapsama (Atlas'ın kendi problemi).** Bir grafın gerekli bütün kenarlarından en az bir kez geçen en ucuz yürüyüş. Atlas'ın kendisi, ağırlıklı ve ışınlanmalı genellemesi, Kırsal Postacı (Rural Postman) kurgusu ve kesin Çinli Postacı (Chinese Postman) çözümü karşılaştırıldı.

Kodun tamamı Lua 5.1'dir (WoW'un Lua sürümü). `core/` ve `data/` oyunun içinde de dışarıda (LuaJIT) da aynen çalışır; testler ve ölçümler dışarıda, aynı dosyalarla yapıldı.

## Atlas nedir, ne değildir

Depodaki Atlas bir WoW eklentisi değildir. Yaklaşık 250 satırlık bir Java programıdır; bir sonlu durum makinesinin (FSM) bütün geçişlerini tek bir test dizisiyle kapsamak için sezgisel bir algoritmadır. Her turda son kenardan DFS ardıl-sıralaması (post-order) çıkarır. Bu sıra üzerinde, henüz yürüyüşte olmayan her kenara 1 puan veren en uzun yol programlamasını çalıştırır ve en iyi zinciri yürüyüşe ekler. Kenar ağırlıklarını kullanmaz.

`core/atlas.lua` bu kodun birebir Lua karşılığıdır. Java'nın `HashSet<Integer>` dolaşma sırası da taklit edildi, çünkü sonuç bu sıraya bağlı. 58 FSM üzerinde (6 durumlu `bbtas`'tan 200 durum × 10 girdiye, 2000 kenara kadar) Java ile aynı test dizisini üretiyor (`tools/compare_java.lua`).

Karşılaştırma sırasında ortaya çıkan iki bulgu:

- **Son kenar düşüyor.** `longestPath` her tura `path.removeLast()` ile başlıyor; son turda o kenarı geri koymadan dönüyor. Bu yüzden Atlas denediğimiz hiçbir grafı tam kapsamadı: her seferinde tam olarak bir kenar eksik kaldı (30 kenarlı grafta 29). `Atlas.run(g, true)` bu kenarı geri koyar ve kapsama %100 olur. Bu davranış testlerde sabitlendi.
- **Uzunluk optimumdan uzaklaşıyor.** Kesin açık Çinli Postacı çözümüne göre Atlas'ın yürüyüşü 30 kenarda 1,14 kat, 2000 kenarda 2,74 kat uzun. Bu uygulamada çalışma süresi de kesin çözümden fazla: 2000 kenarda 281 ms'ye karşı 23 ms (LuaJIT; Java'da ölçülmedi).

## Model

Dünya çok kipli bir graftır (`core/world.lua`). Bütün maliyetler saniye cinsindendir.

| Kenar | Anlamı |
|---|---|
| `walk` | aynı kıtadaki en yakın 4 yer (artı elle eklenen geçitler); mesafe × 1,3 / yer hızı |
| `board` / `fly` / `land` | her uçuş ustası iki düğümdür, yer ve hava. Binmek 5 sn; arka arkaya uçuşlar tek uçuş sayılır, oyundaki taksi gibi |
| `boat`, `zeppelin`, `tram`, `portal` | yolculuk + beklenen bekleme (kalkış aralığının yarısı) |
| büyücü ışınlanmaları | yerdeki her düğümden hedef şehre, 10 sn; yalnızca `MAGE`, kendi fraksiyonu |
| hearthstone | yerdeki her düğümden bağlanan yere; plan başına **bir** kez |

Fraksiyon kısıtları kenar üzerindedir: Horde, Alliance uçuş ustasına binemez, Alliance gemisini kullanamaz. Uçarken ışınlanma yapılamaz.

**Hearthstone durumu.** Yol bulucu (`core/router.lua`), *(düğüm, hearthstone kullanılabilir mi)* durumları üzerinde Dijkstra çalıştırır. Böylece taşın tek kullanımlık olması tam olarak modellenir ve hangi bacakta kullanılacağına arama karar verir.

## Algoritmalar

### Görev turu (`core/tour.lua`)

1. Başlangıçtan ve her duraktan bir Dijkstra çalışır. Sonuç iki matristir: `noH[i][j]` hearthstone'suz, `useH[i][j]` hearthstone kullanarak en hızlı süre.
2. Sıralama:
   - **kesin:** *(ziyaret edilen küme, son durak, hearthstone kullanıldı mı)* üzerinde Held-Karp dinamik programlaması. Bir durak ancak önkoşulları kümedeyken eklenir (alma < hedefler < teslim). Karmaşıklık O(2ⁿ·n²). Varsayılan sınır 13 duraktır: JIT kapalı LuaJIT'te (WoW'a yakın) 13 durak 0,11 sn, 16 durak 1,5 sn sürüyor.
   - **sezgisel:** önkoşula uyan en yakın durakla başlar, sonra Or-opt uygular (1–3 duraklık bir bloğu başka yere taşıma) ve iyileşme kalmayana kadar sürdürür.
3. Oyunda arama bir coroutine'de, her karede bir dilim çalışır; büyük bir arama oyunu dondurmaz.

### Kenar kapsama (`core/coverage.lua`, `core/cpp.lua`)

- **Ağırlıklı Atlas.** Atlas'ın tur yapısı korunur, üç değişiklikle:
  1. Puan: `yeni gerekli kenar × BÜYÜK − ağırlık`, yani önce en çok yeni kenar, eşitlikte en ucuzu.
  2. Yalnızca gerekli kenarlar kapsanır; Kırsal Postacı problemidir.
  3. Atlas'ın takılıp durduğu yerde yürüyüş, kalan en yakın kenara en ucuz yoldan, gerekirse ışınlanarak atlar.

  Ayrıca güçlü bağlı bileşenler hesaplanır. Başka bir bileşene geçmeye ancak geride erişilemez kalacak kapsanmamış kenar yoksa izin verilir; bu kural yokken bir testte yürüyüş çıkmaz bir düğüme girip 18 kenardan 11'inde kalıyordu.
- **Kırsal Postacı kurgusu.** Gerekli kenarların parçaları gidiş-dönüş maliyetli minimum yayılan ağaçla birleştirilir. Derece dengesizliği minimum maliyetli akışla kapatılır, sonra Euler yürüyüşü çıkarılır. Gerekli kenarlar zaten bağlıysa sonuç kesindir.
- **Açık yönlü Çinli Postacı.** Minimum maliyetli akış (potansiyelli ardışık en kısa yollar) ve Hierholzer. Küçük graflarda kaba kuvvetle aynı sonucu verdiği test edildi.

## Sonuçlar

`luajit tools/bench.lua` ile üretildi (5 rastgele güçlü bağlı FSM'nin ortalaması). *Atlas*, Java ile birebir aynı davranan sürümdür.

**Birim ağırlık, yürüyüş uzunluğu / optimum (Çinli Postacı):**

| durum × girdi | kenar | Atlas | Atlas kapsama | Ağırlıklı Atlas | Atlas ms | ağırlıklı ms | Çinli Postacı ms |
|---|---|---|---|---|---|---|---|
| 10 × 3 | 30 | 1,142 | %96,7 | 1,059 | 1 | 1 | 1 |
| 10 × 8 | 80 | 1,167 | %98,8 | 1,046 | 1 | 1 | 0 |
| 50 × 4 | 200 | 1,608 | %99,5 | 1,264 | 3 | 4 | 2 |
| 50 × 10 | 500 | 1,602 | %99,8 | 1,131 | 16 | 19 | 2 |
| 100 × 10 | 1000 | 2,078 | %99,9 | 1,251 | 72 | 86 | 6 |
| 200 × 10 | 2000 | 2,740 | %99,95 | 1,343 | 281 | 332 | 23 |

**Ağırlıklar 1–20, toplam ağırlık / optimum:** Atlas 1,15–2,13; ağırlıklı Atlas 1,12–1,35.

**Oyun haritası, her uçuş bağlantısından iki yönde de geçmek (saniye):**

| karakter | bağlantı | Atlas | ağırlıklı Atlas | Kırsal Postacı | alt sınır |
|---|---|---|---|---|---|
| Alliance | 68 | 40 749 | 9 751 | 5 812 | 5 137 |
| Alliance büyücü | 68 | 40 749 | 9 751 | 5 419 | 5 137 |
| Horde | 64 | 38 999 | 8 667 | 4 470 | 3 920 |
| Horde büyücü | 64 | 38 999 | 8 667 | 3 989 | 3 920 |

Alt sınır, gerekli kenarların ağırlıkları toplamıdır. Ağırlıklı Atlas'ta ışınlanmalar sonucu değiştirmedi, çünkü yalnızca takılınca atlamak için kullanılıyor ve bu haritada yürüyüş hiç takılmadı. Kırsal Postacı kurgusu ışınlanmaları akışın içinde kullanıyor; büyücüde süre düşüyor.

**Görev turu, sezgisel ile kesin (rastgele görev alt kümeleri, 81 deneme):** 11 durağa kadar her denemede aynı sonuç. 12 durakta ortalama fark %0,18 (en kötü %1,06), 13 durakta %0,73 (en kötü %5,36). İkisi de 4 ms'nin altında.

## Oyuna kurulum

Hedef sürüm **World of Warcraft: Forever**'dır (Classic tabanlı, 4 Kasım 2026'da çıktı). Haritadaki veriler özgün Classic ağıdır. Forever'ın yeni bölgeleri ve yolları henüz eklenmedi: The Riverglades uçuş noktaları, yeni gemi hatları, Skyborne başlangıcı Zephras Isle ve Valanaar zeplinleri. Kaynaklar bunlarda birbiriyle çelişiyor, oyundan doğrulanınca `data/world_data.lua`'ya eklenebilir. Forever'da uçan binek olmadığı için modelde de yok.

1. `AtlasRoute/` klasörünü kullandığınız sürümün `World of Warcraft/<sürüm klasörü>/Interface/AddOns/` dizinine kopyalayın.
2. `AtlasRoute.toc` içindeki `## Interface:` numarası istemcinizinkiyle aynı olmalı. Oyunda `/dump select(4, GetBuildInfo())` yazarak öğrenin ve dosyadaki `11507` yerine onu koyun. Bu numara denenmedi.
3. Karakter seçme ekranında *AddOns* menüsünden etkinleştirin.

Komutlar (`/ar` ya da `/atlasroute`):

```
/ar demo                                   fraksiyonunuzun örnek görev kütüğü
/ar quest Menethil > Raptor Grounds > Menethil    al > hedef(ler, virgülle) > teslim
/ar quest > > Theramore                    zaten alınmış teslim görevi
/ar list | clear | remove <n>
/ar plan                                   bulunduğunuz yerden tur
/ar route Astranaar                        tek bir yere en hızlı yol
/ar from <yer> | speed <yd/sn> | places [metin]
```

Fraksiyon (`UnitFactionGroup`), sınıf (`UnitClass`), hearthstone'un bağlı olduğu yer (`GetBindLocation`) ve bekleme süresi (`GetItemCooldown(6948)`) oyundan okunur. Bulunduğunuz yer bölge adından eşlenir.

**Doğrulanmayanlar.** Eklenti gerçek oyun istemcisinde çalıştırılmadı. WoW API'si taklit edilerek (`tests/run.lua`, son test) komutlar, profil okuma ve coroutine'le planlama sınandı. Classic istemcisi görev koordinatı vermediği için görevler elle girilir.

## Veri

`data/world_data.lua` elle kuruldu: Doğu Krallıkları ve Kalimdor'dan 51 yer, 40 uçuş ustası, 65 uçuş bağlantısı, gemi, zeplin, tram ve büyücü ışınlanmaları. Koordinatlar bölge yerleşiminden **yaklaşık** olarak yerleştirildi, oyun dosyalarından okunmadı. Yolculuk ve bekleme süreleri de tahmindir. Algoritmalar bu sayılara bağlı değildir; yalnızca örnek sonuçlar bağlıdır. Dosya değiştirilerek başka bir veriyle plan yapılabilir. `data/quest_data.lua` bu bölgelerdeki görevlere benzeyen örnek kütüklerdir; adlar oyundaki başlıkların birebir aynısı değildir.

## Çalıştırma

LuaJIT gerekir (Lua 5.1 uyumlu, `bit` kütüphanesiyle). Lua 5.4 ile çalışmaz.

```bash
luajit tests/run.lua
```

```bash
luajit tools/bench.lua all
```

```bash
luajit tools/plan.lua alliance ironforge
```

```bash
luajit tools/plan.lua horde undercity mage
```

Java ile karşılaştırma (Java derleyicisi gerekir):

```bash
javac -d /tmp/jref reference/java/*.java && luajit tools/compare_java.lua /tmp/jref reference/fsm/bbtas.kiss2.fsm
```

Rastgele FSM üretmek: `luajit tools/gen_fsm.lua <durum> <girdi> <çıktı> <tohum> [strong]`. Atlas'ın kullandığı `fsm-gen-fsm` aracı depoda yok; bu onun yerine yazıldı.

## Dosyalar

```
AtlasRoute/            eklenti (WoW'a kopyalanacak klasör)
  core/heap.lua        ikili yığın
  core/fsm.lua         Atlas'ın graf yapısı, .fsm okuyucu, Java HashSet sırası
  core/atlas.lua       Atlas'ın birebir Lua karşılığı
  core/world.lua       çok kipli dünya grafı
  core/router.lua      (düğüm, hearthstone) durumlu Dijkstra
  core/tour.lua        görev turu: Held-Karp ve Or-opt
  core/cpp.lua         min-cost flow, açık Çinli Postacı
  core/coverage.lua    ağırlıklı Atlas, Kırsal Postacı kurgusu
  data/                harita ve örnek görevler
  ui/addon.lua         oyun içi komutlar
reference/             hocanın Java kodu (değiştirilmedi) + RefMain.java
tests/                 testler ve Java çıktıları
tools/                 yükleyici, ölçüm, Java karşılaştırması, FSM üretici, komut satırı demosu
```
