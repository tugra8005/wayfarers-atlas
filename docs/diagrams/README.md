# AtlasRoute: sınıf diyagramları

Kaynaklar bu klasördeki `.mmd` dosyalarıdır; bu sayfa ve `../AtlasRoute-Sinif-Diyagramlari.pdf` onlardan
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
