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
| `walk` | aynı bölgedeki en yakın 4 yer (artı elle eklenen geçitler); mesafe × 1,3 / yer hızı. Mount Hyjal, Moonglade, Shen'dralas ve Feathermoon'un adası ayrı bölgedir; yalnızca geçitlerinden girilir |
| `board` / `fly` / `land` | her uçuş ustası iki düğümdür, yer ve hava. Binmek 5 sn; arka arkaya uçuşlar tek uçuş sayılır, oyundaki taksi gibi. Frequent Flier ile uçuş %20 hızlı |
| `boat`, `zeppelin`, `skyship`, `tram`, `portal` | yolculuk + beklenen bekleme (kalkış aralığının yarısı); tek yönlü hatlar olabilir (Menethil gemi döngüsü) |
| sınırsız ışınlanmalar | yerdeki her düğümden hedefe, 10 sn: büyücü şehir ışınlanmaları, druid Teleport: Moonglade |
| tek kullanımlık ışınlanmalar | hearthstone, şaman Astral Recall (bağlanılan yere), Dimensional Ripper - Everlook, Ultrasafe Transporter: Gadgetzan; her biri plan başına **bir** kez |

Kısıtlar kenarın üzerindedir: fraksiyon, sınıf (druid uçuş ustası Nighthaven), eşya (mühendislik aletleri çantada olmalı), büyü (oyunda `IsSpellKnown`) ve yalnızca betada görülmüş olma (`unconfirmed`). Uçarken ışınlanma yapılamaz.

**Tek kullanımlık ışınlanmalar.** Hearthstone ve mühendislik aletlerinin bekleme süreleri bir plandan uzun olduğu için her biri bir kez kullanılabilir sayılır. Astral Recall'ın bekleme süresi daha kısadır; uzun bir planda ikinci kez kullanılabilecekken model onu da bir kez sayar. Bu, planı hiçbir zaman olduğundan hızlı göstermez, en kötü ihtimalle bir fırsatı kaçırır. Yol bulucu (`core/router.lua`), *(düğüm, harcanmış ışınlanmalar kümesi)* durumları üzerinde Dijkstra çalıştırır; K ışınlanma için düğüm başına 2^K durum vardır. Böylece hangisinin hangi bacakta kullanılacağına arama karar verir.

## Algoritmalar

### Görev turu (`core/tour.lua`)

1. Başlangıçtan ve her duraktan bütün ışınlanmalar elde iken bir Dijkstra çalışır. Sonuç `D[i][j][C]` tablosudur: i'den j'ye tam olarak C kümesindeki ışınlanmaları harcayan en hızlı süre.
2. Sıralama:
   - **kesin:** *(ziyaret edilen küme, son durak, harcanmış ışınlanmalar)* üzerinde Held-Karp dinamik programlaması. Bir durak ancak önkoşulları kümedeyken eklenir (alma < hedefler < teslim), her bacak henüz harcanmamış herhangi bir C kümesini harcayabilir. Karmaşıklık O(2ⁿ·n²·3ᴷ). Kesin arama, bu sayı 13 durak + 1 ışınlanma düzeyini aşmadıkça kullanılır. JIT kapalı LuaJIT'te (WoW'a yakın) bu düzey yaklaşık 0,1 sn sürüyor.
   - **sezgisel:** önkoşula uyan en yakın durakla başlar, sonra Or-opt uygular (1–3 duraklık bir bloğu başka yere taşıma) ve iyileşme kalmayana kadar sürdürür. Sabit bir sıra için ışınlanmaların en iyi dağılımı bacaklar üzerinde küçük bir DP ile kesin bulunur.
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
| Alliance | 86 | 49 308 | 9 718 | 6 736 | 6 061 |
| Alliance büyücü | 86 | 49 308 | 9 718 | 6 096 | 6 061 |
| Horde | 84 | 46 193 | 7 994 | 5 648 | 5 098 |
| Horde büyücü | 84 | 46 193 | 7 994 | 5 232 | 5 098 |

Alt sınır, gerekli kenarların ağırlıkları toplamıdır. Ağırlıklı Atlas'ta ışınlanmalar sonucu değiştirmedi, çünkü yalnızca takılınca atlamak için kullanılıyor ve bu haritada yürüyüş hiç takılmadı. Kırsal Postacı kurgusu ışınlanmaları akışın içinde kullanıyor; büyücüde süre düşüyor.

**Görev turu, sezgisel ile kesin (rastgele görev alt kümeleri, 84 deneme):** 10 durağa kadar her denemede aynı sonuç. 11–13 durakta ortalama fark %0,18–0,57, en kötüsü %3,99. İkisi de 5 ms'nin altında.

## Tanıtım sayfası

**Wayfarer's Atlas** (`web/AtlasRoute.html`) oyuna gerek kalmadan planlayıcıyı haritada gösterir. Tek bir dosyadır, tarayıcıda açmak yeter (ilk açılışta internet gerekir: wasmoon Lua VM'i cdn.jsdelivr.net'ten, yazı tipleri Google Fonts'tan gelir).

- Sayfadaki bütün sayılar eklentinin kendi Lua kodundan gelir. `core/` ve `data/` dosyaları, köprü `web/bridge.lua` ile birlikte sayfanın içine gömülür ve tarayıcıda wasmoon (Lua 5.4, WebAssembly) ile, bir Web Worker'da çalışır. Lua 5.4'te `bit` kütüphanesi olmadığı için sayfa onu `&`, `|`, `<<` ile tanımlar; çıktılar LuaJIT'teki komut satırı demosuyla aynıdır.
- **Plan a journey:** fraksiyon, sınıf, başlangıç, hearthstone, binek, mühendislik aletleri, Frequent Flier ve beta yolları seçilir; görevler işaretlenir. Rota haritaya bacak bacak mürekkeple çizilir, her kip kendi çizgisiyle.
- **Ride every flight path:** Atlas (yazıldığı gibi), ağırlıklı Atlas ve Kırsal Postacı aynı haritada karşılaştırılır ve çizilir.
- **Yolcu:** haritada sınıfı gösteren küçük bir figür yolculuğu yapar (savaşçı miğfer ve kılıç, büyücü sivri şapka ve asa, druid yaprak taç, şaman boynuzlu miğfer ve totem; pelerin fraksiyon renginde). Her yolculuk biçiminin kendi figürü var: yaya, at (Horde'da kurt), uçuşta grifon (Horde'da wyvern), gemi, zeplin, skyship, tram vagonu; ışınlanma ve hearthstone'da figür bir girdapla kaybolup varış yerinde belirir. Kamera figürü izler, kum saati yolculuk süresini sayar, *Skip* sona atlar, görev olayları ("Quest accepted: …") sohbet penceresine düşer.
- **Tıkla ve yolculuk et:** haritada bir yere tıklanınca rota kartı açılır; *Travel* ile figür oraya gider, bulunulan yer güncellenir, kullanılan hearthstone bekleme süresine girer.
- `AtlasRoute.html#sprites` bütün figürleri bütün sınıflar ve iki fraksiyon için bir sayfada gösterir (çizimleri denetlemek için).

Kaynak `web/template.html`'dir; değiştirdikten sonra sayfayı yeniden üretin:

```bash
luajit tools/build_web.lua
```

claude.ai'da yayımlanacak kopya (sarmalayıcı etiketler olmadan; `glue.wasm` sayfanın yanında yayımlanır, çünkü orada CDN'den yalnızca betik yüklenebilir):

```bash
luajit tools/build_web.lua artifact <klasör>
```

## Oyuna kurulum

Hedef sürüm **World of Warcraft: Forever**'dır (Classic tabanlı, 4 Kasım 2026'da çıktı). Forever'da uçan binek yoktur, modelde de yok. Eklenen Forever yolları ve kaynakları için aşağıdaki *Veri* bölümüne bakın.

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
/ar flier on|off                           Frequent Flier (+%20 uçuş hızı)
/ar beta on|off                            yalnızca betada görülen yolları da kullan
```

Fraksiyon (`UnitFactionGroup`), sınıf (`UnitClass`), hearthstone'un bağlı olduğu yer (`GetBindLocation`) ve bekleme süresi (`GetItemCooldown(6948)`) oyundan okunur. Bulunduğunuz yer bölge adından eşlenir.

**Doğrulanmayanlar.** Eklenti gerçek oyun istemcisinde çalıştırılmadı. WoW API'si taklit edilerek (`tests/run.lua`, son test) komutlar, profil okuma ve coroutine'le planlama sınandı. Classic istemcisi görev koordinatı vermediği için görevler elle girilir.

## Veri

`data/world_data.lua` elle kuruldu: 67 yer, 50 uçuş ustası, 84 uçuş bağlantısı, 18 gemi/zeplin/skyship/tram/portal hattı, 11 ışınlanma.

Forever'ın eklemeleri dört rehberden derlendi; çeliştikleri yerde oyunun canlı istemcisinden okuyan iki kaynak esas alındı (wowforever.be, classicwowforever.com):

- **The Riverglades:** Farholde Keep (Alliance; Lakeshire, Thelsamar, Morgan's Vigil), Rog'mar (Horde; Stonard, Hammerfall, Kargath, Flame Crest), Powderfuse Port ↔ Steamwheedle Port gemisi (iki fraksiyon).
- **Mount Hyjal:** Tainted Foothills (Everlook, Summit of Eternity), Winterspring'den Darkwhisper Gorge ile giriş. Betada bildirilen 60. seviye kapısı modellenmedi.
- **Gemiler:** Stormwind Harbor → Auberdine; Menethil → Southshore → Auberdine → Menethil tek yönlü döngü (wowforever.be doğrudan hat diyor, canlı istemciyi okuyan diğer kaynak döngü diyor).
- **Skyborne:** Valanaar (Zephras Isle) → Dalaran (iki fraksiyon) ve → Skywatcher Plateau (Horde), yaklaşık 5 dakikada bir.
- **Shen'dralas:** Desolace'ın güneyindeki Valley of Bones'tan yürüyerek; uçuş ustası yok.
- **Frequent Flier** (Legacy avantajı): +%20 uçuş hızı, isteğe bağlı.
- **Yalnızca betada görülenler** (`unconfirmed`, varsayılan kapalı): Dalaran → Stormwind portalı, büyücü Teleport: Dalaran, Powderfuse uçuş ustası ve Farholde bağlantısı.
- Forever'a özgü olmayan ama eksik olan Classic parçaları da eklendi: Burning Steppes ve Desolace uçuş ustaları, Nighthaven (yalnızca druid), Feathermoon feribotu, druid ve şaman ışınlanmaları, iki mühendislik aleti. Bu yeni parçaların bağlantıları da haritanın geri kalanı gibi yaklaşıktır.

Gemi ve skyship yolculuk süreleri hiçbir kaynakta yok; tahmindir. Tidegear Coast uçuş noktasının hiç rotası olmadığı için eklenmedi; açılış gecesinin geçici portalları da eklenmedi. Koordinatlar bölge yerleşiminden **yaklaşık** olarak yerleştirildi, oyun dosyalarından okunmadı. Yolculuk ve bekleme süreleri de tahmindir. Algoritmalar bu sayılara bağlı değildir; yalnızca örnek sonuçlar bağlıdır. Dosya değiştirilerek başka bir veriyle plan yapılabilir. `data/quest_data.lua` bu bölgelerdeki görevlere benzeyen örnek kütüklerdir; adlar oyundaki başlıkların birebir aynısı değildir.

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

```bash
luajit tools/plan.lua horde valanaar shaman engineer flier
```

Bayraklar: `mage`, `druid`, `shaman`, `engineer` (iki mühendislik aleti çantada), `nohearth`, `flier`, `beta`.

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
