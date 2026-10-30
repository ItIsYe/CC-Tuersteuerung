-- ============================================================
--  Tuersteuerung (CC:Tweaked + Advanced Peripherals + Create Crafts & Additions)
--
--  Monitor ENTSPERREN : Button -> prueft Whitelist (gruen/rot)
--  Monitor TUER AUF   : Button -> oeffnet ohne Pruefung
--  Monitor STEUERUNG  : Modus (Automatik/Gesperrt/Dauerauf), Motor, Log
--  Detektor FREI      : Seite, auf der die Tuer fuer JEDEN automatisch oeffnet
--  Detektor WHITELIST : Seite, auf der nur Whitelist-Spieler Zugang bekommen
--  Relay              : Redstone-Ausgang (standardmaessig alle 6 Seiten)
--  Motor              : Electric Motor (Create Crafts & Additions), nur RPM
--
--  Alle Einstellungen laufen ueber das Menue am Computer-Terminal
--  und werden in "door_settings" gespeichert. Beim ersten Start fuehrt
--  ein Assistent durch die Zuweisung der Monitore und Detektoren.
--  Fuer Autostart als "startup.lua" speichern.
-- ============================================================

local SETTINGS_FILE = "door_settings"
local ALL_SIDES = { "top", "bottom", "left", "right", "front", "back" }

local MON_TYPES   = { "monitor" }
local DET_TYPES   = { "player_detector", "playerDetector" }
local RELAY_TYPES = { "redstone_relay", "redstoneIntegrator" }
local MOTOR_TYPES = { "electric_motor" }

-- ------------------------------------------------------------
--  Einstellungen
-- ------------------------------------------------------------
local cfg = {}

local function loadSettings()
  cfg = {
    monitorAuth = nil, monitorOpen = nil, monitorControl = nil,
    detectorFree = nil, detectorWhitelist = nil,
    relay = nil, motor = nil,
    relaySides = { table.unpack(ALL_SIDES) },
    relayInvert = false,       -- false: Signal AN = Tuer offen
    motorRpm = 32,
    openTime = 5,              -- Sekunden offen nach Oeffnen / letzter Erkennung
    freeRange = 4,             -- Radius Detektor FREI
    whitelistRange = 3,        -- Radius Detektor WHITELIST
    holdRange = 2,             -- Tuer schliesst nicht, solange ein Spieler so nah an einem Detektor steht
    mode = "auto",             -- gespeicherter Modus (auto | locked | open)
    motorOn = false,           -- gespeicherter Motorzustand
    whitelistSideAuto = false, -- Whitelist-Seite oeffnet auch automatisch fuer Whitelist-Spieler
    feedbackTime = 3,
    logSize = 4,
    whitelistFile = "whitelist.txt",
  }
  if fs.exists(SETTINGS_FILE) then
    local f = fs.open(SETTINGS_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    if type(data) == "table" then
      for k, v in pairs(data) do cfg[k] = v end
    end
  end
end

local function saveSettings()
  local f = fs.open(SETTINGS_FILE, "w")
  f.write(textutils.serialize(cfg))
  f.close()
end

loadSettings()

-- ------------------------------------------------------------
--  Whitelist
-- ------------------------------------------------------------
local whitelist = {}

local function loadWhitelist()
  whitelist = {}
  if not fs.exists(cfg.whitelistFile) then
    fs.open(cfg.whitelistFile, "w").close()
    return
  end
  local f = fs.open(cfg.whitelistFile, "r")
  while true do
    local line = f.readLine()
    if not line then break end
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then whitelist[line:lower()] = line end
  end
  f.close()
end

local function saveWhitelist()
  local names = {}
  for _, n in pairs(whitelist) do names[#names + 1] = n end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  local f = fs.open(cfg.whitelistFile, "w")
  for _, n in ipairs(names) do f.writeLine(n) end
  f.close()
end

loadWhitelist()

-- ------------------------------------------------------------
--  Peripherals
-- ------------------------------------------------------------
local P = { mon = {}, detFree = nil, detWL = nil, relay = nil, motor = nil }

local function now() return os.epoch("utc") / 1000 end

local function tryWrap(name)
  if name and peripheral.isPresent(name) then return peripheral.wrap(name) end
end

local function findFirst(types)
  for _, t in ipairs(types) do
    local p = peripheral.find(t)
    if p then return p end
  end
end

local function listByTypes(types)
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(n)
    for _, ty in ipairs(types) do
      if t == ty then out[#out + 1] = n; break end
    end
  end
  return out
end

-- groesste Textgroesse waehlen, bei der das Layout noch passt
local function autoScale(m, minW, minH)
  for _, s in ipairs({ 5, 4, 3, 2.5, 2, 1.5, 1, 0.5 }) do
    m.setTextScale(s)
    local w, h = m.getSize()
    if w >= minW and h >= minH then return end
  end
  m.setTextScale(0.5)
end

local function applyPeripherals()
  P.mon.auth = tryWrap(cfg.monitorAuth)
  P.mon.open = tryWrap(cfg.monitorOpen)
  P.mon.ctrl = tryWrap(cfg.monitorControl)
  P.detFree  = tryWrap(cfg.detectorFree)
  P.detWL    = tryWrap(cfg.detectorWhitelist)
  P.relay    = tryWrap(cfg.relay) or findFirst(RELAY_TYPES)
  P.motor    = tryWrap(cfg.motor) or findFirst(MOTOR_TYPES)
  if P.mon.auth then autoScale(P.mon.auth, 10, 3) end
  if P.mon.open then autoScale(P.mon.open, 8, 3) end
  if P.mon.ctrl then autoScale(P.mon.ctrl, 21, 12) end
end

-- ------------------------------------------------------------
--  Zustand
-- ------------------------------------------------------------
local MODE_LABEL = { auto = "AUTOMATIK", locked = "GESPERRT", open = "DAUERAUF" }

local state = {
  mode = MODE_LABEL[cfg.mode] and cfg.mode or "auto",  -- auto | locked | open
  doorOpen = false,
  openUntil = 0,
  motorOn = cfg.motorOn == true,
  feedback = nil,     -- {ok, title, sub, expires}
  log = {},
  autoSeen = false,
}

local buttons = {}
local lastSig = ""
local function invalidate() lastSig = "" end

local function addLog(text)
  table.insert(state.log, 1, textutils.formatTime(os.time(), true) .. " " .. text)
  while #state.log > cfg.logSize do table.remove(state.log) end
end

local function writeDoor(open)
  if not P.relay then return end
  local out = open
  if cfg.relayInvert then out = not open end
  local enabled = {}
  for _, s in ipairs(cfg.relaySides) do enabled[s] = true end
  for _, s in ipairs(ALL_SIDES) do
    pcall(P.relay.setOutput, s, enabled[s] and out or false)
  end
end

local function setDoor(open)
  if state.doorOpen ~= open then
    state.doorOpen = open
    writeDoor(open)
  end
end

local function setMotor(on)
  state.motorOn = on
  if not P.motor then return end
  if on then
    pcall(P.motor.setSpeed, math.abs(cfg.motorRpm))
  else
    pcall(P.motor.stop)
  end
end

-- ------------------------------------------------------------
--  Erkennung / Berechtigung
-- ------------------------------------------------------------
local function playersIn(det, range)
  if not det then return {} end
  local ok, p = pcall(det.getPlayersInRange, range)
  if ok and type(p) == "table" then return p end
  return {}
end

local function firstWhitelisted(list)
  for _, p in ipairs(list) do
    if whitelist[p:lower()] then return p end
  end
end

-- returns granted(bool), name/hinweis
local function checkAccess()
  if not P.detWL then return false, "Kein Detektor" end
  local players = playersIn(P.detWL, cfg.whitelistRange)
  if #players == 0 then return false, "Kein Spieler erkannt" end
  local who = firstWhitelisted(players)
  if who then return true, who end
  return false, players[1]
end

local function showFeedback(ok, title, sub)
  state.feedback = { ok = ok, title = title, sub = sub,
                     expires = now() + cfg.feedbackTime }
end

local function openDoorTimed()
  state.openUntil = math.max(state.openUntil, now() + cfg.openTime)
  setDoor(true)
end

-- ------------------------------------------------------------
--  Aktionen (Touch)
-- ------------------------------------------------------------
local actions = {}

actions.auth = function()
  if state.mode == "locked" then
    showFeedback(false, "GESPERRT", "Zugang deaktiviert")
    return
  end
  local ok, who = checkAccess()
  if ok then
    showFeedback(true, "ZUGANG ERTEILT", who)
    addLog("OK " .. who)
    openDoorTimed()
  else
    showFeedback(false, "ZUGANG VERWEIGERT", who)
    addLog("NEIN " .. tostring(who))
  end
end

actions.open = function()
  if state.mode == "locked" then return end
  addLog("Taster")
  openDoorTimed()
end

local function setMode(mode, label)
  state.mode = mode
  cfg.mode = mode
  saveSettings()
  addLog(label)
end

actions.mode_auto   = function() setMode("auto", "Automatik") end
actions.mode_locked = function() setMode("locked", "Gesperrt") end
actions.mode_open   = function() setMode("open", "Dauerauf") end
actions.motor = function()
  setMotor(not state.motorOn)
  cfg.motorOn = state.motorOn
  saveSettings()
  addLog("Motor " .. (state.motorOn and "AN" or "AUS"))
end

local function handleTouch(name, x, y)
  local list = buttons[name]
  if not list then return end
  for _, b in ipairs(list) do
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
      if actions[b.id] then actions[b.id]() end
      return
    end
  end
end

-- ------------------------------------------------------------
--  Logik-Tick
-- ------------------------------------------------------------
local lastSync = 0

local function tick()
  local t = now()

  if t - lastSync > 10 then
    lastSync = t
    writeDoor(state.doorOpen)
  end

  if state.feedback and t >= state.feedback.expires then
    state.feedback = nil
  end

  if state.mode == "locked" then
    setDoor(false)
  elseif state.mode == "open" then
    setDoor(true)
  else
    -- Freie Seite: jeder Spieler
    local who = playersIn(P.detFree, cfg.freeRange)[1]
    local via = "Frei"
    -- Whitelist-Seite: optional automatisch fuer Whitelist-Spieler
    if not who and cfg.whitelistSideAuto then
      who = firstWhitelisted(playersIn(P.detWL, cfg.whitelistRange))
      via = "WL"
    end
    local seen = who ~= nil
    if seen then
      if not state.autoSeen then addLog(via .. ": " .. who) end
      state.openUntil = math.max(state.openUntil, t + cfg.openTime)
      setDoor(true)
    elseif state.doorOpen and t >= state.openUntil then
      -- nicht schliessen, solange jemand direkt an einem Detektor steht
      if #playersIn(P.detFree, cfg.holdRange) > 0
         or #playersIn(P.detWL, cfg.holdRange) > 0 then
        state.openUntil = t + 1
      else
        setDoor(false)
      end
    end
    state.autoSeen = seen
  end
end

-- ------------------------------------------------------------
--  Zeichnen
-- ------------------------------------------------------------
local function fill(m, x1, y1, x2, y2, bg)
  m.setBackgroundColor(bg)
  local line = string.rep(" ", math.max(0, x2 - x1 + 1))
  for y = y1, y2 do
    m.setCursorPos(x1, y)
    m.write(line)
  end
end

local function center(m, x1, x2, y, text, fg, bg)
  local w = x2 - x1 + 1
  text = tostring(text):sub(1, w)
  m.setTextColor(fg)
  m.setBackgroundColor(bg)
  m.setCursorPos(x1 + math.floor((w - #text) / 2), y)
  m.write(text)
end

local function button(m, list, id, x1, y1, x2, y2, label, bg, fg)
  fill(m, x1, y1, x2, y2, bg)
  center(m, x1, x2, math.floor((y1 + y2) / 2), label, fg or colors.white, bg)
  list[#list + 1] = { id = id, x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

local function drawAuth()
  local m = P.mon.auth
  if not m then return end
  local w, h = m.getSize()
  local list = {}
  local fb = state.feedback
  if fb then
    local bg = fb.ok and colors.green or colors.red
    fill(m, 1, 1, w, h, bg)
    local y = math.max(1, math.floor(h / 2))
    center(m, 1, w, y, fb.title, colors.white, bg)
    if fb.sub and h >= 2 then center(m, 1, w, y + 1, fb.sub, colors.white, bg) end
  else
    m.setBackgroundColor(colors.black)
    m.clear()
    if state.mode == "locked" then
      button(m, list, "auth", 1, 1, w, h, "GESPERRT", colors.gray, colors.red)
    else
      button(m, list, "auth", 1, 1, w, h, "ENTSPERREN", colors.blue)
    end
  end
  buttons[cfg.monitorAuth] = list
end

local function drawOpen()
  local m = P.mon.open
  if not m then return end
  local w, h = m.getSize()
  local list = {}
  m.setBackgroundColor(colors.black)
  m.clear()
  if state.mode == "locked" then
    button(m, list, "open", 1, 1, w, h, "GESPERRT", colors.gray, colors.red)
  else
    button(m, list, "open", 1, 1, w, h, "TUER AUF",
      state.doorOpen and colors.orange or colors.green)
  end
  buttons[cfg.monitorOpen] = list
end

local function drawControl()
  local m = P.mon.ctrl
  if not m then return end
  local w, h = m.getSize()
  local list = {}

  m.setBackgroundColor(colors.black)
  m.clear()

  fill(m, 1, 1, w, 1, colors.blue)
  center(m, 1, w, 1, "TUERSTEUERUNG", colors.white, colors.blue)

  m.setBackgroundColor(colors.black)
  m.setCursorPos(1, 2)
  m.setTextColor(colors.white); m.write("Tuer:  ")
  m.setTextColor(state.doorOpen and colors.green or colors.red)
  m.write(state.doorOpen and "OFFEN" or "ZU")

  m.setCursorPos(1, 3)
  m.setTextColor(colors.white); m.write("Modus: ")
  m.setTextColor(colors.yellow); m.write(MODE_LABEL[state.mode])

  m.setCursorPos(1, 4)
  m.setTextColor(colors.white); m.write("Motor: ")
  if not P.motor then
    m.setTextColor(colors.gray); m.write("nicht gefunden")
  elseif state.motorOn then
    m.setTextColor(colors.green); m.write("AN (" .. math.abs(cfg.motorRpm) .. " RPM)")
  else
    m.setTextColor(colors.red); m.write("AUS")
  end

  local top = 6
  local logReserve = (h >= 22) and (cfg.logSize + 1) or 0
  local bottom = h - logReserve
  local avail = bottom - top + 1
  local gap = (avail >= 7) and 1 or 0
  local rowH = math.max(1, math.floor((avail - gap) / 2))

  local half = math.floor((w - 1) / 2)
  local lx1, lx2 = 1, half
  local rx1, rx2 = half + 2, w

  local function rowY(r) return top + (r - 1) * (rowH + gap) end
  local function modeColor(mode, active)
    return state.mode == mode and active or colors.gray
  end

  button(m, list, "mode_auto",   lx1, rowY(1), lx2, rowY(1) + rowH - 1,
    "AUTOMATIK", modeColor("auto", colors.green))
  button(m, list, "mode_locked", rx1, rowY(1), rx2, rowY(1) + rowH - 1,
    "GESPERRT", modeColor("locked", colors.red))

  if P.motor then
    button(m, list, "mode_open", lx1, rowY(2), lx2, rowY(2) + rowH - 1,
      "DAUERAUF", modeColor("open", colors.orange))
    button(m, list, "motor", rx1, rowY(2), rx2, rowY(2) + rowH - 1,
      state.motorOn and "MOTOR: AN" or "MOTOR: AUS",
      state.motorOn and colors.green or colors.gray)
  else
    button(m, list, "mode_open", 1, rowY(2), w, rowY(2) + rowH - 1,
      "DAUERAUF", modeColor("open", colors.orange))
  end

  if logReserve > 0 then
    local y0 = bottom + 1
    m.setBackgroundColor(colors.black)
    m.setTextColor(colors.lightGray)
    m.setCursorPos(1, y0)
    m.write("Letzte Zugriffe:")
    m.setTextColor(colors.white)
    for i, entry in ipairs(state.log) do
      m.setCursorPos(1, y0 + i)
      m.write(entry:sub(1, w))
    end
  end

  buttons[cfg.monitorControl] = list
end

local function redraw(force)
  local fb = state.feedback
  local sig = table.concat({
    state.mode, tostring(state.doorOpen), tostring(state.motorOn),
    tostring(cfg.motorRpm), tostring(P.motor ~= nil),
    fb and (fb.title .. tostring(fb.sub)) or "-",
    table.concat(state.log, "|"),
  }, ";")
  if not force and sig == lastSig then return end
  lastSig = sig
  drawAuth()
  drawOpen()
  drawControl()
end

-- ------------------------------------------------------------
--  Terminal-Menue (Einstellungen)
-- ------------------------------------------------------------
local function ask(prompt, default)
  write(prompt)
  return read(nil, nil, nil, default ~= nil and tostring(default) or nil)
end

local function askNumber(prompt, current, min, max)
  local v = tonumber(ask(prompt .. " [" .. min .. "-" .. max .. "]: ", current))
  if not v then return current end
  return math.max(min, math.min(max, v))
end

local function pickFrom(list, current, info)
  for i, n in ipairs(list) do
    local line = " " .. i .. ") " .. n
    if info then line = line .. "  " .. info(n) end
    if n == current then line = line .. "  (aktuell)" end
    print(line)
  end
  write("Nummer (Enter = behalten): ")
  local i = tonumber(read())
  return list[i] or current
end

local function labelMonitor(name, text)
  local m = peripheral.wrap(name)
  if not m then return end
  m.setBackgroundColor(colors.black)
  m.setTextColor(colors.white)
  m.clear()
  m.setCursorPos(1, 1)
  m.write(text)
end

local function assignMonitors()
  local list = listByTypes(MON_TYPES)
  if #list == 0 then print("Keine Monitore gefunden."); sleep(2); return end
  for i, n in ipairs(list) do
    local m = peripheral.wrap(n)
    m.setTextScale(1)
    m.setBackgroundColor(colors.black)
    m.setTextColor(colors.white)
    m.clear()
    m.setCursorPos(1, 1); m.write("#" .. i)
    m.setCursorPos(1, 2); m.write(n)
  end
  print("Jeder Monitor zeigt seine Nummer.")
  print("")
  print("Monitor ENTSPERREN (Whitelist-Button):")
  cfg.monitorAuth = pickFrom(list, cfg.monitorAuth)
  if cfg.monitorAuth then labelMonitor(cfg.monitorAuth, "ENTSPERREN") end
  print("")
  print("Monitor TUER AUF (Taster):")
  cfg.monitorOpen = pickFrom(list, cfg.monitorOpen)
  if cfg.monitorOpen then labelMonitor(cfg.monitorOpen, "TUER AUF") end
  print("")
  print("Monitor STEUERUNG:")
  cfg.monitorControl = pickFrom(list, cfg.monitorControl)
  if cfg.monitorControl then labelMonitor(cfg.monitorControl, "STEUERUNG") end
  saveSettings()
  applyPeripherals()
  buttons = {}
  invalidate()
end

local function assignDetectors()
  local list = listByTypes(DET_TYPES)
  if #list == 0 then print("Keine Player Detectors gefunden."); sleep(2); return end
  print("Spieler in 6 Bloecken Reichweite je Detektor")
  print("(stell dich an eine Seite, um sie zuzuordnen):")
  print("")
  local function info(n)
    local d = peripheral.wrap(n)
    local ok, p = pcall(d.getPlayersInRange, 6)
    if ok and type(p) == "table" and #p > 0 then
      return "[" .. table.concat(p, ", ") .. "]"
    end
    return "[-]"
  end
  print("Detektor FREIE Seite (oeffnet automatisch fuer jeden):")
  cfg.detectorFree = pickFrom(list, cfg.detectorFree, info)
  print("")
  print("Detektor WHITELIST-Seite (Pruefung per Button):")
  cfg.detectorWhitelist = pickFrom(list, cfg.detectorWhitelist, info)
  saveSettings()
  applyPeripherals()
  invalidate()
end

local function whitelistMenu()
  while true do
    term.clear(); term.setCursorPos(1, 1)
    print("== Whitelist ==")
    local names = {}
    for _, n in pairs(whitelist) do names[#names + 1] = n end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    if #names == 0 then print(" (leer)") end
    for _, n in ipairs(names) do print(" " .. n) end
    print("")
    print("add <name> | remove <name> | zurueck")
    write("> ")
    local line = read()
    local cmd, arg = line:match("^(%S+)%s*(.-)%s*$")
    if cmd == "add" and arg ~= "" then
      whitelist[arg:lower()] = arg
      saveWhitelist()
    elseif cmd == "remove" and arg ~= "" then
      whitelist[arg:lower()] = nil
      saveWhitelist()
    elseif cmd == "zurueck" or cmd == "back" or cmd == "q" or cmd == nil then
      return
    end
  end
end

local function relayMenu()
  print("Aktive Seiten: " .. table.concat(cfg.relaySides, " "))
  print("Verfuegbar: " .. table.concat(ALL_SIDES, " "))
  local s = ask("Seiten (Leerzeichen getrennt, 'alle'): ", table.concat(cfg.relaySides, " "))
  local sides = {}
  if s:lower() == "alle" then
    sides = { table.unpack(ALL_SIDES) }
  else
    for w in s:gmatch("%S+") do
      for _, valid in ipairs(ALL_SIDES) do
        if w:lower() == valid then sides[#sides + 1] = valid end
      end
    end
  end
  if #sides > 0 then cfg.relaySides = sides end
  local inv = ask("Signal invertieren? (j/n): ", cfg.relayInvert and "j" or "n")
  cfg.relayInvert = (inv:lower() == "j")
  saveSettings()
  writeDoor(state.doorOpen)
end

local function diagnose()
  term.clear(); term.setCursorPos(1, 1)
  print("== Diagnose (beliebige Taste = Ende) ==")

  local function det(label, d, range)
    if not d then return label .. ": NICHT ZUGEWIESEN/GEFUNDEN" end
    local ok, p = pcall(d.getPlayersInRange, range)
    if ok and type(p) == "table" then
      return label .. " r=" .. range .. ": " .. (#p > 0 and table.concat(p, ",") or "-")
    end
    return label .. " FEHLER: " .. tostring(p)
  end

  local function loop()
    while true do
      local lines = {
        det("FREI  ", P.detFree, cfg.freeRange),
        det("FREI-H", P.detFree, cfg.holdRange),
        det("WL    ", P.detWL, cfg.whitelistRange),
        det("WL-H  ", P.detWL, cfg.holdRange),
        "Modus: " .. state.mode .. "  Tuer: " .. (state.doorOpen and "offen" or "zu"),
        "Rest offen: " .. math.max(0, math.floor(state.openUntil - now())) .. "s",
        "Relay: " .. (P.relay and peripheral.getName(P.relay) or "KEINES"),
        "Detektor FREI: " .. tostring(cfg.detectorFree),
        "Detektor WL:   " .. tostring(cfg.detectorWhitelist),
      }
      for i, l in ipairs(lines) do
        term.setCursorPos(1, 2 + i)
        term.clearLine()
        write(l)
      end
      sleep(0.5)
    end
  end

  parallel.waitForAny(loop, function() os.pullEvent("key") end)
end

local function menu()
  while true do
    term.clear(); term.setCursorPos(1, 1)
    print("== Tuersteuerung ==")
    print("1) Whitelist verwalten")
    print("2) Detektoren zuweisen")
    print("3) Monitore zuweisen")
    print("4) Motor-RPM (" .. math.abs(cfg.motorRpm) .. ")")
    print("5) Zeiten/Reichweiten (offen " .. cfg.openTime .. "s)")
    print("6) Relay-Seiten (" .. #cfg.relaySides .. " aktiv, invert: "
      .. (cfg.relayInvert and "ja" or "nein") .. ")")
    print("7) Auto-Oeffnen Whitelist-Seite: "
      .. (cfg.whitelistSideAuto and "AN" or "AUS"))
    print("8) Diagnose (Detektoren live)")
    write("> ")
    local c = read()
    if c == "1" then
      whitelistMenu()
    elseif c == "2" then
      term.clear(); term.setCursorPos(1, 1); assignDetectors()
    elseif c == "3" then
      term.clear(); term.setCursorPos(1, 1); assignMonitors()
    elseif c == "4" then
      cfg.motorRpm = askNumber("RPM", math.abs(cfg.motorRpm), 1, 256)
      saveSettings()
      if state.motorOn then setMotor(true) end
      invalidate()
    elseif c == "5" then
      cfg.openTime = askNumber("Sekunden offen", cfg.openTime, 1, 120)
      cfg.freeRange = askNumber("Reichweite freie Seite (Bloecke)", cfg.freeRange, 1, 64)
      cfg.whitelistRange = askNumber("Reichweite Whitelist-Seite (Bloecke)", cfg.whitelistRange, 1, 64)
      cfg.holdRange = askNumber("Halte-Radius: Tuer bleibt offen (Bloecke)", cfg.holdRange, 1, 8)
      cfg.feedbackTime = askNumber("Rueckmeldung auf Monitor (Sek.)", cfg.feedbackTime, 1, 30)
      saveSettings()
    elseif c == "6" then
      term.clear(); term.setCursorPos(1, 1); relayMenu()
    elseif c == "7" then
      cfg.whitelistSideAuto = not cfg.whitelistSideAuto
      saveSettings()
    elseif c == "8" then
      diagnose()
    end
  end
end

-- ------------------------------------------------------------
--  Hauptschleife
-- ------------------------------------------------------------
local function mainLoop()
  writeDoor(state.doorOpen)
  setMotor(state.motorOn)
  tick()
  redraw(true)
  local timer = os.startTimer(0.5)
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "timer" and a == timer then
      tick()
      redraw()
      timer = os.startTimer(0.5)
    elseif ev == "monitor_touch" then
      handleTouch(a, b, c)
      tick()
      redraw()
    elseif ev == "monitor_resize" then
      invalidate()
      redraw()
    elseif ev == "peripheral" or ev == "peripheral_detach" then
      applyPeripherals()
      if state.motorOn then setMotor(true) end
      writeDoor(state.doorOpen)
      buttons = {}
      invalidate()
      redraw()
    end
  end
end

-- ------------------------------------------------------------
--  Start
-- ------------------------------------------------------------
local function setupComplete()
  return cfg.monitorAuth and cfg.monitorOpen and cfg.monitorControl
    and cfg.detectorFree and cfg.detectorWhitelist
end

applyPeripherals()

if not setupComplete() then
  term.clear(); term.setCursorPos(1, 1)
  print("== Ersteinrichtung ==")
  print("")
  assignMonitors()
  print("")
  assignDetectors()
  if not setupComplete() then
    error("Einrichtung unvollstaendig - Programm neu starten", 0)
  end
end

if not P.relay then error("Kein Redstone Relay gefunden", 0) end

parallel.waitForAny(mainLoop, menu)
