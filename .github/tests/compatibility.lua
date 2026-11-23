-- Native HUD tables are hostile to addon access in this test: any unsupported
-- read, write, hook, or layout call fails, while custom widgets remain usable.
local driver, frames = nil, {}
local function widget()
    local result = { shown = true, width = 30, height = 30, scale = 1, scripts = {}, children = {} }
    for _, name in ipairs({ "RegisterEvent", "RegisterUnitEvent", "SetAllPoints", "SetFrameLevel",
        "SetSwipeTexture", "SetSwipeColor", "SetDrawBling", "SetDrawSwipe", "SetCountdownFont",
        "SetHideCountdownNumbers", "SetAtlas", "AddMaskTexture", "EnableMouse", "SetText" }) do
        result[name] = function() end
    end
    function result:SetScript(event, callback) self.scripts[event] = callback end
    function result:SetPoint(...) self.point = {...} end
    function result:ClearAllPoints() self.point = nil end
    function result:GetChildren() return unpack(self.children) end
    function result:SetShown(shown) self.shown = shown end
    function result:IsShown() return self.shown end
    function result:Show() self.shown = true end
    function result:Hide() self.shown = false end
    function result:GetWidth() return self.width end
    function result:GetHeight() return self.height end
    function result:GetScale() return self.scale end
    function result:SetSize(width, height) self.width, self.height = width, height end
    function result:SetScale(scale) self.scale = scale end
    function result:GetFrameLevel() return 1 end
    function result:CreateTexture() return widget() end
    result.CreateMaskTexture, result.CreateFontString = result.CreateTexture, result.CreateTexture
    function result:SetTexture(id) self.textureID = id end
    function result:SetDesaturated(value) self.desaturated = value end
    function result:GetCountdownMillisecondsThreshold() return 0 end
    function result:SetCountdownMillisecondsThreshold(value) self.threshold = value end
    function result:Clear() self.cleared = true end
    function result:Layout() self.layouts = (self.layouts or 0) + 1 end
    return result
end
function CreateFrame(kind, _, parent, template)
    local result = widget()
    result.kind, result.parent, result.template = kind, parent, template
    if parent and parent.children then parent.children[#parent.children + 1] = result end
    frames[#frames + 1] = result
    if not driver then driver = result end
    return result
end
function wipe(values) for key in pairs(values) do values[key] = nil end end
function hooksecurefunc() error("Compatibility mode must not hook Blizzard") end
UIParent, SlashCmdList = { GetEffectiveScale = function() return 1 end }, {}
C_Timer = { After = function(_, callback) callback() end }
Enum = { SpellBookSpellBank = { Player = 0 } }
C_SpellBook = { GetNumSpellBookSkillLines = function() return 0 end }
C_UnitAuras = { GetUnitAuras = function() return {} end }
C_Spell = {
    GetSpellInfo = function(id) return { name = "Spell " .. id, iconID = id } end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
}
C_Item = { GetItemCount = function() return 0 end }
BetterForeverCooldownsDB = {
    customCooldowns = { spells = { [42] = { section = "utility" } }, buffs = { [5] = {section = "auras"} } },
    auras = { overrides = { [5] = { visibility = "missing", auraID = 5 } } },
}
local visible = true
local function native(count, size)
    local children = {}
    for index = 1, count or 0 do
        local fields = {
            layoutIndex = index, cooldownID = index, includeAsLayoutChildWhenHidden = true,
            IsShown = function() return true end, GetSize = function() return size, size end,
        }
        children[index] = setmetatable({}, {
            __index = function(_, key) return fields[key] end,
            __newindex = function(_, key) error("Unexpected native icon write: " .. key) end,
        })
    end
    local fields = {
        iconScale = 1, timerShown = true, tooltipsShown = true,
        iconPadding = 8, iconLimit = 8, stride = 8, isHorizontal = true,
        layoutFramesGoingRight = true, layoutFramesGoingUp = false,
        GetChildren = function() return unpack(children) end,
        GetEffectiveScale = function() return 1 end,
        IsVisible = function() return visible end, IsEditing = function() return false end,
    }
    return setmetatable({}, {
        __index = function(_, key)
            if fields[key] ~= nil then return fields[key] end
            error("Unexpected native HUD access: " .. key)
        end,
        __newindex = function(_, key) error("Unexpected native HUD write: " .. key) end,
    }), fields, children
end
EssentialCooldownViewer, BuffIconCooldownViewer, BuffBarCooldownViewer = native(1, 50), native(), native()
local utilitySettings, utilityChildren
UtilityCooldownViewer, utilitySettings, utilityChildren = native(2, 30)
CooldownViewerSettings = native()
local addon = { UpdateChoices = function() end, AttachOptions = function() end }
assert(loadfile("BetterForeverCooldowns/BetterForeverCooldowns.lua"))("BetterForeverCooldowns", addon)
driver.scripts.OnEvent(driver, "ADDON_LOADED", "BetterForeverCooldowns")
assert(addon.IsCompatibilityMode(), "New and existing installs default to compatibility mode")
addon.ApplySettings()
driver.scripts.OnEvent(driver, "BAG_UPDATE_DELAYED")
driver.scripts.OnEvent(driver, "UNIT_AURA", "player")
driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
local containers, visibilityDriver, cooldowns = {}, nil, 0
for _, frame in ipairs(frames) do
    if frame.betterCDMAppend then containers[#containers + 1] = frame end
    if frame.scripts.OnUpdate then visibilityDriver = frame end
    if frame.kind == "Cooldown" then cooldowns = cooldowns + 1 end
end
assert(#containers == 3, "Use addon-owned containers without mutating Blizzard's layouts")
assert(cooldowns == 1, "The custom Utility spell still has a timer")
local customUtility = containers[2].children[1]
assert(customUtility.point[2] == utilityChildren[2], "Append to the last Blizzard icon")
assert(customUtility.point[4] == 34 and customUtility.point[5] == 0, "Continue the native row with matching spacing")
assert(customUtility:GetWidth() == 30 and customUtility:GetScale() == 1, "Match native icon size and scale")
utilitySettings.layoutFramesGoingRight = false
visibilityDriver.scripts.OnUpdate(visibilityDriver, 0.3)
assert(customUtility.point[4] == -34 and customUtility.point[5] == 0, "Respect leftward native growth")
utilitySettings.layoutFramesGoingRight = true
utilitySettings.iconLimit = 2
visibilityDriver.scripts.OnUpdate(visibilityDriver, 0.3)
assert(customUtility.point[4] == -34 and customUtility.point[5] == -34, "Wrap at the native icon limit")
utilitySettings.isHorizontal, utilitySettings.iconLimit = false, 8
visibilityDriver.scripts.OnUpdate(visibilityDriver, 0.3)
assert(customUtility.point[4] == 0 and customUtility.point[5] == -34, "Append to vertical layouts too")
utilitySettings.isHorizontal, utilitySettings.iconScale = true, 1.5
visibilityDriver.scripts.OnUpdate(visibilityDriver, 0.3)
assert(customUtility:GetScale() == 1.5, "Follow native scale changes")
visible = false
visibilityDriver.scripts.OnUpdate(visibilityDriver, 0.3)
for _, frame in ipairs(containers) do assert(not frame:IsShown()) end
visible = true
visibilityDriver.scripts.OnUpdate(visibilityDriver, 0.3)
for _, frame in ipairs(containers) do assert(frame:IsShown(), "Restore custom rows when the native HUD becomes visible") end
local reloads = 0
function ReloadUI() reloads = reloads + 1 end
SlashCmdList.BETTERFOREVERCOOLDOWNS("advanced")
assert(not BetterForeverCooldownsDB.compatibilityMode and reloads == 1)
SlashCmdList.BETTERFOREVERCOOLDOWNS("safe")
assert(BetterForeverCooldownsDB.compatibilityMode and reloads == 2)
print("Compatibility: read-only native geometry, appended icons, wrapping, direction, scale, visibility, and mode reloads passed")
