# AtlasRoute: sınıf, kullanım durumu ve sıra diyagramları

Kaynaklar bu klasördeki `.mmd` dosyalarıdır; bu sayfa ve `../AtlasRoute-Diyagramlar.pdf` onlardan
`node docs/diagrams/pdf.mjs` ile üretilir. `tests/design.lua` diyagramları kodla karşılaştırır.

## Paketler

```mermaid
flowchart TB
  UI["<b>Arayüzler</b><br/>ui/addon.lua (Forever), ui/retail.lua (retail),<br/>ui/view.lua (plan penceresi), web/bridge.lua, tools/plan.lua"]
  CMD["<b>Komutlar</b> (Command)<br/>Command, CommandRegistry"]
  SRC["<b>Veri kaynakları</b> (Adapter)<br/>ForeverMap, RetailSnapshot"]
  FAC["<b>Cephe</b> (Facade)<br/>AtlasPlan"]
  PLAN["<b>Planlama</b> (Strategy)<br/>AtlasPlanner, Goal: QuestTourGoal, RouteGoal,<br/>FlightNetworkGoal, FsmCoverageGoal; QuestLog, LegAssembler"]
  SOL["<b>Atlas çözücü</b> (Template Method, Observer, Strategy)<br/>AtlasSolver, RunState, ScoringRule: SingleTarget, WholeChain"]
  GRA["<b>Graf</b> (Factory, Adapter, Strategy)<br/>TravelGraph, TravelGraphFactory, FsmGraphAdapter,<br/>ExplorationOrder: CheapestFirst, DearestFirst, InsertionOrder, Shuffled"]
  MOD["<b>Dünya modeli</b> (Strategy, Registry)<br/>World, Place, TravelEdge, Teleport, Gated, Profile,<br/>TravelMode: FixedMode, WalkMode, FlightMode; TravelModes; WorldSource"]
  JAVA["<b>Atlas.java'nın birebir karşılığı</b><br/>Atlas, FSM"]
  OOP["<b>Altyapı</b><br/>Class, Interface (core/oop.lua), Observable (core/events.lua)"]

  UI --> CMD
  UI --> FAC
  UI --> SRC
  FAC --> PLAN
  FAC --> GRA
  PLAN --> SOL
  PLAN --> GRA
  SOL --> GRA
  GRA --> MOD
  GRA --> JAVA
  SRC --> MOD
```

## 1. Dünya modeli

```mermaid
classDiagram
  direction TB

  class Profile {
    +faction
    +class
    +speed
    +hearth
    +items
    +flySpeed
    +unconfirmed
    +of(t)$ Profile
    +groundSpeed() number
    +flightFactor() number
  }

  class Gated {
    +faction
    +class
    +item
    +spell
    +unconfirmed
    +check(g, profile)$ bool
    +allows(profile) bool
  }

  class TravelEdge {
    +from
    +to
    +mode
    +cost
    +seconds(profile) number
  }

  class Teleport {
    +to
    +toBind
    +mode
    +cost
    +limited
  }

  class Place {
    +id
    +name
    +zone
    +continent
    +x
    +y
    +kind
    +distanceTo(other) number
  }

  class TravelMode {
    <<interface>>
    +seconds(edge, profile) number
    +legMode() string
    +joins(legMode) bool
  }

  class FixedMode {
    +name
    +seconds(edge, profile) number
    +legMode() string
    +joins(legMode) bool
  }

  class WalkMode {
    +seconds(edge, profile) number
    +joins(legMode) bool
  }

  class FlightMode {
    +seconds(edge, profile) number
    +joins(legMode) bool
  }

  class TravelModes {
    <<registry>>
    +register(name, mode)$ TravelMode
    +get(name)$ TravelMode
  }

  class World {
    +nodes
    +adj
    +teleports
    +addPlace(p) int
    +addFlightMaster(placeId, faction, class, unconfirmed) int
    +addFlightLink(idA, idB, opts)
    +addTransport(t)
    +addTeleport(t)
    +connectWalking(k, extra)
    +edge(from, to, mode, cost, gate) TravelEdge
    +index(id) int
    +allowed(gated, profile) bool
    +edgeCost(e, profile) number
  }

  class WorldSource {
    <<interface>>
    +build() World
  }

  class ForeverMap {
    +data
    +build() World
  }

  class RetailSnapshot {
    +snap
    +profile
    +start
    +quests
    +notes
    +build() World
  }

  Gated <|-- TravelEdge
  Gated <|-- Teleport
  Gated ..> Profile : izin
  World "1" *-- "*" Place : yerler
  World "1" *-- "*" TravelEdge : kenarlar
  World "1" *-- "*" Teleport : ışınlanmalar
  TravelEdge ..> TravelModes : kipini sorar
  TravelModes o-- "*" TravelMode
  TravelMode <|.. FixedMode
  FixedMode <|-- WalkMode
  FixedMode <|-- FlightMode
  WalkMode ..> Profile : yer hızı
  FlightMode ..> Profile : uçuş hızı
  WorldSource <|.. ForeverMap
  WorldSource <|.. RetailSnapshot
  ForeverMap ..> World : kurar
  RetailSnapshot ..> World : kurar
  RetailSnapshot ..> Profile : kurar
```

## 2. Graf ve Atlas çözücü

```mermaid
classDiagram
  direction TB

  class TravelGraph {
    +edges
    +out
    +m
    +removed
    +groups
    +add(e) int
    +outEdges(node, order) list
    +removeGroup(group)
  }

  class ExplorationOrder {
    <<interface>>
    +key() any
    +arrange(list, edges, node)
  }
  class CheapestFirst {
    +key() any
    +arrange(list, edges, node)
  }
  class DearestFirst {
    +key() any
    +arrange(list, edges, node)
  }
  class InsertionOrder {
    +key() any
    +arrange(list, edges, node)
  }
  class Shuffled {
    +seed
    +key() any
    +arrange(list, edges, node)
  }
  class ExplorationOrders {
    <<utility>>
    +default()$ list
    +of(spec)$ ExplorationOrder
  }

  class TravelGraphFactory {
    +world
    +profile
    +limited() list
    +build() TravelGraph
  }

  class FsmGraphAdapter {
    +fsm
    +build() TravelGraph
  }

  class FSM {
    +edges
    +out
    +m
    +addEdge(source, dest, input, output, weight) int
    +outEdges(node) list
    +firstStart() int
    +parse(text)$ FSM
  }

  class Atlas {
    <<utility>>
    +longestPath(g, start, keepLast)$ list
    +run(g, keepLast)$ string
    +testSuite(g, path)$ string
    +stats(g, path)$ table
  }

  class Observable {
    +on(event, listener)
    +off(event, listener)
    +emit(event, args)
  }

  class ScoringRule {
    <<interface>>
    +propagate(avail, value) number
    +candidate(nc, avail, value) number
  }
  class SingleTarget {
    +propagate(avail, value) number
    +candidate(nc, avail, value) number
  }
  class WholeChain {
    +propagate(avail, value) number
    +candidate(nc, avail, value) number
  }

  class AtlasSolver {
    +orders
    +scoring
    +solve(g, start) table
    +explore(g, last, order) list
    +score(g, last, order, state) number
    +choose(g, last, state) list
    +append(g, chain, last, state) int
  }

  class RunState {
    +covered
    +walk
    +seconds
    +value
    +required
    +available(l) bool
  }

  ExplorationOrder <|.. CheapestFirst
  ExplorationOrder <|.. DearestFirst
  ExplorationOrder <|.. InsertionOrder
  ExplorationOrder <|.. Shuffled
  ExplorationOrders ..> ExplorationOrder : yaratır
  TravelGraph ..> ExplorationOrder : sıraya göre dizer
  TravelGraphFactory ..> TravelGraph : kurar
  FsmGraphAdapter ..> FSM : uyarlar
  FsmGraphAdapter ..> TravelGraph : kurar
  Atlas ..> FSM : 2020 Java karşılığı
  Observable <|-- AtlasSolver
  AtlasSolver o-- "16" ExplorationOrder : orders
  AtlasSolver o-- "1" ScoringRule : scoring
  ScoringRule <|.. SingleTarget
  ScoringRule <|.. WholeChain
  AtlasSolver ..> TravelGraph : yürür
  AtlasSolver ..> RunState : yaratır
```

## 3. Planlama, cephe ve arayüzler

```mermaid
classDiagram
  direction TB

  class Goal {
    <<interface>>
    +prepare(g)
    +collect(g, run) any
  }
  class QuestTourGoal {
    +world
    +stops
    +prepare(g)
    +collect(g, run) table
  }
  class RouteGoal {
    +dest
    +prepare(g)
    +collect(g, run) number
  }
  class FlightNetworkGoal {
    +required
    +prepare(g)
    +collect(g, run) table
  }
  class FsmCoverageGoal {
    +prepare(g)
    +collect(g, run) table
  }

  class QuestLog {
    +world
    +quests
    +stops() list
  }

  class LegAssembler {
    +legs(g, labels) list
  }

  class AtlasPlanner {
    +solver
    +run(g, start, goal) any
  }

  class AtlasPlan {
    <<facade>>
    +plan(world, profile, startId, quests, opts)$ table
    +route(world, profile, fromId, toId, opts)$ number
    +cover(world, profile, startId, opts)$ table
    +coverFSM(fsm, startNode, opts)$ table
    +travelGraph(world, profile)$ TravelGraph
    +limited(world, profile)$ list
    +stops(world, quests)$ list
    +walk(g, start, opts)$ table
    +legsOf(g, labels)$ list
  }

  class Command {
    +name
    +handler
    +execute(rest)
  }

  class CommandRegistry {
    +commands
    +register(name, handler) Command
    +get(name) Command
    +dispatch(msg)
    +fromTable(t)$ CommandRegistry
  }

  class ForeverShell {
    <<module ui/addon.lua>>
  }
  class RetailShell {
    <<module ui/retail.lua>>
  }
  class PlanWindow {
    <<module ui/view.lua>>
  }
  class WebBridge {
    <<module web/bridge.lua>>
  }

  Goal <|.. QuestTourGoal
  Goal <|.. RouteGoal
  Goal <|.. FlightNetworkGoal
  Goal <|.. FsmCoverageGoal
  QuestTourGoal ..> QuestLog : durakları alır
  QuestTourGoal ..> LegAssembler : bacaklara böler
  RouteGoal ..> LegAssembler : bacaklara böler
  AtlasPlanner o-- AtlasSolver : solver
  AtlasPlanner ..> Goal : run(goal)
  AtlasPlan ..> AtlasPlanner : kurar, çalıştırır
  AtlasPlan ..> TravelGraphFactory : grafı kurar
  AtlasPlan ..> AtlasSolver : "round" olayına abone (yield)
  CommandRegistry o-- "*" Command
  ForeverShell ..> CommandRegistry : /ar
  RetailShell ..> CommandRegistry : /ar
  ForeverShell ..> AtlasPlan
  RetailShell ..> AtlasPlan
  WebBridge ..> AtlasPlan
  ForeverShell ..> ForeverMap : dünyayı kurar
  RetailShell ..> RetailSnapshot : dünyayı kurar
  RetailShell ..> PlanWindow : planı gösterir
```

## 4.1 Kullanım durumları: Forever eklentisi

```mermaid
%% Kullanım durumları: Forever eklentisi. Komutlar: AtlasRoute/ui/addon.lua
%% (Mermaid'de kullanım durumu diyagramı türü yok: aktörler dikdörtgen, kullanım durumları
%% oval, sistem sınırı bir çerçevedir; «include» ve «extend» kesikli oklardır.)
flowchart LR
  P["«aktör»<br/>Oyuncu"]
  WOW["«aktör»<br/>WoW istemcisi"]
  subgraph SYS["AtlasRoute: Forever eklentisi"]
    direction TB
    UC1(["Örnek görevleri yükle<br/>/ar demo"])
    UC2(["Görev ekle<br/>/ar quest"])
    UC3(["Görevleri listele, sil, temizle<br/>/ar list, /ar remove, /ar clear"])
    UC4(["Görev turu planla<br/>/ar plan"])
    UC5(["Bir yere rota iste<br/>/ar route"])
    UC6(["Başlangıç yerini seç<br/>/ar from"])
    UC7(["Binek hızını ayarla<br/>/ar speed"])
    UC8(["Frequent Flier ve beta yolları<br/>/ar flier, /ar beta"])
    UC9(["Yerleri ara<br/>/ar places"])
    UC10(["Karakteri oku<br/>fraksiyon, sınıf, büyüler,<br/>hearthstone, aletler, bekleme süreleri"])
    UC11(["Bulunulan yeri bul<br/>bölge ve alt bölge adı"])
  end
  P --- UC1
  P --- UC2
  P --- UC3
  P --- UC4
  P --- UC5
  P --- UC6
  P --- UC7
  P --- UC8
  P --- UC9
  UC4 -. "«include»" .-> UC10
  UC4 -. "«include»" .-> UC11
  UC5 -. "«include»" .-> UC10
  UC5 -. "«include»" .-> UC11
  UC6 -. "«extend»" .-> UC11
  UC10 --- WOW
  UC11 --- WOW
```

## 4.2 Kullanım durumları: retail eklentisi

```mermaid
%% Kullanım durumları: retail eklentisi (ücretsiz deneme sürümü). Komutlar: AtlasRoute/ui/retail.lua
flowchart LR
  P["«aktör»<br/>Oyuncu"]
  WOW["«aktör»<br/>WoW istemcisi"]
  subgraph SYS["AtlasRoute: retail eklentisi"]
    direction TB
    UC1(["Görev kütüğünü planla<br/>/ar plan"])
    UC2(["Yakındaki görev verenleri ekle<br/>/ar nearby"])
    UC3(["Planın duraklarını listele<br/>/ar list"])
    UC4(["Bir yere rota iste<br/>/ar route"])
    UC5(["Yerleri ara<br/>/ar places"])
    UC6(["Binek hızını ayarla<br/>/ar speed"])
    UC7(["Ne okunduğunu gör<br/>/ar status"])
    UC8(["Plan penceresini aç, kapat<br/>/ar window"])
    UC9(["Haritada rotayı gör<br/>/ar map"])
    UC10(["Bir durağa yön oku koy<br/>pencerede sol tık"])
    UC11(["Durağı tamam say<br/>pencerede sağ tık"])
    UC12(["Oyunu oku<br/>konum, uçuş noktaları,<br/>görev kütüğü, görev verenler"])
    UC13(["Uçuş süresini ölç"])
    UC14(["Hearthstone noktasını kaydet"])
    UC15(["Görev olayıyla durağı işaretle<br/>alındı, bitti, teslim edildi"])
  end
  P --- UC1
  P --- UC2
  P --- UC3
  P --- UC4
  P --- UC5
  P --- UC6
  P --- UC7
  P --- UC8
  P --- UC9
  P --- UC10
  P --- UC11
  UC1 -. "«include»" .-> UC12
  UC3 -. "«include»" .-> UC12
  UC4 -. "«include»" .-> UC12
  UC1 -. "«include»" .-> UC8
  UC10 -. "«extend»" .-> UC11
  UC15 -. "«include»" .-> UC11
  UC12 --- WOW
  WOW --- UC13
  WOW --- UC14
  WOW --- UC15
```

## 4.3 Kullanım durumları: tanıtım sayfası

```mermaid
%% Kullanım durumları: Wayfarer's Atlas tanıtım sayfası. Kod: web/template.html, web/bridge.lua
flowchart LR
  V["«aktör»<br/>Ziyaretçi"]
  subgraph SYS["Wayfarer's Atlas (tarayıcıda, oyunsuz)"]
    direction TB
    UC1(["Karakteri seç<br/>fraksiyon, sınıf, başlangıç,<br/>hearthstone, binek, aletler"])
    UC2(["Görevleri seç"])
    UC3(["Yolculuğu planla<br/>Plan the journey"])
    UC4(["Yolculuğu haritada izle<br/>figür, kamera, kum saati"])
    UC5(["Yolculuğu atla<br/>Skip"])
    UC6(["Bir yere tıkla ve git<br/>Travel"])
    UC7(["Uçuş ağının tamamını kapsa<br/>Atlas 2020 ve süreli Atlas"])
    UC8(["Kapsama yürüyüşünü çiz<br/>Draw"])
    UC9(["Atlas ile hesapla<br/>Lua kodu, wasmoon'da"])
  end
  V --- UC1
  V --- UC2
  V --- UC3
  V --- UC6
  V --- UC7
  UC3 -. "«include»" .-> UC9
  UC3 -. "«include»" .-> UC4
  UC6 -. "«include»" .-> UC9
  UC6 -. "«include»" .-> UC4
  UC7 -. "«include»" .-> UC9
  UC5 -. "«extend»" .-> UC4
  UC8 -. "«extend»" .-> UC7
```

## 5.1 Sıra: Forever eklentisinde /ar plan

```mermaid
%% Sıra diyagramı: Forever eklentisinde /ar plan. Kod: AtlasRoute/ui/addon.lua, core/
sequenceDiagram
  autonumber
  actor P as Oyuncu
  participant WOW as WoW istemcisi
  participant CR as CommandRegistry
  participant CMD as Command
  participant UI as AtlasRoute/ui/addon.lua
  participant AP as AtlasPlan
  participant QG as QuestTourGoal
  participant QL as QuestLog
  participant TF as TravelGraphFactory
  participant PL as AtlasPlanner
  participant S as AtlasSolver
  participant LA as LegAssembler

  P->>WOW: /ar plan yazar
  WOW->>CR: dispatch("plan")
  CR->>CR: get("plan")
  CR->>CMD: execute("")
  CMD->>UI: plan()
  UI->>UI: startPlace()
  UI->>WOW: GetSubZoneText(), GetZoneText()
  UI->>UI: profile()
  UI->>WOW: UnitClass(), UnitFactionGroup(), IsSpellKnown(), GetItemCount(), GetBindLocation(), GetItemCooldown()
  UI->>UI: coroutine.create(plan işi)
  UI-->>P: "Planning from ..." (sohbet)

  WOW->>UI: OnUpdate (ilk kare): coroutine.resume
  UI->>AP: plan(world, profile, startId, quests, opts)
  AP->>QG: new(world, quests)
  QG->>QL: stops()
  QL-->>QG: duraklar (alma, hedefler, teslim, önkoşullar)
  AP->>TF: build()
  TF-->>AP: TravelGraph (karakterin kullanabildiği kenarlar, saniye)
  AP->>PL: run(g, start, goal)
  PL->>QG: prepare(g)
  Note over QG: her durak için gerekli bir döngü kenarı
  PL->>S: solve(g, start)
  loop her Atlas turu (ayrıntısı bir sonraki diyagramda)
    S->>S: choose(g, last, state)
    S->>S: append(g, chain, last, state)
    S->>S: emit("round", rounds, covered, required)
    S-->>UI: "round" dinleyicisi: coroutine.yield()
    Note over UI,WOW: kare oyuna geri verilir, sonraki OnUpdate kaldığı yerden sürdürür
    WOW->>UI: OnUpdate: coroutine.resume
  end
  S-->>PL: yürüyüş (kenar sırası, süre, tur sayısı)
  PL->>QG: collect(g, run)
  QG->>LA: legs(g, labels)
  LA-->>QG: bacaklar (yürü, uç, gemi, ışınlan...)
  QG-->>AP: plan
  AP-->>UI: plan
  UI->>UI: printPlan(plan)
  UI-->>P: duraklar ve bacaklar (sohbet)
```

## 5.2 Sıra: bir Atlas turu

```mermaid
%% Sıra diyagramı: AtlasSolver.solve ve bir Atlas turu. Kod: AtlasRoute/core/solver.lua, core/graph.lua
sequenceDiagram
  autonumber
  participant PL as AtlasPlanner
  participant S as AtlasSolver
  participant RS as RunState
  participant TG as TravelGraph
  participant EO as ExplorationOrder
  participant SR as ScoringRule

  PL->>S: solve(g, start)
  S->>TG: add(e)
  Note over S,TG: başlangıç döngüsü: yürüyüş buradan başlar
  S->>RS: new(g)
  Note over RS: VALUE = bütün ağırlıkların toplamı + 1
  loop kapsanmamış gerekli kenar kaldıkça
    S->>S: choose(g, last, state)
    loop 16 keşif sırasının her biri
      S->>S: score(g, last, order, state)
      S->>S: explore(g, last, order)
      S->>TG: outEdges(node, order)
      TG->>EO: arrange(list, edges, node)
      Note over TG,EO: yalnızca ilk istekte, sonra sıraya göre önbellekten
      TG-->>S: canlı kenarlar (harcanan ışınlanmalar hariç)
      Note over S: DFS ardıl-sıralaması, sonra ters sırada en uzun yol DP'si
      loop sıradaki her kenar n
        S->>RS: available(n)
        S->>SR: propagate(avail, value)
        S->>SR: candidate(nc, avail, value)
      end
      S-->>S: bu sıranın en iyi zinciri ve puanı
    end
    S-->>S: bütün sıralar içinde en iyi zincir
    alt zincir yok
      S-->>PL: kalan gerekli kenarlara ulaşılamıyor: dur
    else zincir var
      S->>S: append(g, chain, last, state)
      loop zincirdeki her kenar
        S->>RS: available(l)
        opt yeni gerekli kenar
          S->>S: emit("covered", l, walk)
        end
        opt tek kullanımlık ışınlanma
          S->>TG: removeGroup(group)
        end
      end
      S->>S: emit("round", rounds, covered, required)
    end
  end
  S-->>PL: walk, seconds, covered, required, rounds, order
```

## 5.3 Sıra: retail eklentisinde /ar plan ve bir görev olayı

```mermaid
%% Sıra diyagramı: retail eklentisinde /ar plan, sonra bir görev olayı.
%% Kod: AtlasRoute/ui/retail.lua, AtlasRoute/ui/view.lua, core/retail.lua
sequenceDiagram
  autonumber
  actor P as Oyuncu
  participant WOW as WoW istemcisi
  participant CR as CommandRegistry
  participant RUI as AtlasRoute/ui/retail.lua
  participant RET as AtlasRoute/core/retail.lua
  participant SNAP as RetailSnapshot
  participant W as World
  participant AP as AtlasPlan
  participant V as AtlasRoute/ui/view.lua

  P->>WOW: /ar plan
  WOW->>CR: dispatch("plan")
  CR->>RUI: plan() (Command)
  RUI->>RUI: build()
  RUI->>RUI: snapshot()
  RUI->>WOW: UnitPosition(), C_TaxiMap.GetTaxiNodesForMap(), C_QuestLog.GetQuestsOnMap(), GetBindLocation(), C_Item.GetItemCooldown()
  RUI->>RET: build(snap)
  RET->>SNAP: new(snap, taxiData, questData)
  RET->>SNAP: build()
  SNAP->>W: new()
  SNAP->>W: addPlace(p)
  SNAP->>W: addFlightMaster(placeId)
  SNAP->>W: edge(from, to, mode, cost)
  SNAP->>W: connectWalking(k)
  SNAP-->>RET: World, profile, quests, notes
  RET-->>RUI: b = {world, profile, start, quests, notes}
  RUI->>AP: plan(world, profile, startId, quests, opts)
  Note over RUI,AP: coroutine içinde, her Atlas turundan sonra kare oyuna bırakılır (Forever diyagramındaki gibi)
  AP-->>RUI: plan
  RUI->>RUI: printPlan(b, plan)
  RUI->>V: model(world, plan, continent, describe)
  RUI->>V: show(model)
  V->>WOW: plan penceresi, dünya haritasına rota (harita veri sağlayıcısı)
  RUI-->>P: özet ve notlar (sohbet)

  Note over P,V: daha sonra, oyunda
  P->>WOW: görevi teslim eder
  WOW->>V: QUEST_TURNED_IN (questID)
  V->>V: questEvent(questID, kinds)
  V->>V: toggle(k)
  V->>V: waypoint(k)
  V->>WOW: C_Map.SetUserWaypoint(), C_SuperTrack.SetSuperTrackedUserWaypoint()
  WOW-->>P: yön oku sıradaki durağı gösterir
```

## 5.4 Sıra: tanıtım sayfasında plan

```mermaid
%% Sıra diyagramı: tanıtım sayfasında "Plan the journey". Kod: web/template.html, web/bridge.lua
sequenceDiagram
  autonumber
  actor V as Ziyaretçi
  participant PG as web/template.html
  participant WK as Web Worker (wasmoon, Lua 5.4)
  participant BR as web/bridge.lua
  participant AP as AtlasPlan

  V->>PG: Plan the journey
  PG->>PG: plan()
  PG->>PG: planQuery()
  PG->>WK: postMessage({type: "call", fn: "plan", arg})
  WK->>BR: plan(q)
  BR->>BR: parse(q)
  BR->>BR: getWorld()
  BR->>BR: profileFrom(o)
  BR->>AP: plan(world, profile, startId, quests)
  AP-->>BR: plan
  BR->>BR: legsOut(w, travel)
  BR->>BR: json(v)
  BR-->>WK: JSON
  WK-->>PG: postMessage({type: "result", result})
  PG->>PG: renderPlan(r)
  PG->>PG: buildSegments(segs)
  PG->>PG: drawMarkers(steps)
  PG->>PG: travel(items, who, opts)
  loop her bacak (requestAnimationFrame)
    PG->>PG: figürü kipine göre çiz, mürekkebi aç, kamera izler, kum saati sayar
  end
  PG-->>V: rota haritada, duraklar yolculuk günlüğünde, olaylar sohbet kutusunda
```
