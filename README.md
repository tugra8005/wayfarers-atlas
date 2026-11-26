# AtlasRoute

**Yazarlar:** Alparslan Tuğra ŞAHİN, Abdülbaki BAYIR, Seyyid Abdülbaki BOZKURT

World of Warcraft: Forever için, Savaş Takan'ın **Atlas** algoritmasıyla ([savastakan/atlas](https://github.com/savastakan/atlas), `1748ccf`) çalışan yol planlayıcı eklenti. Yürüme, uçuş noktaları (flight path), gemi, zeplin, skyship, Deeprun Tram, portallar, büyücü ve druid ışınlanmaları, hearthstone ve mühendislik aletleri tek bir grafın kenarlarıdır; bütün planları Atlas yapar:

1. **Görev turu.** Görev kütüğündeki bütün durakları (görevi alma → hedefler → teslim) dolaşan yol.
2. **Tek rota.** Bulunulan yerden bir yere gitmenin yolu.
3. **Bütün uçuş ağı.** Karakterin kullanabildiği her uçuş bağlantısından geçen yol; Atlas'ın asıl problemi olan "her kenarı kapsa".

Kod Lua 5.1'dir (WoW'un Lua sürümü). `core/` ve `data/` oyunun içinde de dışarıda (LuaJIT) da aynen çalışır; testler ve ölçümler dışarıda, aynı dosyalarla yapıldı. Eklenti ve tanıtım sayfası yalnızca Atlas'ı kullanır. Başka yöntemler (Dijkstra, Held-Karp, Çinli ve Kırsal Postacı) yalnızca `benchmark/` klasöründe, Atlas'ın sonuçlarını ölçmek için durur.

## Atlas

Atlas bir grafın bütün kenarlarını düşük maliyetle tek yürüyüşte dolaşmak için yazılmış bir sezgiseldir. İlk hâli (2020) sonlu durum makinelerinden test dizisi üretmek içindir; yazarın 2026 tarihli deposunun başlığı onu bir yay rotalama (arc routing) sezgiseli olarak tanımlar. Her turda:

1. yürüyüşün son kenarından erişilen kenarları DFS ardıl-sıralamasıyla (post-order) dizer,
2. bu sıra üzerinde en uzun yol dinamik programlamasıyla zincirleri puanlar,
3. en iyi zinciri yürüyüşe ekler; gerekli kenar kalmayana kadar sürer.

`core/atlas.lua` Java kodunun birebir Lua karşılığıdır (Java'nın `HashSet<Integer>` dolaşma sırası dahil). 58 FSM üzerinde (6 durumlu `bbtas`'tan 2000 kenarlı makinelere) Java ile aynı test dizisini üretir (`tools/compare_java.lua`). Java kodu son turda yürüyüşün son kenarını yürüyüşe eklemeden döner; `Atlas.run(g, true)` ve planlayıcı bu kenarı tutar.

## Tasarım: sınıflar, SOLID, desenler

Diyagramlar: [`docs/AtlasRoute-Diyagramlar.pdf`](docs/AtlasRoute-Diyagramlar.pdf) (A4, 12 sayfa) ve GitHub'da çizilen hâli [`docs/diagrams/`](docs/diagrams/README.md): paket görünümü, üç sınıf diyagramı (dünya modeli; graf ve Atlas çözücü; planlama, cephe ve arayüzler), üç kullanım durumu diyagramı (Forever eklentisi, retail eklentisi, tanıtım sayfası) ve dört sıra diyagramı (Forever'da `/ar plan`, bir Atlas turu, retail'de `/ar plan` ve bir görev olayı, tanıtım sayfasında plan). Kaynaklar `docs/diagrams/*.mmd` (Mermaid). `tests/design.lua` diyagramları kodla karşılaştırır: sınıf diyagramlarındaki her sınıf, yöntem ve kalıtım/arayüz oku kodda var mı, koddaki her sınıf bir diyagramda mı, sıra diyagramlarındaki her çağrı çağrılan sınıfta ya da dosyada tanımlı mı, kullanım durumu diyagramları her eklentinin `/ar` komutlarını eksiksiz gösteriyor mu; desenlerin davranışını da sınar.

Lua'da sınıf ve arayüz yoktur; `core/oop.lua` ikisini ekler (`Class`, `Interface`, `implements`). Bir sınıf arayüzünün bir yöntemini eksik bırakırsa eklenti yüklenirken hata verir.

| Desen | Sınıflar | Ne için |
|---|---|---|
| Strategy | `TravelMode` (`FixedMode`, `WalkMode`, `FlightMode`), `ExplorationOrder` (`CheapestFirst`, `DearestFirst`, `InsertionOrder`, `Shuffled`), `ScoringRule` (`SingleTarget`, `WholeChain`), `Goal` (`QuestTourGoal`, `RouteGoal`, `FlightNetworkGoal`, `FsmCoverageGoal`) | süre hesabı, keşif sırası, zincir puanı, planın türü |
| Template Method | `AtlasSolver.solve`: `explore`, `score`, `choose`, `append` | Atlas turu |
| Observer | `Observable`, `AtlasSolver` ("round", "covered") | oyun her turda kareyi bırakır |
| Factory | `TravelGraphFactory`, `ExplorationOrders` | karakterin grafı, 16 keşif sırası |
| Adapter | `ForeverMap`, `RetailSnapshot` (`WorldSource`), `FsmGraphAdapter` | iki veri kaynağı tek bir `World`'e; test makineleri `TravelGraph`'a |
| Facade | `AtlasPlan` | arayüzlerin kullandığı tek giriş |
| Command | `Command`, `CommandRegistry` | `/ar` komutları (iki eklenti de) |
| Registry | `TravelModes` | kip adından stratejiye |

SOLID: her sınıfın tek işi vardır (izin `Gated`'da, süre `TravelMode`'da, algoritma `AtlasSolver`'da, ne kapsanacağı `Goal`'de); yeni yolculuk biçimi, keşif sırası, plan türü, komut ya da veri kaynağı eklemek `AtlasSolver`'ı değiştirmez; stratejiler birbirinin yerine geçer (testle); arayüzler küçüktür (1–3 yöntem); çözücü yalnızca soyutlamalara bağlıdır, oyunu ve WoW API'sini bilmez.

## Atlas ile planlama (`core/atlasplan.lua`)

### Graf

Dünya çok kipli bir graftır (`core/world.lua`); Atlas bu grafın üzerinde çalışır. Bütün ağırlıklar saniye cinsindendir.

| Kenar | Anlamı |
|---|---|
| `walk` | aynı bölgedeki en yakın 4 yer (artı elle eklenen geçitler); mesafe × 1,3 / yer hızı. Mount Hyjal, Moonglade, Shen'dralas ve Feathermoon'un adası ayrı bölgedir; yalnızca geçitlerinden girilir |
| `board` / `fly` / `land` | her uçuş ustası iki düğümdür, yer ve hava. Binmek 5 sn; arka arkaya uçuşlar tek uçuş sayılır, oyundaki taksi gibi. Frequent Flier ile uçuş %20 hızlı |
| `boat`, `zeppelin`, `skyship`, `tram`, `portal` | yolculuk + beklenen bekleme (kalkış aralığının yarısı); tek yönlü hatlar olabilir (Menethil gemi döngüsü) |
| sınırsız ışınlanmalar | yerdeki her düğümden hedefe birer kenar, 10 sn: büyücü şehir ışınlanmaları, druid Teleport: Moonglade |
| tek kullanımlık ışınlanmalar | hearthstone, şaman Astral Recall (bağlanılan yere), Dimensional Ripper - Everlook, Ultrasafe Transporter: Gadgetzan; yine yerdeki her düğümden birer kenar, ama biri kullanılınca o ışınlanmanın bütün kenarları graftan çıkar: plan başına **bir** kez |

Kısıtlar kenarın üzerindedir: fraksiyon, sınıf (druid uçuş ustası Nighthaven), eşya (mühendislik aletleri çantada olmalı), büyü (oyunda `IsSpellKnown`) ve yalnızca betada görülmüş olma (`unconfirmed`). Uçarken ışınlanma yapılamaz.

### Gerekli kenarlar

Planın yapması gereken her şey bir **gerekli kenardır**; Atlas'ın işi hepsini tek yürüyüşte kapsamaktır.

- **Görev turu:** her durak (alma, hedef, teslim) kendi yerinde bir döngü kenarıdır; ağırlığı orada geçen süredir. Bir durak, önkoşulları kapsanmadan yeni sayılmaz: alma → hedefler → teslim sırası ve görev zincirleri (`requires`, ör. Raising Spirits ancak Hammerfall teslim edildikten sonra) böyle korunur.
- **Tek rota:** varış yerinde ağırlığı 0 olan tek bir döngü kenarı.
- **Uçuş ağı:** karakterin kullanabildiği bütün uçuş bağlantıları (iki yönde).

### Atlas turu, ağırlıklarla

Java kodunda her kenar 1 adımdır ve zincir yeni kenar sayısıyla puanlanır. Burada her kenar süresiyle ağırlıklıdır ve zincirin puanı `yeni gerekli kenar × BÜYÜK − saniye` olur (BÜYÜK, bütün ağırlıkların toplamından büyük): önce yeni kenar, eşitlikte en kısa süre. Oyun için eklenenler:

- **Birden çok DFS sırası.** Dinamik programlama yalnızca DFS sırasında ileri giden kenarları izler. Her tur, aynı DFS + DP adımını 16 sırayla çalıştırır (önce ucuz kenar, önce pahalı kenar, ekleniş sırası ve sabit tohumlu karıştırmalar) ve en iyi zinciri seçer.
- **Turda bir hedef.** Her tur, ulaşılabilen her yeni gerekli kenara giden zinciri kendi süresiyle puanlar ve en iyisine gider (`opts.chain = true`, Java'daki gibi bütün zinciri ekler). Oyun haritasında bu, görev turlarını belirgin biçimde kısaltır (aşağıdaki sonuçlar).
- **Tek kullanımlık ışınlanmalar.** Hearthstone, Astral Recall ya da bir alet kullanılınca o ışınlanmanın bütün kenarları graftan çıkar. Astral Recall'ın bekleme süresi aslında daha kısadır; model onu da bir kez sayar, bu planı hiçbir zaman olduğundan hızlı göstermez.
- **Ulaşılamayan durak.** Karakterin hiçbir kenarla ulaşamadığı duraklar (ör. Horde için Darnassus) planda ayrıca bildirilir.

Oyunda her Atlas turundan sonra planlama bir sonraki kareye bırakılır (coroutine), 20 duraklık bir plan oyunu dondurmaz. JIT kapalı LuaJIT'te (WoW'a yakın) 20 duraklık tur 0,3–0,4 sn, tek rota 12 ms, bütün uçuş ağı 0,75 sn sürer.

## Sonuçlar

`luajit benchmark/bench.lua` ile. Karşılaştırma yöntemleri (`benchmark/`) eklentinin parçası değildir; yalnızca ölçüt olarak kullanıldı.

**Test FSM'leri, birim ağırlık; yürüyüş uzunluğu / optimum (açık Çinli Postacı), 5 makinenin ortalaması:**

| durum × girdi | kenar | Atlas (Java) | kapsama | Atlas (ağırlıklı, burada) | kapsama |
|---|---|---|---|---|---|
| 10 × 3 | 30 | 1,142 | %96,7 | 1,059 | %100 |
| 10 × 8 | 80 | 1,167 | %98,8 | 1,057 | %100 |
| 50 × 4 | 200 | 1,608 | %99,5 | 1,069 | %100 |
| 50 × 10 | 500 | 1,602 | %99,8 | 1,050 | %100 |
| 100 × 10 | 1000 | 2,078 | %99,9 | 1,057 | %100 |
| 200 × 10 | 2000 | 2,740 | %99,95 | 1,057 | %100 |

Ağırlıklar 1–20 iken toplam ağırlık / optimum: Java 1,15–2,13; burada 1,04–1,10. Büyük makinelerde turda bir hedef ve 16 DFS sırası yavaştır (2000 kenarda yaklaşık 1 dakika); oyun haritası küçük olduğu için orada sorun değildir.

**Oyun haritası, her uçuş bağlantısından iki yönde de geçmek (saniye):**

| karakter | bağlantı | Atlas (Java, her kenar 1 adım) | Atlas (ağırlıklı) | Kırsal Postacı | alt sınır |
|---|---|---|---|---|---|
| Alliance | 86 | 50 461 | 6 967 (1,15×) | 6 736 (1,11×) | 6 061 |
| Alliance büyücü | 86 | 307 766 | 6 785 (1,12×) | 6 348 (1,05×) | 6 061 |
| Horde | 84 | 47 386 | 6 438 (1,26×) | 5 648 (1,11×) | 5 098 |
| Horde büyücü | 84 | 208 601 | 6 084 (1,19×) | 5 434 (1,07×) | 5 098 |

Java sürümü uçuşların yanında bütün yürüyüş, gemi ve ışınlanma kenarlarını da kapsar ve her birini 1 adım sayar; süreleri o yüzden büyüktür. Alt sınır, her uçuşun bir kez uçulmasıdır.

**Görev turları, Atlas / kesin tur (Held-Karp), gerçek görevlerden rastgele alt kümeler, 121 deneme:** ortalama 1,00–1,34, en kötü 1,69. 20 duraklık tam kütüklerde Atlas, Or-opt sezgiselinin 1,18–1,35 katıdır (Alliance Ironforge'dan 73, Horde Undercity'den 59 dakika).

**Tek rotalar, Atlas / en kısa yol (Dijkstra), 12 yerin her çifti:** Alliance'ta 132 çiftin 87'si aynı, ortalama 1,077 (en kötü 2,01); Horde büyücüde 121 çiftin 100'ü aynı, ortalama 1,014.

## Tanıtım sayfası

**Wayfarer's Atlas** (`web/AtlasRoute.html`) oyuna gerek kalmadan planlayıcıyı haritada gösterir. Tek bir dosyadır, tarayıcıda açmak yeter (ilk açılışta internet gerekir: wasmoon Lua VM'i cdn.jsdelivr.net'ten, yazı tipleri Google Fonts'tan gelir).

- Sayfadaki bütün sayılar eklentinin kendi Lua kodundan gelir. `core/` ve `data/` dosyaları, köprü `web/bridge.lua` ile birlikte sayfanın içine gömülür ve tarayıcıda wasmoon (Lua 5.4, WebAssembly) ile, bir Web Worker'da çalışır. Lua 5.4'te `bit` kütüphanesi olmadığı için sayfa onu `&`, `|`, `<<` ile tanımlar; çıktılar LuaJIT'teki komut satırı demosuyla aynıdır.
- **Plan a journey:** fraksiyon, sınıf, başlangıç, hearthstone, binek, mühendislik aletleri, Frequent Flier ve beta yolları seçilir; görevler işaretlenir. Rota haritaya bacak bacak mürekkeple çizilir, her kip kendi çizgisiyle.
- **Ride every flight path:** Atlas'ın 2020 hâli (her kenar 1 adım) ile süreleri kullanan Atlas aynı haritada karşılaştırılır ve çizilir.
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

## Retail (ücretsiz deneme sürümü)

Eklenti, Blizzard'ın ücretsiz deneme sürümünün (Free Trial, 20. seviyeye kadar) çalıştığı güncel istemcide de (retail, 12.x) çalışır. Retail istemcisi `AtlasRoute_Mainline.toc` dosyasını yükler, Forever ise `AtlasRoute.toc` dosyasını yüklemeye devam eder. İki sürüm de aynı Atlas planlayıcısını (`core/atlasplan.lua`) kullanır; yalnızca dünya grafı farklıdır.

Retail'de elle kurulmuş bir harita yoktur. Graf her komutta oyunun kendi verisinden yeniden kurulur (`core/retail.lua`, oyunu okuyan kısım `ui/retail.lua`):

| Veri | Kaynak |
|---|---|
| uçuş noktalarının yeri, uçuş hatları ve uzunlukları | oyunun tabloları (TaxiNodes, TaxiPath, TaxiPathNode) → `data/retail_taxi.lua` |
| hangi uçuş noktalarını keşfettiğiniz, fraksiyonları | canlı istemci, `C_TaxiMap.GetTaxiNodesForMap` |
| kütükteki görevlerin hedefi ve teslim yeri | canlı istemci (`C_QuestLog.GetQuestsOnMap`, `GetNextWaypoint`); istemci haritada göstermiyorsa oyunun görev haritası tabloları (QuestPOIBlob, QuestPOIPoint) → `data/retail_quests.lua` |
| görev verenler (haritadaki "!" işaretleri) | canlı istemci, `C_QuestLine.GetAvailableQuestLines` (Blizzard'ın kendi haritasının kullandığı çağrı) |
| bulunduğunuz yer | `UnitPosition` |
| uçuş süreleri | oyunda ölçülür; ölçülene kadar yol uzunluğu ÷ koşu hızının %434'ü (≈ 30,4 yd/sn, warcraft.wiki.gg "Flight path") |
| hearthstone'un indiği yer | oyunda kaydedilir (hanciye bağlarken ya da taşı kullanınca); bekleme süresi `C_Item.GetItemCooldown` |
| yer hızı | binekteyken ölçülür (`GetUnitSpeed`); ölçülene kadar koşu hızı |

Tablolar build **12.1.5.70961** içindir ve `tools/extract_retail.py` ile wago.tools'un CSV dışa aktarımlarından üretilir; elle yazılmış koordinat ya da süre yoktur. Yeni bir build için:

```bash
python tools/extract_retail.py <CSV klasörü> <build>
```

(`https://wago.tools/db2/<tablo>/csv?build=<build>`: TaxiNodes, TaxiPath, TaxiPathNode, QuestPOIBlob, QuestPOIPoint.)

### Oyunda gösterim

1. `AtlasRoute/` klasörünü `World of Warcraft/_retail_/Interface/AddOns/` dizinine kopyalayın.
2. Karakter seçme ekranında *AddOns* menüsünden etkinleştirin. `AtlasRoute_Mainline.toc` içindeki `## Interface: 120105` numarası 12.1.5 içindir; oyunda `/dump select(4, GetBuildInfo())` farklı bir sayı verirse onu yazın ya da menüde *Load out of date AddOns* kutusunu işaretleyin.
3. `/ar status`: eklentinin okuduklarını gösterir (kıta, gösterilen ve keşfedilmiş uçuş noktaları, uçuş ve yer hızı, hearthstone, görev duraklarının kaynağı).
4. Birkaç görev alın; haritadaki görev verenleri de eklemek için `/ar nearby`.
5. `/ar list`: her durağın nereden geldiği (canlı kütük, harita işareti ya da oyunun tabloları). `/ar plan`: Atlas'ın turu. Plan bir pencerede açılır ve dünya haritasına (M) çizilir:
   - **Plan penceresi** (`ui/view.lua`): ilerleme çubuğu (yapılan / toplam durak, kalan süre), sıradaki durak ve ona canlı uzaklığınız (saniyede iki kez güncellenir), ardından bütün duraklar sırayla, yolculuk süreleriyle; sıradaki satır vurgulanır, yapılanlarda onay işareti çıkar, uçuşlu bacaklarda "fly" yazar. Bir durağa sol tıklayınca oyunun kendi yön oku (waypoint) oraya döner; sağ tıklayınca durak yapıldı/yapılmadı olarak işaretlenir. Pencere sürüklenebilir; *Map* haritayı açar, *Replan* yeniden planlar.
   - **Dünya haritası**: yürüme beyaz, koyu kenarlı çizgi; uçuşlar oyunun uçuş haritasının kendi çizgi dokusuyla (`_UI-Taxi-Line-horizontal`). Yeni bir plan açılınca rota parça parça çizilir (uçuş haritasının `LineScale` animasyonu). Duraklar yuvarlak, numaralı işaretler; aynı yerdeki duraklar tek işaret paylaşır ("1,2"). Sıradaki durağın arkasında görev işaretlerinin parıltısı (`UI-QuestPoi-OuterGlow`) atar; yapılanlar soluk. Hangi haritaya bakarsanız (bölge ya da kıta) ona göre çizilir; işaretler yakınlaştırınca ekrandaki boyutunu korur (Blizzard'ın harita iğneleri gibi). İşaretlerin üzerine gelince o yerdeki bütün duraklar listelenir; tıklayınca pencerede olduğu gibi ok ya da işaret.
   - Kullanılan bütün doku, atlas ve yazı tipleri Blizzard'ın 12.1.5 arayüzünün kendi kullandıklarıdır.
   - Görevi alınca, hedefleri bitince ve teslim edince ilgili duraklar kendiliğinden işaretlenir ve ok bir sonraki durağa geçer (`QUEST_ACCEPTED`, `QUEST_LOG_UPDATE`, `QUEST_TURNED_IN`).
6. `/ar route <uçuş noktası ya da durak>`: tek bir yere en hızlı yol. `/ar places` adları listeler.
7. Bir kez uçun ve hearthstone'u bir kez kullanın: eklenti uçuşu ölçer, hearthstone'un indiği yeri kaydeder (`/ar status`'ta görünür) ve sonraki planlar bunları kullanır.

Komutlar: `/ar plan`, `/ar window` (pencereyi aç/kapat), `/ar map` (haritayı aç), `/ar nearby [clear]`, `/ar list`, `/ar route <yer>`, `/ar places [metin]`, `/ar speed <yd/sn> | auto`, `/ar status`.

### Sınırlar

- Plan bulunduğunuz kıtada kalır. Başka kıtadaki duraklar plana alınmaz, `note:` satırında bildirilir (kıtalar arası gemi, zeplin ve portallar tablolarda yok).
- Yürüme düz çizgi × 1,3'tür; arazi, su ve dağlar bilinmez. Yürüme grafı her yeri en yakın 4 yere bağlar, kopuk kalan parçaları en yakın çiftten birleştirir.
- İstemcinin haritada göstermediği bir görev hedefi için tablolardaki her hedefin ilk alanının ortası kullanılır; bitmiş hedefler kütükteki sırayla eşleştirilir.
- Büyücü ışınlanmaları, şehir portalları ve skyriding modellenmedi.
- Haritadaki uçuş çizgileri iki uçuş noktası arasında düz çizgidir; uçağın izlediği gerçek yol (tablolarda var) çizilmez, yalnızca uzunluğu kullanılır. Pencere en çok 25 durak gösterir; daha uzun planlar sohbet penceresinde de listelenir.
- Eklenti gerçek bir istemcide ve deneme hesabında çalıştırılmadı. 12.1.5 API'si taklit edilerek (`tests/retail.lua`) Lua 5.1 ve LuaJIT altında sınandı; API imzaları Blizzard'ın arayüz kaynağından (Gethe/wow-ui-source, `live` dalı, 12.1.5.70961) alındı.

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

Gemi ve skyship yolculuk süreleri hiçbir kaynakta yok; tahmindir. Tidegear Coast uçuş noktasının hiç rotası olmadığı için eklenmedi; açılış gecesinin geçici portalları da eklenmedi. Koordinatlar bölge yerleşiminden **yaklaşık** olarak yerleştirildi, oyun dosyalarından okunmadı. Yolculuk ve bekleme süreleri de tahmindir. Algoritmalar bu sayılara bağlı değildir; yalnızca örnek sonuçlar bağlıdır. Dosya değiştirilerek başka bir veriyle plan yapılabilir. `data/quest_data.lua` gerçek Classic görevleridir: 8 Alliance, 8 Horde (ör. The Night Watch, Northfold Manor, Noble Deaths, The Barrens Port; Hammerfall, Raising Spirits, Elixir of Agony, Hunting in Stranglethorn). Hepsi patch 4.0.3a'da kaldırıldığı için Wowpedia sayfaları Classic hâlini anlatır; görevi veren ve alan NPC'ler ile hedeflerin yeri görev, NPC ve yaratık sayfalarından alındı, her görevin sayfası `wiki` alanında. (warcraft.wiki.gg aynı sayfaları taşır, ama buradan erişilemedi.) Hedeflerdeki öldürme ya da toplama süresi (`work`) wikide yok, tahmindir. Bazı görevler bir zincirin parçasıdır: önceki adım yapılmış sayılır; iki adım da kütükteyse (`requires`) planlayıcı ilkini teslim etmeden ikincisini almaz.

## Çalıştırma

LuaJIT gerekir (Lua 5.1 uyumlu, `bit` kütüphanesiyle). Lua 5.4 ile çalışmaz.

```bash
luajit tests/run.lua
```

Retail testleri (oyunun tabloları ve taklit edilmiş 12.x API'si ile):

```bash
luajit tests/retail.lua
```

Tasarım testleri (diyagramlar kodla aynı mı, desenler çalışıyor mu):

```bash
luajit tests/design.lua
```

Diyagramların PDF'i ve GitHub sayfası (`playwright-core`, `mermaid` ve Chromium gerekir; yolları ortam değişkenleriyle verilir):

```bash
PLAYWRIGHT_CORE=<...>/playwright-core MERMAID=<...>/mermaid.min.js CHROME=<chromium> node docs/diagrams/pdf.mjs
```

Karşılaştırma yöntemlerinin testleri ve ölçümler:

```bash
luajit benchmark/tests.lua
```

```bash
luajit benchmark/bench.lua all
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

Java ile karşılaştırma (Java derleyicisi gerekir; Atlas'ın Java kodu bu depoda yok, `reference/README.md`'deki gibi kendi deposundan alınır):

```bash
javac -d /tmp/jref /tmp/atlas/*.java reference/java/RefMain.java && luajit tools/compare_java.lua /tmp/jref tests/fixtures/bbtas.fsm
```

Rastgele FSM üretmek: `luajit tools/gen_fsm.lua <durum> <girdi> <çıktı> <tohum> [strong]`. Atlas'ın kullandığı `fsm-gen-fsm` aracı depoda yok; bu onun yerine yazıldı.

## Dosyalar

```
AtlasRoute/            eklenti (WoW'a kopyalanacak klasör)
  AtlasRoute.toc       Forever
  AtlasRoute_Mainline.toc  retail (ücretsiz deneme sürümü)
  core/oop.lua         Class, Interface, implements
  core/events.lua      Observable (Observer)
  core/fsm.lua         Atlas'ın graf yapısı, .fsm okuyucu, Java HashSet sırası
  core/atlas.lua       Atlas'ın birebir Lua karşılığı
  core/world.lua       dünya modeli: World, Place, TravelEdge, Teleport, Gated, Profile,
                       TravelMode stratejileri ve TravelModes, WorldSource
  core/graph.lua       TravelGraph, ExplorationOrder stratejileri, TravelGraphFactory, FsmGraphAdapter
  core/solver.lua      AtlasSolver (Template Method, Observable), ScoringRule stratejileri
  core/goals.lua       Goal stratejileri, QuestLog, LegAssembler, AtlasPlanner
  core/atlasplan.lua   AtlasPlan cephesi: görev turu, tek rota, uçuş ağı
  core/commands.lua    Command, CommandRegistry
  core/retail.lua      retail: oyunun verisinden dünya grafı ve görev durakları
  data/                Forever haritası ve gerçek Classic görevleri;
                       retail_taxi.lua, retail_quests.lua: oyunun tablolarından üretildi
  ui/addon.lua         oyun içi komutlar (Forever)
  ui/retail.lua        oyun içi komutlar (retail): canlı istemciyi okur, uçuşları ölçer
  ui/view.lua          retail: plan penceresi, dünya haritasındaki rota, yön oku
benchmark/             yalnızca ölçüt: Dijkstra, Held-Karp, Çinli ve Kırsal Postacı,
                       testleri ve bench.lua (eklentide yok)
web/                   Wayfarer's Atlas tanıtım sayfası ve Lua köprüsü
reference/             Atlas'ın Java koduna bağlantı + RefMain.java (karşılaştırma için)
tests/                 testler ve Java çıktıları; retail.lua: retail testleri;
                       design.lua: diyagramlar ile kod, desenlerin davranışı
docs/                  sınıf, kullanım durumu ve sıra diyagramları: PDF, Mermaid kaynakları
                       (diagrams/), GitHub sayfası, pdf.mjs
tools/                 yükleyici, ölçüm, Java karşılaştırması, FSM üretici, komut satırı demosu;
                       extract_retail.py: retail verisini oyunun tablolarından üretir
```
