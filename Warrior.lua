local Addon = ProcSoundsAddon or {}
ProcSoundsAddon = Addon
Addon.modules = Addon.modules or {}
Addon.api = Addon.api or {}
Addon.constants = Addon.constants or {}
Addon.constants.Warrior = Addon.constants.Warrior or {}
Addon.state = Addon.state or {}
Addon.state.warrior = Addon.state.warrior or {
  executeArmed = true,
  executeTargetName = nil,
  executeCueMoveMode = false,
  lastExecuteTriggerAt = 0,
  lastExecuteTriggerTarget = nil,
}

local API = Addon.api
local WarriorConstants = Addon.constants.Warrior
local Warrior = Addon.modules.Warrior or {}

Addon.modules.Warrior = Warrior

local BUFF_SOUNDS = {
  ["Death Wish"] = "DEATHWISH",
  ["Recklessness"] = "RECKLESSNESS",
}

local bloodrageActive = false

local function GetState()
  return Addon.state and Addon.state.warrior
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

function Warrior.IsWarriorPlayer()
  local localizedClass, englishClass = UnitClass("player")
  return englishClass == "WARRIOR" or englishClass == "Warrior" or localizedClass == "Warrior"
end

function Warrior.GetTargetHealthPercent()
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

function Warrior.ResetExecuteState()
  local state = GetState()
  if not state then
    return
  end

  state.executeTargetName = UnitName("target")
  state.executeArmed = true
end

function Warrior.CanWatchExecute()
  local state = GetState()
  if not state then
    return false
  end

  if not ProcSounds_DB.enabled or not ProcSounds_DB.execute_enabled then
    return false
  end

  if state.executeCueMoveMode then
    return false
  end

  if not Warrior.IsWarriorPlayer() then
    return false
  end

  if not UnitExists("target") or UnitIsDead("target") then
    return false
  end

  if UnitIsFriend and UnitIsFriend("player", "target") then
    return false
  end

  return true
end

function Warrior.CheckExecutePhase()
  local state = GetState()
  local healthMax
  local health
  local healthPct
  local targetName
  local withAttention

  if not state then
    return
  end

  targetName = UnitName("target")
  if targetName ~= state.executeTargetName then
    if state.executeTargetName and API.IsExecuteCueShown and API.IsExecuteCueShown() and API.BeginExecuteCueFadeOut then
      API.BeginExecuteCueFadeOut()
    end
    state.executeTargetName = targetName
    state.executeArmed = true
  end

  if not Warrior.CanWatchExecute() then
    if not state.executeCueMoveMode and API.BeginExecuteCueFadeOut then
      API.BeginExecuteCueFadeOut()
    end
    return
  end

  healthMax = UnitHealthMax("target") or 0
  if healthMax <= 0 then
    return
  end

  health = UnitHealth("target") or 0
  if health <= 0 then
    state.executeArmed = true
    if API.BeginExecuteCueFadeOut then
      API.BeginExecuteCueFadeOut()
    end
    return
  end

  healthPct = health / healthMax
  if healthPct <= (WarriorConstants.EXECUTE_TRIGGER_PCT or 0.20) then
    if state.executeArmed then
      withAttention = true
      if API.FireOnce then
        withAttention = API.FireOnce("execute:range:attention", WarriorConstants.EXECUTE_CUE_ATTENTION_COOLDOWN or 5.00)
      end
      state.executeArmed = false

      if API.TriggerExecuteCue then
        targetName = UnitName("target")
        if targetName and targetName ~= "" then
          API.TriggerExecuteCue("EXECUTE", targetName .. " is in execute range", withAttention)
        else
          API.TriggerExecuteCue("EXECUTE", "Target at or below 20% health", withAttention)
        end
      end
    end
  elseif healthPct >= (WarriorConstants.EXECUTE_REARM_PCT or 0.25) then
    state.executeArmed = true
  end
end

function Warrior.HandleMessage(msg)
  local buff
  local rageSource

  if string.match(msg, "^Bloodrage fades from you%.$") then
    bloodrageActive = false
    return true
  end

  if IsSuccessfulExecuteMessage(msg) then
    if not API.FireOnce or API.FireOnce("spell:ExecuteSuccess", 0.05) then
      if API.PlaySoundKey then
        API.PlaySoundKey("EXECUTE_EFFECT")
      end
    end
    return true
  end

  rageSource = string.match(msg, "^You gain %d+ Rage from (.+)%.$")
  if rageSource == "Bloodrage" then
    if not bloodrageActive then
      bloodrageActive = true
      if API.PlaySoundKey then
        API.PlaySoundKey("BLOODRAGE")
      end
    end
    return true
  end

  buff = API.ExtractBuffName and API.ExtractBuffName(msg)
  if buff and BUFF_SOUNDS[buff] then
    if not API.FireOnce or API.FireOnce("buff:" .. buff, 0.50) then
      if API.PlaySoundKey then
        API.PlaySoundKey(BUFF_SOUNDS[buff])
      end
    end
    return true
  end

  return false
end
