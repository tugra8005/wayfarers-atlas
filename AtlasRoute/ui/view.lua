-- What the retail plan looks like in game:
--   * the world map: the route drawn in (walking: white with a dark edge; flights: the
--     game's own flight-line texture), round numbered markers, one marker for stops at the
--     same spot ("1,2"), a pulsing glow on the next stop, done stops dimmed. Drawn by a map
--     data provider, the way Blizzard's own map layers are, so it follows the map you look
--     at, zoom and pan.
--   * the plan window: progress bar, the next stop with its live distance, then every stop
--     in order with its travel time. Left-click a stop: the game's waypoint arrow points to
--     it. Right-click: mark it done (or not).
--   * stops tick themselves off when you pick up, finish or hand in their quest.
-- Every texture, atlas and font here is one Blizzard's own 12.1.5 interface uses
-- (_UI-Taxi-Line-horizontal: the flight map's route lines; UI-QuestPoi-OuterGlow: the glow
-- behind quest markers; TempPortraitAlphaMask: round portraits; the checkmark: the emissary
-- tracker), so none of them can come out blank.
-- Positions are world yards (UnitPosition axes); ns.apiVec turns them into the vectors the
-- C_Map functions take (ui/retail.lua).
local _, ns = ...

local View = {}
ns.View = View

-- Sizes on the map are in screen pixels at zoom 1 (divided by the canvas scale).
local MARKER, WALK_LINE, FLY_LINE, SAME_SPOT = 20, 3, 18, 15 -- SAME_SPOT in yards
local MAX_ROWS = 25
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TAXI_LINE = "_UI-Taxi-Line-horizontal"
local GLOW = "UI-QuestPoi-OuterGlow"
local CHECK = "worldquest-emissary-tracker-checkmark"
local COLOR = {
  walk = { 1, 1, 1 }, fly = { 0.4, 0.8, 1 }, hearth = { 0.4, 1, 0.4 },
  accept = { 1, 0.82, 0 }, objective = { 1, 0.5, 0.2 }, turnin = { 0.3, 0.9, 0.3 },
}
local KIND = { accept = "pick up", objective = "objective", turnin = "turn in" }

local current -- {continent, start, stops, segments, groups, seconds, speed}

local function fmtTime(s)
  s = math.floor(s + 0.5)
  if s >= 3600 then return ("%dh %02dm"):format(math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  return ("%dm %02ds"):format(math.floor(s / 60), s % 60)
end

local function hex(c) return ("ff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

-- Plan -> what to draw ------------------------------------------------------------------------
-- stops    = {{n, name, kind, quest (number), x, y, seconds, travel (text), modes, done}}
-- segments = {{x1, y1, x2, y2, mode, stop}}  (stop = the stop this travel leads to)
-- groups   = {{stop indices at the same spot}}, in route order
function View.model(world, plan, continent, describe)
  local m = { continent = continent, stops = {}, segments = {}, groups = {}, seconds = plan.seconds }
  local here = world.nodes[world:index("here")]
  m.start = { x = here.x, y = here.y }
  for k, leg in ipairs(plan.legs) do
    local node = world.nodes[leg.stop.node]
    local modes = {}
    for _, t in ipairs(leg.travel) do modes[t.mode] = true end
    m.stops[k] = { n = k, name = node.name, kind = leg.stop.kind,
                   quest = tonumber(tostring(leg.stop.quest):match("%d+")),
                   x = node.x, y = node.y, seconds = leg.seconds, modes = modes,
                   travel = describe and describe(leg.travel) or "", done = false }
    for _, t in ipairs(leg.travel) do
      if t.mode ~= "hearth" and t.mode ~= "teleport" then
        for i = 2, #t.path do
          local a, b = world.nodes[t.path[i - 1]], world.nodes[t.path[i]]
          if a.x ~= b.x or a.y ~= b.y then
            m.segments[#m.segments + 1] = { a.x, a.y, b.x, b.y, t.mode, k }
          end
        end
      end
    end
  end
  -- stops within SAME_SPOT yards of each other share one marker
  for k, s in ipairs(m.stops) do
    local joined
    for _, g in ipairs(m.groups) do
      local f = m.stops[g[1]]
      if (f.x - s.x) ^ 2 + (f.y - s.y) ^ 2 <= SAME_SPOT ^ 2 then g[#g + 1] = k; joined = true; break end
    end
    if not joined then m.groups[#m.groups + 1] = { k } end
  end
  return m
end

-- The first stop not done yet, or nil.
local function nextStop()
  if not current then return nil end
  for k, s in ipairs(current.stops) do if not s.done then return k end end
end
View.nextStop = nextStop

-- Clip a segment to the unit square (Liang-Barsky); nil when it misses the square.
local function clip(x1, y1, x2, y2)
  local t0, t1 = 0, 1
  local dx, dy = x2 - x1, y2 - y1
  local p = { -dx, dx, -dy, dy }
  local q = { x1, 1 - x1, y1, 1 - y1 }
  for i = 1, 4 do
    if p[i] == 0 then
      if q[i] < 0 then return nil end
    else
      local r = q[i] / p[i]
      if p[i] < 0 then if r > t1 then return nil elseif r > t0 then t0 = r end
      else if r < t0 then return nil elseif r < t1 then t1 = r end end
    end
  end
  return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end
View.clip = clip

-- The waypoint arrow --------------------------------------------------------------------------
function View.waypoint(k)
  local s = current and current.stops[k]
  if not s then return end
  local mapID, pos = C_Map.GetMapPosFromWorldPos(current.continent, ns.apiVec(s.x, s.y))
  if not mapID or not pos or not C_Map.CanSetUserWaypointOnMap(mapID) then
    ns.out("The game doesn't allow a waypoint there.")
    return
  end
  local x, y = pos:GetXY()
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
  C_SuperTrack.SetSuperTrackedUserWaypoint(true)
  ns.out(("Arrow points to stop %d: %s."):format(k, s.name))
end

-- Shapes ------------------------------------------------------------------------------------
local function round(frame, layerName, sub)
  local t = frame:CreateTexture(nil, layerName or "ARTWORK", nil, sub)
  local mask = frame:CreateMaskTexture()
  mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(t)
  t:AddMaskTexture(mask)
  return t
end

-- World map layer -----------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)
local layer
local walkLines, flyLines, markers = {}, {}, {}
local revealNext = false -- a new plan: draw its route in, segment by segment

function provider:RemoveAllData()
  for _, l in ipairs(walkLines) do l:Hide() end
  for _, l in ipairs(flyLines) do l:Hide() end
  for _, f in ipairs(markers) do f:Hide(); f.pulse:Stop() end
end

-- A line inside its own frame, as Blizzard's flight map builds them: the frame's animation
-- draws the line in from its start (LineScale on the child "Fill").
local function lineHolder(pool, i, flight)
  local h = pool[i]
  if h then return h end
  h = CreateFrame("Frame", nil, layer)
  h:SetAllPoints(layer)
  if flight then
    h.Fill = h:CreateLine(nil, "ARTWORK")
    h.Fill:SetAtlas(TAXI_LINE)
  else
    h.Edge = h:CreateLine(nil, "ARTWORK", nil, 1)
    h.Edge:SetColorTexture(0, 0, 0, 0.6)
    h.Fill = h:CreateLine(nil, "ARTWORK", nil, 2)
  end
  h.reveal = h:CreateAnimationGroup()
  for _, key in ipairs(flight and { "Fill" } or { "Edge", "Fill" }) do
    local a = h.reveal:CreateAnimation("LineScale")
    a:SetChildKey(key)
    a:SetScaleFrom(0.001, 1)
    a:SetScaleTo(1, 1)
    a:SetOrigin("LEFT", 0, 0)
    a:SetDuration(0.15)
    a:SetSmoothing("IN")
  end
  pool[i] = h
  return h
end

local function marker(i)
  local f = markers[i]
  if f then return f end
  f = CreateFrame("Button", nil, layer)
  f.glow = f:CreateTexture(nil, "BACKGROUND")
  f.glow:SetAtlas(GLOW)
  f.glow:SetPoint("CENTER")
  f.glow:SetBlendMode("ADD")
  f.rim = round(f, "ARTWORK", 1)
  f.rim:SetAllPoints()
  f.rim:SetColorTexture(0.05, 0.05, 0.05, 0.95)
  f.fill = round(f, "ARTWORK", 2)
  f.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
  f.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
  f.label:SetPoint("CENTER", 0, 0)
  f.pulse = f:CreateAnimationGroup()
  f.pulse:SetLooping("BOUNCE")
  local a = f.pulse:CreateAnimation("Alpha")
  a:SetTarget(f.glow)
  a:SetFromAlpha(0.25)
  a:SetToAlpha(1)
  a:SetDuration(0.8)
  a:SetSmoothing("IN_OUT")
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:SetScript("OnClick", function(self, button)
    if not self.stop then return end
    if button == "RightButton" then View.toggle(self.stop) else View.waypoint(self.stop) end
  end)
  f:SetScript("OnEnter", function(self)
    if not self.group or not current then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for _, k in ipairs(self.group) do
      local s = current.stops[k]
      local c = COLOR[s.kind] or COLOR.walk
      GameTooltip:AddLine(("%d. %s%s"):format(k, s.name, s.done and "  (done)" or ""), c[1], c[2], c[3])
      GameTooltip:AddLine(("%s, %s: %s"):format(KIND[s.kind] or s.kind, fmtTime(s.seconds), s.travel), 0.85, 0.85, 0.85, true)
    end
    GameTooltip:AddLine("Left-click: arrow   Right-click: done", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  markers[i] = f
  return f
end

function provider:RefreshAllData()
  self:RemoveAllData()
  local map = self:GetMap()
  if not current or not map then return end
  local mapID, canvas = map:GetMapID(), map:GetCanvas()
  if not mapID or not canvas then return end
  if not layer then layer = CreateFrame("Frame", nil, canvas) end
  layer:SetParent(canvas)
  layer:SetAllPoints(canvas)
  layer:SetFrameLevel(canvas:GetFrameLevel() + 2000) -- above Blizzard's pins
  layer:Show()
  local w, h = canvas:GetSize()
  local scale = map:GetCanvasScale() or 1
  local function norm(x, y)
    local _, pos = C_Map.GetMapPosFromWorldPos(current.continent, ns.apiVec(x, y), mapID)
    if pos then return pos:GetXY() end
  end
  local reveal, delay = revealNext, 0
  revealNext = false

  local nWalk, nFly = 0, 0
  for _, s in ipairs(current.segments) do
    local ax, ay = norm(s[1], s[2])
    local bx, by = norm(s[3], s[4])
    if ax and bx then
      local x1, y1, x2, y2 = clip(ax, ay, bx, by)
      if x1 then
        local flight = s[5] == "fly"
        local hd
        if flight then nFly = nFly + 1; hd = lineHolder(flyLines, nFly, true)
        else nWalk = nWalk + 1; hd = lineHolder(walkLines, nWalk, false) end
        local done = current.stops[s[6]].done
        local c = COLOR[s[5]] or COLOR.walk
        if flight then
          hd.Fill:SetVertexColor(1, 1, 1, done and 0.3 or 1)
          hd.Fill:SetThickness(FLY_LINE / scale)
        else
          hd.Fill:SetColorTexture(c[1], c[2], c[3], done and 0.3 or 0.95)
          hd.Fill:SetThickness(WALK_LINE / scale)
          hd.Edge:SetAlpha(done and 0.2 or 1)
          hd.Edge:SetThickness((WALK_LINE + 2) / scale)
        end
        for _, part in ipairs(flight and { hd.Fill } or { hd.Fill, hd.Edge }) do
          part:SetStartPoint("TOPLEFT", layer, x1 * w, -y1 * h)
          part:SetEndPoint("TOPLEFT", layer, x2 * w, -y2 * h)
        end
        hd:Show()
        if reveal then
          hd.reveal:Stop()
          for _, a in ipairs({ hd.reveal:GetAnimations() }) do a:SetStartDelay(delay) end
          hd.reveal:Play()
          delay = delay + 0.06
        end
      end
    end
  end

  local nextK = nextStop()
  local count = 0
  local function place(x, y, text, color, group, done, isNext)
    local nx, ny = norm(x, y)
    if not nx or nx < 0 or nx > 1 or ny < 0 or ny > 1 then return end
    count = count + 1
    local f = marker(count)
    -- as Blizzard's map pins: the marker frame is scaled by 1/zoom so it keeps its size on
    -- screen, and its offsets are divided by that scale (MapCanvasMixin:ApplyPinPosition)
    local size = #text > 2 and MARKER * 1.3 or MARKER
    local pinScale = 1 / scale
    f:SetScale(pinScale)
    f:ClearAllPoints()
    f:SetSize(size, size)
    f:SetPoint("CENTER", layer, "TOPLEFT", nx * w / pinScale, -ny * h / pinScale)
    f.fill:SetColorTexture(color[1], color[2], color[3], 1)
    f.label:SetText(text)
    f.glow:SetSize(size * 2.4, size * 2.4)
    f.glow:SetShown(isNext)
    if isNext then f.pulse:Play() end
    f:SetAlpha(done and 0.45 or 1)
    f.group = group
    f.stop = nil
    if group then
      f.stop = group[1]
      for _, k in ipairs(group) do if not current.stops[k].done then f.stop = k; break end end
    end
    f:Show()
  end
  place(current.start.x, current.start.y, "", { 0.85, 0.85, 0.85 }, nil, true, false)
  for _, g in ipairs(current.groups) do
    local labels, lead, allDone, hasNext = {}, nil, true, false
    for _, k in ipairs(g) do
      labels[#labels + 1] = tostring(k)
      local s = current.stops[k]
      if not s.done then allDone = false; lead = lead or s end
      if k == nextK then hasNext = true end
    end
    lead = lead or current.stops[g[1]]
    place(lead.x, lead.y, table.concat(labels, ","), COLOR[lead.kind] or COLOR.walk, g, allDone, hasNext)
  end
end

function provider:OnCanvasScaleChanged() self:RefreshAllData() end
function provider:OnCanvasSizeChanged() self:RefreshAllData() end

local attached = false
local function attach()
  if attached or not WorldMapFrame then return end
  WorldMapFrame:AddDataProvider(provider)
  attached = true
end
View.provider = provider

local function refreshMap()
  attach()
  if attached and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end

-- Plan window ---------------------------------------------------------------------------------
local win
local ROW_TOP = 112 -- below the title, progress bar and next-stop panel

local function createWindow()
  local f = CreateFrame("Frame", "AtlasRoutePlanFrame", UIParent, "BackdropTemplate")
  f:SetBackdrop(BACKDROP_DARK_DIALOG_32_32)
  f:SetSize(420, 200)
  f:SetPoint("RIGHT", UIParent, "RIGHT", -80, 0)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 20, -18)
  f.title:SetText("AtlasRoute")
  f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 8, -1)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- progress bar
  f.bar = f:CreateTexture(nil, "ARTWORK")
  f.bar:SetPoint("TOPLEFT", 20, -44)
  f.bar:SetPoint("RIGHT", f, "RIGHT", -20, 0)
  f.bar:SetHeight(14)
  f.bar:SetColorTexture(0, 0, 0, 0.6)
  f.barFill = f:CreateTexture(nil, "ARTWORK", nil, 1)
  f.barFill:SetPoint("TOPLEFT", f.bar, "TOPLEFT", 1, -1)
  f.barFill:SetHeight(12)
  f.barFill:SetColorTexture(1, 0.82, 0, 0.85)
  f.barText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
  f.barText:SetPoint("CENTER", f.bar, "CENTER")

  -- next stop
  f.nextBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.nextBg:SetPoint("TOPLEFT", 16, -64)
  f.nextBg:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  f.nextBg:SetHeight(40)
  f.nextBg:SetColorTexture(1, 0.82, 0, 0.1)
  f.nextLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.nextLabel:SetPoint("TOPLEFT", f.nextBg, "TOPLEFT", 6, -5)
  f.nextLabel:SetText("NEXT")
  f.nextName = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.nextName:SetPoint("LEFT", f.nextLabel, "RIGHT", 8, 0)
  f.nextName:SetPoint("RIGHT", f.nextBg, "RIGHT", -6, 0)
  f.nextName:SetJustifyH("LEFT")
  f.nextName:SetWordWrap(false)
  f.nextInfo = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.nextInfo:SetPoint("TOPLEFT", f.nextLabel, "BOTTOMLEFT", 0, -5)
  f.nextInfo:SetTextColor(0.8, 0.8, 0.8)

  f.rows = {}
  for i = 1, MAX_ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", 16, -ROW_TOP - (i - 1) * 18)
    r:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.12)
    r.hl:Hide()
    r.cur = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.cur:SetAllPoints()
    r.cur:SetColorTexture(1, 0.82, 0, 0.12)
    r.dot = round(r, "ARTWORK")
    r.dot:SetSize(10, 10)
    r.dot:SetPoint("LEFT", 4, 0)
    r.check = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.check:SetAtlas(CHECK)
    r.check:SetSize(14, 14)
    r.check:SetPoint("CENTER", r.dot, "CENTER")
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.dot, "RIGHT", 7, 0)
    r.text:SetPoint("RIGHT", r, "RIGHT", -96, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.mode = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.mode:SetPoint("RIGHT", r, "RIGHT", -52, 0)
    r.time = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.time:SetPoint("RIGHT", -4, 0)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
      if button == "RightButton" then View.toggle(self.stop) else View.waypoint(self.stop) end
    end)
    r:SetScript("OnEnter", function(self)
      self.hl:Show()
      local s = current and current.stops[self.stop]
      if not s then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(s.name)
      GameTooltip:AddLine(s.travel, 1, 1, 1, true)
      GameTooltip:AddLine("Left-click: arrow   Right-click: done", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    r:Hide()
    f.rows[i] = r
  end
  f.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.hint:SetPoint("BOTTOMLEFT", 20, 18)
  f.hint:SetText("Left-click: arrow   Right-click: done")

  f.replan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.replan:SetSize(80, 22)
  f.replan:SetPoint("BOTTOMRIGHT", -16, 14)
  f.replan:SetText("Replan")
  f.replan:SetScript("OnClick", function() ns.commands.plan() end)
  f.mapButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.mapButton:SetSize(80, 22)
  f.mapButton:SetPoint("RIGHT", f.replan, "LEFT", -6, 0)
  f.mapButton:SetText("Map")
  f.mapButton:SetScript("OnClick", function() ToggleWorldMap() end)

  -- live distance to the next stop, twice a second
  f.elapsed = 0
  f:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + (elapsed or 0)
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    View.updateNext()
  end)
  return f
end

local MODE_TEXT = { fly = "|cff66ccfffly|r", hearth = "|cff66ff66hearth|r" }

function View.updateNext()
  if not win or not current then return end
  local k = nextStop()
  if not k then
    win.nextName:SetText("|cff4de64dRoute complete|r")
    win.nextInfo:SetText("Every stop is done. Replan for the next round.")
    return
  end
  local s = current.stops[k]
  local c = COLOR[s.kind] or COLOR.walk
  win.nextName:SetText(("|c%s%d. %s|r"):format(hex(c), k, s.name))
  local x, y, cont = ns.playerPos()
  if x and cont == current.continent then
    local d = math.sqrt((s.x - x) ^ 2 + (s.y - y) ^ 2)
    win.nextInfo:SetText(("%d yd away  -  %s planned  -  %s"):format(d + 0.5, fmtTime(s.seconds), KIND[s.kind] or s.kind))
  else
    win.nextInfo:SetText(("%s planned  -  %s"):format(fmtTime(s.seconds), KIND[s.kind] or s.kind))
  end
end

local function refreshWindow()
  if not current then return end
  win = win or createWindow()
  local left, done = 0, 0
  for _, s in ipairs(current.stops) do
    if s.done then done = done + 1 else left = left + s.seconds end
  end
  local total = #current.stops
  win.subtitle:SetText(("%d stops, %s of travel"):format(total, fmtTime(current.seconds)))
  local barW = (win:GetWidth() or 420) - 42
  win.barFill:SetWidth(math.max(0.001, barW * (total > 0 and done / total or 0)))
  win.barText:SetText(("%d / %d done  -  %s left"):format(done, total, fmtTime(left)))
  local nextK = nextStop()
  local shown = math.min(total, MAX_ROWS)
  for i, r in ipairs(win.rows) do
    local s = current.stops[i]
    if s and i <= shown then
      r.stop = i
      local c = COLOR[s.kind] or COLOR.walk
      r.dot:SetColorTexture(c[1], c[2], c[3], 1)
      r.dot:SetShown(not s.done)
      r.check:SetShown(s.done)
      r.cur:SetShown(i == nextK)
      local name = ("%d. %s"):format(i, s.name)
      r.text:SetText(s.done and ("|cff808080" .. name .. "|r") or name)
      r.mode:SetText((s.modes.fly and MODE_TEXT.fly) or (s.modes.hearth and MODE_TEXT.hearth) or "")
      r.time:SetText(fmtTime(s.seconds))
      r:SetAlpha(s.done and 0.7 or 1)
      r:Show()
    else
      r:Hide()
    end
  end
  win.more:ClearAllPoints()
  win.more:SetPoint("TOPLEFT", 20, -ROW_TOP - shown * 18 - 2)
  win.more:SetText(total > shown and ("... %d more stops (see chat)"):format(total - shown) or "")
  win:SetHeight(ROW_TOP + shown * 18 + (total > shown and 16 or 0) + 50)
  View.updateNext()
  win:Show()
end

-- Public --------------------------------------------------------------------------------------
function View.show(model)
  current = model
  revealNext = true
  refreshWindow()
  refreshMap()
end

function View.toggle(k)
  local s = current and current.stops[k]
  if not s then return end
  s.done = not s.done
  refreshWindow()
  refreshMap()
  if s.done then -- point the arrow at the next stop still to do
    for j = k + 1, #current.stops do
      if not current.stops[j].done then View.waypoint(j); return end
    end
  end
end

-- A quest event: tick off its stops of that kind.
function View.questEvent(questID, kinds)
  if not current then return end
  for k, s in ipairs(current.stops) do
    if s.quest == questID and kinds[s.kind] and not s.done then View.toggle(k) end
  end
end

function View.toggleWindow()
  if not current then ns.out("No plan yet: /ar plan"); return end
  win = win or createWindow()
  if win:IsShown() then win:Hide() else refreshWindow() end
end

function View.current() return current end
function View.window() return win end

local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:SetScript("OnEvent", function(_, event, questID)
  if event == "QUEST_ACCEPTED" then
    View.questEvent(questID, { accept = true })
  elseif event == "QUEST_TURNED_IN" then
    View.questEvent(questID, { accept = true, objective = true, turnin = true })
  elseif event == "QUEST_LOG_UPDATE" and current then
    for _, s in ipairs(current.stops) do
      if s.kind == "objective" and not s.done and s.quest and C_QuestLog.IsComplete(s.quest) then
        View.questEvent(s.quest, { objective = true })
      end
    end
  end
end)
attach()
