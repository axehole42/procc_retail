-- ProcSounds - combat log parsing and alert cues (self-only)
local ADDON_NAME = "ProcSounds"

local SOUND = {
  PROC         = "Interface\\AddOns\\ProcSounds\\Sounds\\proc.mp3",
  EXECUTE      = "Interface\\AddOns\\ProcSounds\\Sounds\\execute_proc.mp3",
  EXECUTE_EFFECT = "Interface\\AddOns\\ProcSounds\\Sounds\\execute_effect.mp3",

  DEATHWISH    = "Interface\\AddOns\\ProcSounds\\Sounds\\deathwish.mp3",
  RECKLESSNESS = "Interface\\AddOns\\ProcSounds\\Sounds\\recklessness.mp3",
  COLDBLOOD    = "Interface\\AddOns\\ProcSounds\\Sounds\\coldblood.mp3",
  BLOODRAGE    = "Interface\\AddOns\\ProcSounds\\Sounds\\bloodrage.mp3",

  CASINO       = "Interface\\AddOns\\ProcSounds\\Sounds\\casino.mp3",
  JACKPOT      = "Interface\\AddOns\\ProcSounds\\Sounds\\jackpot.mp3",
}

local SOUND_OPTIONS = {
  PROC = {
    { id = "default", label = "Default", path = SOUND.PROC },
  },
  EXECUTE = {
    { id = "execute_proc", label = "Execute Proc", path = SOUND.EXECUTE },
  },
  EXECUTE_EFFECT = {
    { id = "default", label = "Default", path = SOUND.EXECUTE_EFFECT },
  },
  DEATHWISH = {
    { id = "default", label = "Default", path = SOUND.DEATHWISH },
  },
  RECKLESSNESS = {
    { id = "default", label = "Default", path = SOUND.RECKLESSNESS },
  },
  COLDBLOOD = {
    { id = "default", label = "Default", path = SOUND.COLDBLOOD },
  },
  BLOODRAGE = {
    { id = "default", label = "Default", path = SOUND.BLOODRAGE },
  },
  CASINO = {
    { id = "default", label = "Default", path = SOUND.CASINO },
  },
  JACKPOT = {
    { id = "default", label = "Default", path = SOUND.JACKPOT },
  },
}

local SOUND_ORDER = {
  "PROC",
  "EXECUTE",
  "EXECUTE_EFFECT",
  "DEATHWISH",
  "RECKLESSNESS",
  "COLDBLOOD",
  "BLOODRAGE",
  "CASINO",
  "JACKPOT",
}

local SOUND_LABELS = {
  PROC = "Proc",
  EXECUTE = "Execute Range",
  EXECUTE_EFFECT = "Execute Hit",
  DEATHWISH = "Death Wish",
  RECKLESSNESS = "Recklessness",
  COLDBLOOD = "Cold Blood",
  BLOODRAGE = "Bloodrage",
  CASINO = "Casino",
  JACKPOT = "Jackpot",
}

local VISUAL = {
  -- Drop execute.tga or execute.blp into Visuals\ to skin the cue.
  EXECUTE = "Interface\\AddOns\\ProcSounds\\Visuals\\execute",
}

local EXTRA_ATTACK_SOURCES = {
  ["Hand of Justice"] = true,
  ["Timeless Strike"] = true,
  ["Windfury Totem"]  = true,
  ["Windfury Weapon"] = true,
}

local EXECUTE_TRIGGER_PCT = 0.20
local EXECUTE_REARM_PCT = 0.25
local EXECUTE_CHECK_INTERVAL = 0.10
local EXECUTE_CUE_ATTENTION_COOLDOWN = 5.00
local EXECUTE_CUE_FADE_IN = 0.18
local EXECUTE_CUE_PULSE_DURATION = 2.60
local EXECUTE_CUE_DURATION = EXECUTE_CUE_FADE_IN + EXECUTE_CUE_PULSE_DURATION
local EXECUTE_CUE_FADE_OUT = 0.40
local EXECUTE_CUE_BASE_SCALE = 1.00
local EXECUTE_CUE_PULSE_SCALE = 0.045
local EXECUTE_CUE_PULSE_CYCLES = 2.0
local EXECUTE_ART_WIDTH = 128
local EXECUTE_ART_HEIGHT = 256
local EXECUTE_CUE_FRAME_WIDTH = EXECUTE_ART_WIDTH
local EXECUTE_CUE_FRAME_HEIGHT = EXECUTE_ART_HEIGHT

local BUFF_SOUNDS = {
  ["Death Wish"]   = "DEATHWISH",
  ["Recklessness"] = "RECKLESSNESS",
  ["Cold Blood"]   = "COLDBLOOD",
}

ProcSounds_DB = ProcSounds_DB or ProcSoundTW_DB or {
  enabled = true,

  lifetime_boxes = 0,
  lifetime_copper = 0,

  run_active = false,
  run_paused = false,
  run_start_epoch = 0,
  run_elapsed = 0,
  run_boxes = 0,
  run_copper = 0,

  panel_shown = true,
  panel_x = nil,
  panel_y = nil,
  settings_x = nil,
  settings_y = nil,

  execute_enabled = true,
  execute_x = nil,
  execute_y = nil,

  sound_choices = {},
}

-- Backfill defaults for older saved vars
ProcSounds_DB.enabled         = (ProcSounds_DB.enabled ~= false)
ProcSounds_DB.lifetime_boxes  = ProcSounds_DB.lifetime_boxes  or 0
ProcSounds_DB.lifetime_copper = ProcSounds_DB.lifetime_copper or 0
ProcSounds_DB.run_active      = ProcSounds_DB.run_active      or false
ProcSounds_DB.run_paused      = ProcSounds_DB.run_paused      or false
ProcSounds_DB.run_start_epoch = ProcSounds_DB.run_start_epoch or 0
ProcSounds_DB.run_elapsed     = ProcSounds_DB.run_elapsed     or 0
ProcSounds_DB.run_boxes       = ProcSounds_DB.run_boxes       or 0
ProcSounds_DB.run_copper      = ProcSounds_DB.run_copper      or 0
ProcSounds_DB.panel_shown     = (ProcSounds_DB.panel_shown ~= false)
ProcSounds_DB.execute_enabled = (ProcSounds_DB.execute_enabled ~= false)
-- Legacy execute sound/visual flags are intentionally ignored now.
ProcSounds_DB.execute_sound   = true
ProcSounds_DB.execute_visual  = true
ProcSoundTW_DB = ProcSounds_DB

local function EnsureSoundChoicesTable()
  if type(ProcSounds_DB.sound_choices) ~= "table" then
    ProcSounds_DB.sound_choices = {}
  end
  return ProcSounds_DB.sound_choices
end

do
  local soundChoices = EnsureSoundChoicesTable()
  local i
  for i = 1, table.getn(SOUND_ORDER) do
    local key = SOUND_ORDER[i]
    local options = SOUND_OPTIONS[key]
    if options and options[1] and not soundChoices[key] then
      soundChoices[key] = options[1].id
    end
  end
end

local lastFireAt = {}
local bloodrageActive = false

local JUNKBOX_STREAK_WINDOW = 15
local junkboxStreak = 0
local lastJunkboxAt = 0

-- Used only for streak reset logic (NOT counting pickpockets)
local ppPending = false
local ppPendingUntil = 0

-- Money dedupe (some servers/UIs may echo money line twice)
local lastMoneyMsg, lastMoneyAt = nil, 0

local executeCueFrame = nil
local executeCueUntil = 0
local executeCueStartAt = 0
local executeCueFadeOutAt = 0
local executeCueFadeOutAlpha = 1
local executeCueFadeOutScale = 1
local executeCuePhase = "hidden"
local executeCheckAt = 0
local executeArmed = true
local executeTargetName = nil
local executeCueMoveMode = false
local lastExecuteTriggerAt = 0
local lastExecuteTriggerTarget = nil

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ADDON_NAME .. "|r " .. msg)
  end
end

local function FireOnce(key, minInterval)
  local now = GetTime()
  minInterval = minInterval or 0.25
  if lastFireAt[key] and (now - lastFireAt[key]) < minInterval then
    return false
  end
  lastFireAt[key] = now
  return true
end

local function Play(path)
  PlaySoundFile(path)
end

local function GetSelectedSoundOption(key)
  local options = SOUND_OPTIONS[key]
  local soundChoices = EnsureSoundChoicesTable()
  local i
  local selectedId

  if not options or table.getn(options) == 0 then
    return nil, nil
  end

  selectedId = soundChoices[key]
  for i = 1, table.getn(options) do
    if options[i].id == selectedId then
      return options[i], i
    end
  end

  soundChoices[key] = options[1].id
  return options[1], 1
end

local function PlaySoundKey(key)
  local option = GetSelectedSoundOption(key)
  if option and option.path then
    Play(option.path)
  end
end

local function CycleSoundOption(key, step)
  local options = SOUND_OPTIONS[key]
  local soundChoices = EnsureSoundChoicesTable()
  local currentOption, currentIndex
  local nextIndex

  if not options or table.getn(options) == 0 then
    return
  end

  currentOption, currentIndex = GetSelectedSoundOption(key)
  if not currentOption then
    return
  end

  nextIndex = currentIndex + (step or 1)
  if nextIndex < 1 then
    nextIndex = table.getn(options)
  elseif nextIndex > table.getn(options) then
    nextIndex = 1
  end

  soundChoices[key] = options[nextIndex].id
end

local function FormatMMSS(sec)
  sec = tonumber(sec) or 0
  if sec < 0 then sec = 0 end
  local m = math.floor(sec / 60)
  local s = sec - (m * 60)
  return string.format("%02d:%02d", m, s)
end

local function FormatMoneyCopper(copper)
  copper = tonumber(copper) or 0
  if copper < 0 then copper = 0 end
  local g = math.floor(copper / 10000)
  copper = copper - g * 10000
  local s = math.floor(copper / 100)
  local c = copper - s * 100
  return string.format("%dg %ds %dc", g, s, c)
end

local function ParseLootCopper(msg)
  -- "You loot 3 Silver, 70 Copper"
  -- "You loot 1 Gold, 2 Silver, 3 Copper"
  if not msg or not string.find(msg, "^You loot ") then return 0 end
  local g = tonumber(string.match(msg, "(%d+)%s*Gold")) or 0
  local s = tonumber(string.match(msg, "(%d+)%s*Silver")) or 0
  local c = tonumber(string.match(msg, "(%d+)%s*Copper")) or 0
  return (g * 10000) + (s * 100) + c
end

local function ResetJunkboxStreak()
  junkboxStreak = 0
  lastJunkboxAt = 0
end

local function IsWarriorPlayer()
  local localizedClass, englishClass = UnitClass("player")
  return englishClass == "WARRIOR" or englishClass == "Warrior" or localizedClass == "Warrior"
end

local function GetTargetHealthPercent()
  if not UnitExists("target") then
    return nil, nil, nil
  end

  local healthMax = UnitHealthMax("target") or 0
  local health = UnitHealth("target") or 0
  if healthMax <= 0 then
    return nil, health, healthMax
  end

  return (health / healthMax) * 100, health, healthMax
end

local function ResetExecuteState()
  executeTargetName = UnitName("target")
  executeArmed = true
end

local function SaveExecuteCuePosition()
  if not executeCueFrame then return end
  local x, y = executeCueFrame:GetCenter()
  local px, py = UIParent:GetCenter()
  if not x or not y or not px or not py then return end
  ProcSounds_DB.execute_x = math.floor((x - px) + 0.5)
  ProcSounds_DB.execute_y = math.floor((y - py) + 0.5)
end

local function ApplyExecuteCuePosition()
  if not executeCueFrame then return end
  executeCueFrame:ClearAllPoints()
  if ProcSounds_DB.execute_x and ProcSounds_DB.execute_y then
    executeCueFrame:SetPoint("CENTER", UIParent, "CENTER", ProcSounds_DB.execute_x, ProcSounds_DB.execute_y)
  else
    executeCueFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
  end
end

local function HideExecuteCue(force)
  executeCueUntil = 0
  executeCueStartAt = 0
  executeCueFadeOutAt = 0
  executeCueFadeOutAlpha = 1
  executeCueFadeOutScale = 1
  executeCuePhase = "hidden"
  if executeCueFrame then
    executeCueFrame:SetScale(1)
    executeCueFrame:SetAlpha(1)
    if executeCueMoveMode and not force then
      return
    end
    executeCueFrame:Hide()
  end
end

local function EnsureExecuteCueFrame()
  if executeCueFrame then return end

  executeCueFrame = CreateFrame("Frame", "ProcSoundsExecuteCue", UIParent)
  executeCueFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  executeCueFrame:SetWidth(EXECUTE_CUE_FRAME_WIDTH)
  executeCueFrame:SetHeight(EXECUTE_CUE_FRAME_HEIGHT)
  executeCueFrame:SetClampedToScreen(true)
  executeCueFrame:EnableMouse(true)
  executeCueFrame:SetMovable(true)
  executeCueFrame:RegisterForDrag("LeftButton")
  executeCueFrame:SetScript("OnDragStart", function()
    if executeCueMoveMode then
      executeCueFrame:StartMoving()
    end
  end)
  executeCueFrame:SetScript("OnDragStop", function()
    executeCueFrame:StopMovingOrSizing()
    SaveExecuteCuePosition()
  end)
  ApplyExecuteCuePosition()

  local art = executeCueFrame:CreateTexture(nil, "ARTWORK")
  art:SetAllPoints(executeCueFrame)
  art:SetTexture(VISUAL.EXECUTE)
  art:SetVertexColor(1, 1, 1, 1)
  executeCueFrame.art = art

  executeCueFrame:Hide()
end

local function SetExecuteCueText(title, subText)
  -- Only the custom texture is shown now; text labels are intentionally omitted.
end

local function UnlockVisuals(silent)
  executeCueMoveMode = true
  EnsureExecuteCueFrame()
  executeCueFrame:SetAlpha(1)
  executeCueFrame:SetScale(1)
  executeCueFrame:Show()
  if UpdateSettingsFrame then
    UpdateSettingsFrame()
  end
  if not silent then
    Print("Visuals unlocked. Drag the execute cue, then run /psounds visuals lock.")
  end
end

local function LockVisuals(silent)
  executeCueMoveMode = false
  HideExecuteCue(true)
  if UpdateSettingsFrame then
    UpdateSettingsFrame()
  end
  if not silent then
    Print("Visuals locked.")
  end
end

local function ToggleExecuteCueMover()
  if executeCueMoveMode then
    LockVisuals(true)
    Print("Execute cue locked. Use /psounds visuals unlock next time.")
    return
  end

  UnlockVisuals(true)
  Print("Execute cue unlocked. Drag it, then run /psounds visuals lock.")
end

local function PrintVisualsStatus()
  Print("Visuals: " .. (executeCueMoveMode and "UNLOCKED" or "LOCKED") ..
    " | Movable now: execute cue")
end

local function BeginExecuteCueFadeOut()
  if executeCueMoveMode then
    return
  end

  if not executeCueFrame or not executeCueFrame:IsShown() then
    HideExecuteCue(true)
    return
  end

  if executeCuePhase == "fadeout" then
    return
  end

  executeCuePhase = "fadeout"
  executeCueFadeOutAt = GetTime()
  executeCueFadeOutAlpha = executeCueFrame:GetAlpha() or 1
  executeCueFadeOutScale = executeCueFrame:GetScale() or 1
end

local function TriggerExecuteCue(title, subText, withAttention)
  if withAttention == nil then
    withAttention = true
  end

  lastExecuteTriggerAt = GetTime()
  lastExecuteTriggerTarget = UnitName("target")

  if withAttention then
    PlaySoundKey("EXECUTE")
  end

  EnsureExecuteCueFrame()
  executeCueStartAt = GetTime()
  executeCueFadeOutAt = 0

  if withAttention then
    executeCueUntil = executeCueStartAt + EXECUTE_CUE_DURATION
    executeCuePhase = "pulse"
    executeCueFrame:SetAlpha(0)
    executeCueFrame:SetScale(EXECUTE_CUE_BASE_SCALE)
  else
    executeCueUntil = 0
    executeCuePhase = "steady"
    executeCueFrame:SetAlpha(1)
    executeCueFrame:SetScale(EXECUTE_CUE_BASE_SCALE)
  end

  executeCueFrame:Show()
end

local function UpdateExecuteCue()
  if not executeCueFrame or not executeCueFrame:IsShown() then
    return
  end

  if executeCueMoveMode then
    executeCueFrame:SetAlpha(1)
    executeCueFrame:SetScale(1)
    return
  end

  local now = GetTime()
  local elapsed
  local pulseElapsed
  local pulseProgress
  local pulse
  local damping

  if executeCuePhase == "fadeout" then
    local fadeProgress
    if executeCueFadeOutAt <= 0 then
      HideExecuteCue(true)
      return
    end

    fadeProgress = (now - executeCueFadeOutAt) / EXECUTE_CUE_FADE_OUT
    if fadeProgress >= 1 then
      HideExecuteCue(true)
      return
    end

    executeCueFrame:SetAlpha(executeCueFadeOutAlpha * (1 - fadeProgress))
    executeCueFrame:SetScale(executeCueFadeOutScale)
    return
  end

  elapsed = now - executeCueStartAt
  if executeCueStartAt <= 0 or elapsed < 0 then
    return
  end

  if elapsed <= EXECUTE_CUE_FADE_IN then
    local progress = elapsed / EXECUTE_CUE_FADE_IN
    executeCueFrame:SetAlpha(progress)
    executeCueFrame:SetScale(EXECUTE_CUE_BASE_SCALE)
    return
  end

  if executeCuePhase == "pulse" and now < executeCueUntil then
    pulseElapsed = elapsed - EXECUTE_CUE_FADE_IN
    pulseProgress = pulseElapsed / EXECUTE_CUE_PULSE_DURATION
    if pulseProgress < 0 then pulseProgress = 0 end
    if pulseProgress > 1 then pulseProgress = 1 end

    -- Two slower outward swells that decay before settling to the base scale.
    pulse = 0.5 - (0.5 * math.cos(pulseProgress * EXECUTE_CUE_PULSE_CYCLES * 6.2831853))
    damping = 1 - (0.35 * pulseProgress)
    executeCueFrame:SetAlpha(1)
    executeCueFrame:SetScale(EXECUTE_CUE_BASE_SCALE + (EXECUTE_CUE_PULSE_SCALE * pulse * damping))
    return
  end

  executeCuePhase = "steady"
  executeCueFrame:SetAlpha(1)
  executeCueFrame:SetScale(EXECUTE_CUE_BASE_SCALE)
end

local function CanWatchExecute()
  if not ProcSounds_DB.enabled or not ProcSounds_DB.execute_enabled then
    return false
  end

  if executeCueMoveMode then
    return false
  end

  if not IsWarriorPlayer() then
    return false
  end

  if not UnitExists("target") or UnitIsDead("target") then
    return false
  end

  -- Some clients report attackability unreliably, so
  -- only block obvious friendly targets here.
  if UnitIsFriend and UnitIsFriend("player", "target") then
    return false
  end

  return true
end

local function CheckExecutePhase()
  local targetName = UnitName("target")
  if targetName ~= executeTargetName then
    if executeTargetName and executeCueFrame and executeCueFrame:IsShown() then
      BeginExecuteCueFadeOut()
    end
    executeTargetName = targetName
    executeArmed = true
  end

  if not CanWatchExecute() then
    if not executeCueMoveMode then
      BeginExecuteCueFadeOut()
    end
    return
  end

  local healthMax = UnitHealthMax("target") or 0
  if healthMax <= 0 then
    return
  end

  local health = UnitHealth("target") or 0
  if health <= 0 then
    executeArmed = true
    BeginExecuteCueFadeOut()
    return
  end

  local healthPct = health / healthMax
  if healthPct <= EXECUTE_TRIGGER_PCT then
    if executeArmed then
      local withAttention = FireOnce("execute:range:attention", EXECUTE_CUE_ATTENTION_COOLDOWN)
      executeArmed = false
      if UnitName("target") and UnitName("target") ~= "" then
        TriggerExecuteCue("EXECUTE", UnitName("target") .. " is in execute range", withAttention)
      else
        TriggerExecuteCue("EXECUTE", "Target at or below 20% health", withAttention)
      end
    end
  elseif healthPct >= EXECUTE_REARM_PCT then
    executeArmed = true
  end
end

-- =========================
-- Run control (Start/Pause/Resume)
-- =========================

local function StartRun()
  ProcSounds_DB.run_active = true
  ProcSounds_DB.run_paused = false
  ProcSounds_DB.run_start_epoch = time()
  ProcSounds_DB.run_elapsed = 0
  ProcSounds_DB.run_boxes = 0
  ProcSounds_DB.run_copper = 0
  Print("Run started (timer + counters reset).")
end

local function PauseRun()
  if not ProcSounds_DB.run_active or ProcSounds_DB.run_paused then return end
  local now = time()
  if ProcSounds_DB.run_start_epoch and ProcSounds_DB.run_start_epoch > 0 then
    ProcSounds_DB.run_elapsed = (ProcSounds_DB.run_elapsed or 0) + (now - ProcSounds_DB.run_start_epoch)
  end
  ProcSounds_DB.run_start_epoch = 0
  ProcSounds_DB.run_paused = true
  Print("Run paused.")
end

local function ResumeRun()
  if not ProcSounds_DB.run_active or not ProcSounds_DB.run_paused then return end
  ProcSounds_DB.run_start_epoch = time()
  ProcSounds_DB.run_paused = false
  Print("Run resumed.")
end

local function ResetRun()
  ProcSounds_DB.run_active = false
  ProcSounds_DB.run_paused = false
  ProcSounds_DB.run_start_epoch = 0
  ProcSounds_DB.run_elapsed = 0
  ProcSounds_DB.run_boxes = 0
  ProcSounds_DB.run_copper = 0
  Print("Run reset (stopped + cleared).")
end

local function GetRunElapsed()
  if not ProcSounds_DB.run_active then
    return 0
  end

  local base = ProcSounds_DB.run_elapsed or 0

  if ProcSounds_DB.run_paused then
    return base
  end

  if ProcSounds_DB.run_start_epoch and ProcSounds_DB.run_start_epoch > 0 then
    return base + (time() - ProcSounds_DB.run_start_epoch)
  end

  return base
end

-- =========================
-- Clean Copy Window (no StaticPopup)
-- =========================

local copyFrame = nil
local settingsFrame = nil
local UpdateSettingsFrame
local SetPanelShown

local function MakeRunCSVLine()
  local ts = date("%Y-%m-%d %H:%M:%S", time())
  local boxes = ProcSounds_DB.run_boxes or 0
  local elapsed = GetRunElapsed()

  local bph = 0
  if elapsed > 0 then bph = (boxes / elapsed) * 3600 end

  local copper = ProcSounds_DB.run_copper or 0
  local gold = copper / 10000
  local gph = 0
  if elapsed > 0 then gph = (gold / elapsed) * 3600 end

  -- Excel-friendly (EU): semicolon-separated
  return string.format("%s;%s;%d;%.2f;%.2f;%.2f", ts, FormatMMSS(elapsed), boxes, bph, gold, gph)
end

local function GetCopyPayload()
  local row = MakeRunCSVLine()
  if IsShiftKeyDown and IsShiftKeyDown() then
    return "timestamp;duration;boxes;boxes_per_hour;gold;gph\n" .. row
  end
  return row
end

local function EnsureCopyFrame()
  if copyFrame then return end

  copyFrame = CreateFrame("Frame", "ProcSounds_CopyFrame", UIParent)
  copyFrame:SetFrameStrata("DIALOG")
  copyFrame:SetWidth(600)
  copyFrame:SetHeight(170)
  copyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  copyFrame:SetClampedToScreen(true)
  copyFrame:EnableMouse(true)
  copyFrame:SetMovable(true)
  copyFrame:RegisterForDrag("LeftButton")
  copyFrame:SetScript("OnDragStart", function() copyFrame:StartMoving() end)
  copyFrame:SetScript("OnDragStop", function() copyFrame:StopMovingOrSizing() end)

  if copyFrame.SetBackdrop then
    copyFrame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 6, right = 6, top = 6, bottom = 6 }
    })
    copyFrame:SetBackdropColor(0, 0, 0, 0.90)
  end

  local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", copyFrame, "TOP", 0, -14)
  title:SetText("Copy CSV (Ctrl+C)")

  local hint = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
  hint:SetText("Semicolon-separated for Excel. (Hold SHIFT for header row)")

  local eb = CreateFrame("EditBox", nil, copyFrame, "InputBoxTemplate")
  eb:SetAutoFocus(false)
  eb:SetMultiLine(true)
  eb:SetWidth(540)
  eb:SetHeight(52)
  eb:SetPoint("TOP", hint, "BOTTOM", 0, -12)
  eb:SetScript("OnEscapePressed", function(self) self:GetParent():Hide() end)
  eb:SetScript("OnEnterPressed", function(self) self:GetParent():Hide() end)
  copyFrame.editBox = eb

  local closeBtn = CreateFrame("Button", nil, copyFrame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(110)
  closeBtn:SetHeight(22)
  closeBtn:SetPoint("BOTTOM", copyFrame, "BOTTOM", 0, 14)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function() copyFrame:Hide() end)

  copyFrame:Hide()
end

local function ShowCopy()
  EnsureCopyFrame()
  copyFrame:Show()
  copyFrame.editBox:SetText(GetCopyPayload())
  copyFrame.editBox:HighlightText()
  copyFrame.editBox:SetFocus()
end

local function CreateSettingsCheckbox(parent, name, label, x, y, onClick)
  local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  local text = getglobal(name .. "Text")
  check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  check:SetScript("OnClick", onClick)
  if text then
    text:SetText(label)
  end
  return check
end

local function EnsureSettingsFrame()
  local i
  local y
  local soundLabelX = 18
  local soundValueX = 230
  local soundPrevX = 350
  local soundNextX = 380
  local soundTestX = 414

  if settingsFrame then return end

  settingsFrame = CreateFrame("Frame", "ProcSounds_SettingsFrame", UIParent)
  settingsFrame:SetFrameStrata("DIALOG")
  settingsFrame:SetWidth(520)
  settingsFrame:SetHeight(470)
  settingsFrame:SetClampedToScreen(true)
  settingsFrame:EnableMouse(true)
  settingsFrame:SetMovable(true)
  settingsFrame:RegisterForDrag("LeftButton")
  settingsFrame:SetScript("OnDragStart", function() settingsFrame:StartMoving() end)
  settingsFrame:SetScript("OnDragStop", function()
    local x, yPos = settingsFrame:GetCenter()
    local px, py = UIParent:GetCenter()
    settingsFrame:StopMovingOrSizing()
    if x and yPos and px and py then
      ProcSounds_DB.settings_x = math.floor((x - px) + 0.5)
      ProcSounds_DB.settings_y = math.floor((yPos - py) + 0.5)
    end
  end)

  if settingsFrame.SetBackdrop then
    settingsFrame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 6, right = 6, top = 6, bottom = 6 }
    })
    settingsFrame:SetBackdropColor(0, 0, 0, 0.92)
  end

  if ProcSounds_DB.settings_x and ProcSounds_DB.settings_y then
    settingsFrame:SetPoint("CENTER", UIParent, "CENTER", ProcSounds_DB.settings_x, ProcSounds_DB.settings_y)
  else
    settingsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  end

  local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", settingsFrame, "TOP", 0, -14)
  title:SetText("ProcSounds Settings")

  local hint = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
  hint:SetText("Settings are saved across sessions.")

  settingsFrame.enabledCheck = CreateSettingsCheckbox(
    settingsFrame,
    "ProcSounds_SettingsEnabledCheck",
    "Addon Enabled",
    16,
    -42,
    function()
      ProcSounds_DB.enabled = settingsFrame.enabledCheck:GetChecked() and true or false
      if ProcSounds_DB.enabled then
        ProcSounds_DB.execute_enabled = true
        ResetExecuteState()
      else
        executeCueMoveMode = false
        HideExecuteCue(true)
      end
      if UpdateSettingsFrame then UpdateSettingsFrame() end
    end
  )

  settingsFrame.executeCheck = CreateSettingsCheckbox(
    settingsFrame,
    "ProcSounds_SettingsExecuteCheck",
    "Execute Cue Enabled",
    16,
    -66,
    function()
      ProcSounds_DB.execute_enabled = settingsFrame.executeCheck:GetChecked() and true or false
      if ProcSounds_DB.execute_enabled then
        ResetExecuteState()
      else
        executeCueMoveMode = false
        HideExecuteCue(true)
      end
      if UpdateSettingsFrame then UpdateSettingsFrame() end
    end
  )

  settingsFrame.panelCheck = CreateSettingsCheckbox(
    settingsFrame,
    "ProcSounds_SettingsPanelCheck",
    "Show Loot Panel",
    16,
    -90,
    function()
      SetPanelShown(settingsFrame.panelCheck:GetChecked() and true or false, false)
    end
  )

  local actionsLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  actionsLabel:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 16, -126)
  actionsLabel:SetText("Actions")

  settingsFrame.testExecuteBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
  settingsFrame.testExecuteBtn:SetWidth(110)
  settingsFrame.testExecuteBtn:SetHeight(22)
  settingsFrame.testExecuteBtn:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 16, -146)
  settingsFrame.testExecuteBtn:SetText("Test Execute")
  settingsFrame.testExecuteBtn:SetScript("OnClick", function()
    TriggerExecuteCue("EXECUTE", nil, true)
  end)

  settingsFrame.visualsBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
  settingsFrame.visualsBtn:SetWidth(120)
  settingsFrame.visualsBtn:SetHeight(22)
  settingsFrame.visualsBtn:SetPoint("LEFT", settingsFrame.testExecuteBtn, "RIGHT", 10, 0)
  settingsFrame.visualsBtn:SetScript("OnClick", function()
    if executeCueMoveMode then
      LockVisuals()
    else
      UnlockVisuals()
    end
    if UpdateSettingsFrame then UpdateSettingsFrame() end
  end)

  settingsFrame.copyBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
  settingsFrame.copyBtn:SetWidth(90)
  settingsFrame.copyBtn:SetHeight(22)
  settingsFrame.copyBtn:SetPoint("LEFT", settingsFrame.visualsBtn, "RIGHT", 10, 0)
  settingsFrame.copyBtn:SetText("Copy CSV")
  settingsFrame.copyBtn:SetScript("OnClick", function()
    ShowCopy()
  end)

  local soundsLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  soundsLabel:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 16, -186)
  soundsLabel:SetText("Sounds")

  local soundCueHeader = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  soundCueHeader:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", soundLabelX, -206)
  soundCueHeader:SetText("Cue")

  local soundSelectedHeader = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  soundSelectedHeader:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", soundValueX, -206)
  soundSelectedHeader:SetText("Selected")

  settingsFrame.soundRows = {}
  y = -228
  for i = 1, table.getn(SOUND_ORDER) do
    local key = SOUND_ORDER[i]
    local row = {}

    row.key = key
    row.label = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetWidth(190)
    row.label:SetJustifyH("LEFT")
    row.label:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", soundLabelX, y)
    row.label:SetText(SOUND_LABELS[key] or key)

    row.value = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.value:SetWidth(100)
    row.value:SetJustifyH("CENTER")
    row.value:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", soundValueX, y)
    row.value:SetHeight(20)
    row.value:SetJustifyH("CENTER")

    row.prevBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    row.prevBtn:SetWidth(24)
    row.prevBtn:SetHeight(20)
    row.prevBtn:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", soundPrevX, y + 2)
    row.prevBtn:SetText("<")
    row.prevBtn:SetScript("OnClick", function()
      CycleSoundOption(key, -1)
      if UpdateSettingsFrame then UpdateSettingsFrame() end
    end)

    row.nextBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    row.nextBtn:SetWidth(24)
    row.nextBtn:SetHeight(20)
    row.nextBtn:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", soundNextX, y + 2)
    row.nextBtn:SetText(">")
    row.nextBtn:SetScript("OnClick", function()
      CycleSoundOption(key, 1)
      if UpdateSettingsFrame then UpdateSettingsFrame() end
    end)

    row.testBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    row.testBtn:SetWidth(50)
    row.testBtn:SetHeight(20)
    row.testBtn:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", soundTestX, y + 2)
    row.testBtn:SetText("Test")
    row.testBtn:SetScript("OnClick", function()
      PlaySoundKey(key)
    end)

    settingsFrame.soundRows[key] = row
    y = y - 24
  end

  local closeBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(90)
  closeBtn:SetHeight(22)
  closeBtn:SetPoint("BOTTOM", settingsFrame, "BOTTOM", 0, 14)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function() settingsFrame:Hide() end)

  settingsFrame:SetScript("OnShow", function()
    if UpdateSettingsFrame then UpdateSettingsFrame() end
  end)

  settingsFrame:Hide()
end

function UpdateSettingsFrame()
  local i

  if not settingsFrame then return end

  settingsFrame.enabledCheck:SetChecked(ProcSounds_DB.enabled and 1 or nil)
  settingsFrame.executeCheck:SetChecked(ProcSounds_DB.execute_enabled and 1 or nil)
  settingsFrame.panelCheck:SetChecked(ProcSounds_DB.panel_shown and 1 or nil)

  if executeCueMoveMode then
    settingsFrame.visualsBtn:SetText("Lock Visual")
  else
    settingsFrame.visualsBtn:SetText("Unlock Visual")
  end

  for i = 1, table.getn(SOUND_ORDER) do
    local key = SOUND_ORDER[i]
    local row = settingsFrame.soundRows[key]
    local option = GetSelectedSoundOption(key)
    local count = table.getn(SOUND_OPTIONS[key] or {})

    if row and option then
      row.value:SetText(option.label)
      if count <= 1 then
        row.prevBtn:Disable()
        row.nextBtn:Disable()
      else
        row.prevBtn:Enable()
        row.nextBtn:Enable()
      end
    end
  end
end

local function ToggleSettings()
  EnsureSettingsFrame()
  if settingsFrame:IsShown() then
    settingsFrame:Hide()
  else
    UpdateSettingsFrame()
    settingsFrame:Show()
  end
end

-- =========================

local function ExtractBuffName(msg)
  local name = string.match(msg, "^You are afflicted by (.-)%s*%(%d+%)%.$")
  if name then return name end
  name = string.match(msg, "^You are afflicted by (.-)%.$")
  if name then return name end
  name = string.match(msg, "^You gain (.-)%s*%(%d+%)%.$")
  if name then return name end
  name = string.match(msg, "^You gain (.-)%.$")
  if name then return name end
  return nil
end

local function IsSuccessfulExecuteMessage(msg)
  if not msg or not string.find(msg, "Execute") then
    return false
  end

  if string.find(msg, "^Your Execute ") then
    if string.find(msg, " hits ") or string.find(msg, " crits ") then
      return true
    end
  end

  return false
end

-- Panel UI -------------------------------------------------------------

local panel, panelText1, panelText2, panelText3, panelText4, panelText5
local startBtn

local function UpdatePanelText()
  if not panel or not panel:IsShown() then return end

  local boxes = ProcSounds_DB.run_boxes or 0
  local elapsed = GetRunElapsed()

  local status = "STOPPED"
  if ProcSounds_DB.run_active then
    status = ProcSounds_DB.run_paused and "PAUSED" or "RUNNING"
  end

  panelText1:SetText("Junkboxes: " .. tostring(boxes))
  panelText2:SetText("Time: " .. FormatMMSS(elapsed) .. "  (" .. status .. ")")

  if ProcSounds_DB.run_active and elapsed > 0 then
    local perHour = (boxes / elapsed) * 3600
    panelText3:SetText(string.format("Boxes/h: %.2f", perHour))
  else
    panelText3:SetText("Boxes/h: -")
  end

  local copper = ProcSounds_DB.run_copper or 0
  if ProcSounds_DB.run_active and elapsed > 0 then
    local gph = (copper / 10000) / elapsed * 3600
    panelText4:SetText("Gold: " .. FormatMoneyCopper(copper) .. string.format("  | GPH: %.2f", gph))
  else
    panelText4:SetText("Gold: " .. FormatMoneyCopper(copper) .. "  | GPH: -")
  end

  local now = GetTime()
  local jtxt = "Jackpot: -"
  if junkboxStreak > 0 and lastJunkboxAt > 0 then
    local rem = JUNKBOX_STREAK_WINDOW - (now - lastJunkboxAt)
    if rem <= 0 then
      ResetJunkboxStreak()
    else
      jtxt = string.format("Jackpot window: %.1fs  (streak %d/3)", rem, junkboxStreak)
    end
  end
  panelText5:SetText(jtxt)

  if startBtn then
    if not ProcSounds_DB.run_active then
      startBtn:SetText("Start")
    elseif ProcSounds_DB.run_paused then
      startBtn:SetText("Resume")
    else
      startBtn:SetText("Pause")
    end
  end
end

local function CreatePanel()
  if panel then return end

  panel = CreateFrame("Frame", "ProcSoundsPanel", UIParent)
  panel:SetWidth(320)
  panel:SetHeight(132)
  panel:SetFrameStrata("DIALOG")
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function() panel:StartMoving() end)
  panel:SetScript("OnDragStop", function()
    panel:StopMovingOrSizing()
    ProcSounds_DB.panel_x = panel:GetLeft()
    ProcSounds_DB.panel_y = panel:GetTop()
  end)

  if panel.SetBackdrop then
    panel:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
  end

  panelText1 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panelText1:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)

  panelText2 = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panelText2:SetPoint("TOPLEFT", panelText1, "BOTTOMLEFT", 0, -4)

  panelText3 = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panelText3:SetPoint("TOPLEFT", panelText2, "BOTTOMLEFT", 0, -4)

  panelText4 = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panelText4:SetPoint("TOPLEFT", panelText3, "BOTTOMLEFT", 0, -4)

  panelText5 = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panelText5:SetPoint("TOPLEFT", panelText4, "BOTTOMLEFT", 0, -4)

  startBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  startBtn:SetWidth(80)
  startBtn:SetHeight(20)
  startBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 10)
  startBtn:SetText("Start")
  startBtn:SetScript("OnClick", function()
    if not ProcSounds_DB.run_active then
      StartRun()
    elseif ProcSounds_DB.run_paused then
      ResumeRun()
    else
      PauseRun()
    end
    UpdatePanelText()
  end)

  local copyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  copyBtn:SetWidth(80)
  copyBtn:SetHeight(20)
  copyBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 10)
  copyBtn:SetText("Copy")
  copyBtn:SetScript("OnClick", function()
    ShowCopy()
  end)

  local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  resetBtn:SetWidth(80)
  resetBtn:SetHeight(20)
  resetBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
  resetBtn:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    ResetRun()
    UpdatePanelText()
  end)

  if ProcSounds_DB.panel_x and ProcSounds_DB.panel_y then
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ProcSounds_DB.panel_x, ProcSounds_DB.panel_y)
  else
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
  end

  local acc = 0
  panel:SetScript("OnUpdate", function(self, elapsed)
    elapsed = elapsed or arg1
    if not elapsed then return end
    acc = acc + elapsed
    if acc >= 0.2 then
      acc = 0
      UpdatePanelText()
    end
  end)

  UpdatePanelText()
end

SetPanelShown = function(shown, chatFeedback)
  CreatePanel()
  if shown then
    panel:Show()
    ProcSounds_DB.panel_shown = true
    UpdatePanelText()
    if chatFeedback then
      Print("Loot panel: shown. (/psounds lp)")
    end
  else
    panel:Hide()
    ProcSounds_DB.panel_shown = false
    if chatFeedback then
      Print("Loot panel: hidden. (/psounds lp)")
    end
  end

  if UpdateSettingsFrame then
    UpdateSettingsFrame()
  end
end

local function TogglePanel()
  CreatePanel()
  SetPanelShown(not panel:IsShown(), true)
end

-- Loot / sounds --------------------------------------------------------

local function OnHeavyJunkboxLoot()
  local now = GetTime()

  if lastJunkboxAt == 0 or (now - lastJunkboxAt) > JUNKBOX_STREAK_WINDOW then
    junkboxStreak = 1
  else
    junkboxStreak = junkboxStreak + 1
  end
  lastJunkboxAt = now

  ProcSounds_DB.lifetime_boxes = (ProcSounds_DB.lifetime_boxes or 0) + 1

  if ProcSounds_DB.run_active and not ProcSounds_DB.run_paused then
    ProcSounds_DB.run_boxes = (ProcSounds_DB.run_boxes or 0) + 1
  end

  PlaySoundKey("CASINO")
  if junkboxStreak >= 3 then
    PlaySoundKey("JACKPOT")
    ResetJunkboxStreak()
  end

  UpdatePanelText()
end

local function HandleMessage(msg)
  if not ProcSounds_DB.enabled then return end
  if not msg or msg == "" then return end

  local now = GetTime()

  -- Money tracking ("You loot X Gold/Silver/Copper")
  if string.find(msg, "^You loot ") then
    if msg == lastMoneyMsg and (now - lastMoneyAt) < 0.10 then
      return
    end
    lastMoneyMsg = msg
    lastMoneyAt = now

    local copper = ParseLootCopper(msg)
    if copper and copper > 0 then
      ProcSounds_DB.lifetime_copper = (ProcSounds_DB.lifetime_copper or 0) + copper
      if ProcSounds_DB.run_active and not ProcSounds_DB.run_paused then
        ProcSounds_DB.run_copper = (ProcSounds_DB.run_copper or 0) + copper
      end
      UpdatePanelText()
    end
    return
  end

  -- Pick Pocket detection kept ONLY for streak reset logic (no tracking)
  if string.find(msg, "Pick Pocket") and string.match(msg, "^You ") then
    ppPending = true
    ppPendingUntil = now + 5
  end

  if string.match(msg, "no pockets") or string.match(msg, "fail to pick pocket") then
    ResetJunkboxStreak()
  end

  if string.match(msg, "^Bloodrage fades from you%.$") then
    bloodrageActive = false
    return
  end

  if IsSuccessfulExecuteMessage(msg) then
    if FireOnce("spell:ExecuteSuccess", 0.05) then
      PlaySoundKey("EXECUTE_EFFECT")
    end
    return
  end

  if string.find(msg, "^You receive loot:") or string.find(msg, "^You receive item:") then
    if string.find(msg, "%[Heavy Junkbox%]") or string.find(msg, "Heavy Junkbox") then
      if FireOnce("loot:Heavy Junkbox", 0.30) then
        OnHeavyJunkboxLoot()
      end
      return
    else
      if ppPending and now <= ppPendingUntil then
        ResetJunkboxStreak()
        ppPending = false
      end
    end
  end

  if ppPending and now > ppPendingUntil then
    ppPending = false
  end

  local source = string.match(msg, "^You gain %d+ extra attack[s]? through (.+)%.$")
  if source and EXTRA_ATTACK_SOURCES[source] then
    if FireOnce("extra:" .. source, 0.20) then
      PlaySoundKey("PROC")
    end
    return
  end

  local rageSource = string.match(msg, "^You gain %d+ Rage from (.+)%.$")
  if rageSource == "Bloodrage" then
    if not bloodrageActive then
      bloodrageActive = true
      PlaySoundKey("BLOODRAGE")
    end
    return
  end

  local buff = ExtractBuffName(msg)
  if buff and BUFF_SOUNDS[buff] then
    if FireOnce("buff:" .. buff, 0.50) then
      PlaySoundKey(BUFF_SOUNDS[buff])
    end
    return
  end
end

-- Events ---------------------------------------------------------------

local printedLoaded = false

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_TARGET_CHANGED")

f:RegisterEvent("CHAT_MSG_LOOT")
f:RegisterEvent("CHAT_MSG_MONEY")

f:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
f:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
f:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_SELF")

f:SetScript("OnUpdate", function(self, elapsed)
  elapsed = elapsed or arg1 or 0
  executeCheckAt = executeCheckAt + elapsed

  if executeCheckAt >= EXECUTE_CHECK_INTERVAL then
    executeCheckAt = 0
    CheckExecutePhase()
  end

  UpdateExecuteCue()
end)

f:SetScript("OnEvent", function()
  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    ResetExecuteState()
    HideExecuteCue()
    if event == "PLAYER_TARGET_CHANGED" then
      return
    end
  end

  if (event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD") and not printedLoaded then
    printedLoaded = true
    Print("Loaded. Status: " .. (ProcSounds_DB.enabled and "ON" or "OFF") .. "  (/psounds)")
    CreatePanel()
    if not ProcSounds_DB.panel_shown and panel then panel:Hide() end
    UpdatePanelText()
    return
  end

  HandleMessage(arg1)
end)

-- Slash commands -------------------------------------------------------

local function PrintHelp()
  Print("Commands:")
  Print("  /psounds on|off|status")
  Print("  /psounds execute on|off|status|move|test")
  Print("  /psounds settings")
  Print("  /psounds visuals unlock|lock|status")
  Print("  /psounds lp      - toggle loot panel")
  Print("  /psounds run start|pause|resume|reset|status")
  Print("  /psounds copy    - open CSV copy window (SHIFT = header)")
end

SLASH_PROCSOUNDS1 = "/psounds"
SLASH_PROCSOUNDS2 = "/pstw"
SlashCmdList["PROCSOUNDS"] = function(cmd)
  cmd = cmd or ""
  local args = {}
  for w in string.gmatch(cmd, "%S+") do table.insert(args, w) end
  local a1 = string.lower(args[1] or "")
  local a2 = string.lower(args[2] or "")

  if a1 == "on" then
    ProcSounds_DB.enabled = true
    ProcSounds_DB.execute_enabled = true
    ResetExecuteState()
    HideExecuteCue(true)
    if UpdateSettingsFrame then UpdateSettingsFrame() end
    Print("Enabled. All features are on.")
  elseif a1 == "off" then
    ProcSounds_DB.enabled = false
    executeCueMoveMode = false
    HideExecuteCue(true)
    if UpdateSettingsFrame then UpdateSettingsFrame() end
    Print("Disabled. All features are off.")
  elseif a1 == "status" then
    Print("Status: " .. (ProcSounds_DB.enabled and "ON" or "OFF") ..
      " | Lifetime boxes: " .. tostring(ProcSounds_DB.lifetime_boxes or 0) ..
      " | Lifetime gold: " .. FormatMoneyCopper(ProcSounds_DB.lifetime_copper or 0) ..
      " | Execute cue: " .. (ProcSounds_DB.execute_enabled and "ON" or "OFF"))
  elseif a1 == "settings" then
    ToggleSettings()
  elseif a1 == "visuals" then
    if a2 == "unlock" then
      UnlockVisuals()
    elseif a2 == "lock" then
      LockVisuals()
    else
      PrintVisualsStatus()
    end
  elseif a1 == "execute" then
    if a2 == "on" then
      ProcSounds_DB.execute_enabled = true
      ResetExecuteState()
      if UpdateSettingsFrame then UpdateSettingsFrame() end
      Print("Execute cue enabled.")
    elseif a2 == "off" then
      ProcSounds_DB.execute_enabled = false
      executeCueMoveMode = false
      HideExecuteCue(true)
      if UpdateSettingsFrame then UpdateSettingsFrame() end
      Print("Execute cue disabled.")
    elseif a2 == "move" then
      ToggleExecuteCueMover()
    elseif a2 == "test" then
      if executeCueMoveMode then
        Print("Lock the visuals first. (/psounds visuals lock)")
      else
        TriggerExecuteCue("EXECUTE", "Preview: pulse + sound", true)
      end
    else
      local targetPct, targetHealth, targetHealthMax = GetTargetHealthPercent()
      local targetInfo = " | Target HP: none"
      if targetPct then
        targetInfo = string.format(" | Target HP: %.1f%% (%d/%d)", targetPct, targetHealth, targetHealthMax)
      elseif UnitExists("target") then
        targetInfo = string.format(" | Target HP: unavailable (%d/%d)", targetHealth or 0, targetHealthMax or 0)
      end

      local lastTriggerInfo = " | Last trigger: never"
      if lastExecuteTriggerAt > 0 then
        local age = GetTime() - lastExecuteTriggerAt
        if age < 0 then age = 0 end
        lastTriggerInfo = string.format(" | Last trigger: %.1fs ago%s",
          age,
          (lastExecuteTriggerTarget and lastExecuteTriggerTarget ~= "" and (" (" .. lastExecuteTriggerTarget .. ")") or ""))
      end

      Print("Execute cue: " .. (ProcSounds_DB.execute_enabled and "ON" or "OFF") ..
        " | Class: " .. (IsWarriorPlayer() and "WARRIOR" or "NON-WARRIOR") ..
        " | Trigger: <= 20% target HP" ..
        " | Watch: " .. (CanWatchExecute() and "READY" or "BLOCKED") ..
        " | Visuals: " .. (executeCueMoveMode and "UNLOCKED" or "LOCKED") ..
        " | Armed: " .. (executeArmed and "YES" or "NO") ..
        " | Cue: ON" ..
        targetInfo ..
        lastTriggerInfo)
    end
  elseif a1 == "lp" then
    TogglePanel()
  elseif a1 == "run" then
    if a2 == "start" then
      StartRun(); UpdatePanelText()
    elseif a2 == "pause" then
      PauseRun(); UpdatePanelText()
    elseif a2 == "resume" then
      ResumeRun(); UpdatePanelText()
    elseif a2 == "reset" then
      ResetRun(); UpdatePanelText()
    elseif a2 == "status" then
      local elapsed = GetRunElapsed()
      local copper = ProcSounds_DB.run_copper or 0
      local gph = 0
      local status = "STOPPED"
      if ProcSounds_DB.run_active then
        status = ProcSounds_DB.run_paused and "PAUSED" or "RUNNING"
      end
      if ProcSounds_DB.run_active and elapsed > 0 then
        gph = (copper / 10000) / elapsed * 3600
      end
      Print("Run: " .. status ..
        " | Boxes: " .. tostring(ProcSounds_DB.run_boxes or 0) ..
        " | Time: " .. FormatMMSS(elapsed) ..
        " | Gold: " .. FormatMoneyCopper(copper) ..
        (ProcSounds_DB.run_active and elapsed > 0 and string.format(" | GPH: %.2f", gph) or " | GPH: -")
      )
    else
      Print("Usage: /psounds run start|pause|resume|reset|status")
    end
  elseif a1 == "copy" then
    ShowCopy()
  else
    PrintHelp()
  end
end

