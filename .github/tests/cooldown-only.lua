local driver, overlays = nil, {}
local function widget()
    local frame = { shown = true, alpha = 1, scripts = {} }
    local noop = function() end
    for _, name in ipairs({"SetAllPoints", "SetFrameLevel", "SetSwipeTexture", "SetSwipeColor", "SetDrawBling",
        "SetDrawEdge", "SetDrawSwipe", "SetCountdownFont", "SetPoint", "SetCountdownFormatter",
        "SetCountdownAbbrevThreshold", "SetCountdownMillisecondsThreshold", "SetMinimumCountdownDuration",
        "RegisterEvent", "RegisterUnitEvent"}) do frame[name] = noop end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetShown(shown) self.shown = shown end
    function frame:GetFrameLevel() return 1 end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:SetText(text) self.text = text end
    function frame:CreateFontString() return widget() end
    function frame:SetHideCountdownNumbers(hidden) self.hiddenNumbers = hidden end
    function frame:GetHideCountdownNumbers() return false end
    function frame:GetCountdownFormatter() return nil end
    function frame:GetCountdownAbbrevThreshold() return 60 end
    function frame:GetCountdownMillisecondsThreshold() return 3 end
    function frame:GetMinimumCountdownDuration() return 0 end
    function frame:GetCooldownDuration() return 45 end -- Blizzard's aura duration
    function frame:SetCooldownFromDurationObject(duration) self.duration = duration end
    function frame:Clear() self.duration = nil end
    function frame:IsDesaturated() return self.desaturated or false end
    function frame:SetDesaturated(value) self.desaturated = value end
    return frame
end
function CreateFrame(kind)
    local result = widget()
    if not driver then driver = result end
    if kind == "Cooldown" then overlays[#overlays + 1] = result end
    return result
end
function wipe(values) for key in pairs(values) do values[key] = nil end end
function InCombatLockdown() return false end
function hooksecurefunc() end
SlashCmdList = {}
BetterForeverCooldownsDB = { compatibilityMode = false }
Enum = { SpellBookSpellBank = { Player = 0 } }
C_Timer = { After = function(_, callback) callback() end }
C_SpellBook = {}
CooldownViewerConstants = { ITEM_COOLDOWN_COLOR = { GetRGBA = function() return 0, 0, 0, 0.7 end } }
local active = true
local duration = {
    IsActive = function() return active end,
    GetRemainingDuration = function() return active and 10 or 0 end,
}
C_Spell = { GetSpellCooldownDuration = function(id, ignoreGCD)
    assert(id == 42 and ignoreGCD, "Request the spell cooldown with GCD ignored")
    return duration
end }
local addon = { UpdateChoices = function() end }
assert(loadfile("BetterForeverCooldowns/BetterForeverCooldowns.lua"))("BetterForeverCooldowns", addon)
driver.scripts.OnEvent(driver, "ADDON_LOADED", "BetterForeverCooldowns")
local native, charge, icon = widget(), widget(), widget()
native.alpha, charge.alpha = 0.8, 0.6
local item = widget()
function item:GetBaseSpellID() return 42 end
function item:GetSpellID() return 42 end
function item:GetCooldownFrame() return native end
function item:GetChargeCountFrame() return charge end
function item:GetIconTexture() return icon end
function item:GetCooldownID() return 1 end
function item:ShouldBeShown() return true end
item.includeAsLayoutChildWhenHidden = true
local editing = false
EssentialCooldownViewer = {
    IsEditing = function() return editing end,
    itemFramePool = { EnumerateActive = function()
        local done = false
        return function() if not done then done = true; return item end end
    end },
}
addon.SetIconOverride("cooldowns", 42, "cooldownOnly", true)
local overlay = assert(overlays[1])
assert(overlay.duration == duration, "Show spell cooldown even while Blizzard shows an aura")
assert(native.alpha == 0 and charge.alpha == 0, "Suppress native aura countdown and aura counts")
local recharge = { IsActive = function() return true end }
C_Spell.GetSpellCharges = function() return { currentCharges = 1, maxCharges = 2 } end
C_Spell.GetSpellChargeDuration = function() return recharge end
addon.ApplySettings()
assert(overlay.duration == recharge, "Show recharge time for a partially recharging spell")
C_Spell.GetSpellCharges, C_Spell.GetSpellChargeDuration = nil, nil
active = false
addon.ApplySettings()
assert(overlay.duration == nil and native.alpha == 0, "Ready spell must not fall back to aura duration")
overlay.scripts.OnCooldownDone()
assert(native.alpha == 0, "Cooldown completion must not restore the aura timer")
-- A target change or aura update still uses the same cooldown API.
active = true
addon.ApplySettings()
assert(overlay.duration == duration and native.alpha == 0)
driver.scripts.OnEvent(driver, "ADDON_LOADED", "BetterForeverCooldowns")
assert(addon.GetIconOverride("cooldowns", 42).cooldownOnly, "Persist the setting across reloads")
editing = true
addon.ApplySettings()
assert(native.alpha == 0.8 and charge.alpha == 0.6, "Restore native display in Edit Mode")
editing = false
addon.ApplySettings()
assert(native.alpha == 0)
addon.SetIconOverride("cooldowns", 42, "cooldownOnly", nil)
assert(native.alpha == 0.8 and charge.alpha == 0.6, "Disabling restores original alpha values")
assert(not item:IsDesaturated(), "Do not leave the icon grey when disabling")
-- Utility uses the same timer options, but must retain Blizzard's reserved
-- cooldown slots. Left-packing hidden reminders applies to Tracked Buffs only.
UtilityCooldownViewer = EssentialCooldownViewer
EssentialCooldownViewer = nil
addon.SetIconOverride("cooldowns", 42, "cooldownOnly", true)
assert(item:IsShown(), "Cooldown-only must not hide a Utility icon")
active = true
addon.SetIconOverride("cooldowns", 42, "visibility", "ready")
assert(not item:IsShown(), "Ready-only hides a spell while on cooldown")
assert(item.includeAsLayoutChildWhenHidden == true, "Keep Utility's native row footprint when a spell is filtered")
active = false
addon.ApplySettings()
assert(item:IsShown(), "Utility icon must reappear when ready")
addon.SetIconOverride("cooldowns", 42, "visibility", nil)
active = true
addon.ApplySettings()
assert(item:IsShown(), "Utility icon stays visible during cooldown when ready-only is disabled")
print("Cooldown-only: spell timer, ready state, completion, refresh, persistence, edit mode, and disabling passed")
print("Utility visibility: cooldown-only preserves visibility; ready-only retains layout slots and restores icons")
