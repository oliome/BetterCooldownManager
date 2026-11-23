-- Exercise the real addon with a learned Brilliance absent from Blizzard's list.
local driver
function CreateFrame()
    driver = {
        RegisterEvent = function() end,
        RegisterUnitEvent = function() end,
        SetScript = function(self, _, callback) self.onEvent = callback end,
    }
    return driver
end
function wipe(values) for key in pairs(values) do values[key] = nil end end
SlashCmdList = {}
BetterForeverCooldownsDB = { compatibilityMode = false }
C_Timer = { After = function(_, callback) callback() end }
Enum = {
    SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 },
    CooldownViewerCategory = { HiddenPassive = 3 },
}
local names = { "Intellect", "Brilliance", "Fireball", "Mage Armor", "Headmaster buff", "Saved buff" }
names[18264] = "Headmaster's Charge"
C_Spell = {
    GetSpellInfo = function(id) return { name = names[id], iconID = id } end,
    GetSpellSubtext = function() return "" end,
    IsSpellHelpful = function(id) return id == 1 or id == 2 end,
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 3 } end,
    GetSpellBookItemInfo = function(slot) return { itemType = 1, actionID = slot } end,
    GetSpellBookItemLevelLearned = function() return 1 end,
    IsSpellBookItemLowRank = function() return false end,
}
local auras = { { spellId = 5 } }
C_UnitAuras = { GetUnitAuras = function() return auras end }
local addon = { UpdateChoices = function() end }
assert(loadfile("BetterForeverCooldowns/BetterForeverCooldowns.lua"))("BetterForeverCooldowns", addon)
driver.onEvent(driver, "ADDON_LOADED", "BetterForeverCooldowns")
driver.onEvent(driver, "SPELLS_CHANGED")
driver.onEvent(driver, "UNIT_AURA", "player")
local function ids(selectedOnly)
    local result = {}
    for _, entry in ipairs(addon.GetBuffAlternatives(1, 1, selectedOnly)) do
        assert(not result[entry.id], "Duplicate alternative")
        result[entry.id] = true
    end
    return result
end
local entries = ids(false)
assert(entries[18264], "Headmaster's Charge must be available before applying it")
assert(entries[2], "Learned Brilliance must appear even without the settings UI or an active buff")
assert(entries[5], "An active buff from another player must appear")
assert(not entries[1] and not entries[3], "Exclude the reminder itself and harmful spells")
local function pool(values)
    return { EnumerateActive = function() local index = 0; return function()
        index = index + 1; return values[index]
    end end }
end
CooldownViewerSettings = { categoryPool = pool({ {
    GetCategoryObject = function() return { GetCategory = function() return 3 end } end,
    itemPool = pool({ { GetSpellID = function() return 2 end }, { GetSpellID = function() return 4 end } }),
} }) }
local applySettings = addon.ApplySettings
addon.ApplySettings = function() end
addon.SetBuffAlternative(1, 1, 6, true)
entries = ids(false)
assert(entries[2] and entries[4] and entries[5] and entries[6], "Merge all sources and retain saved selections")
entries = ids(true)
assert(entries[6] and not entries[2] and not entries[4] and not entries[5], "Selected view must only show selections")
C_Spell.IsSpellHelpful = function() error("Unavailable spell data") end
entries = ids(false)
assert(entries[4] and entries[5] and entries[6], "An unavailable helpful-spell query must preserve other sources")
-- Item buffs stay selectable after expiring, including after an addon reload.
auras = {}
driver.onEvent(driver, "UNIT_AURA", "player")
assert(ids(false)[5], "Remember an expired item buff")
driver.onEvent(driver, "ADDON_LOADED", "BetterForeverCooldowns")
assert(ids(false)[5], "Remember item buffs across reloads")
assert(addon.AddBuffReminder(5), "Create a reminder outside Blizzard's catalog")
assert(addon.GetCustomCooldowns("auras")[1].id == 5)
assert(addon.GetIconOverride("auras", 5).visibility == "missing")
assert(not addon.AddBuffReminder(-1), "Reject invalid spell IDs")

local children = {}
local container = { layoutFramesGoingRight = false }
container.points = { { "CENTER", {}, "CENTER", 0, 0 } }
function container:GetNumPoints() return #self.points end
function container:GetPoint(index) return unpack(self.points[index]) end
function container:ClearAllPoints() self.points = {} end
function container:SetPoint(point, relative, ...)
    assert(relative ~= self, "A HUD row cannot anchor to itself")
    self.points[#self.points + 1] = {point, relative, ...}
end
function container:Layout()
    self.visible = {}
    for _, child in ipairs(children) do
        if child.shown or child.includeAsLayoutChildWhenHidden then
            self.visible[#self.visible + 1] = child
        end
    end
    table.sort(self.visible, function(a, b) return a.layoutIndex < b.layoutIndex end)
end
local function frame()
    local result = { shown = true }
    function result:SetShown(shown) self.shown = shown end
    function result:IsShown() return self.shown end
    function result:Hide() self.shown = false end
    function result:SetSize() end
    function result:GetSize() return 40, 40 end
    function result:SetScale() end
    function result:SetScript() end
    function result:EnableMouse() end
    function result:CreateTexture() return {
        SetAllPoints = function() end, SetTexture = function() end,
        SetAtlas = function() end, SetPoint = function() end, AddMaskTexture = function() end,
    } end
    result.CreateMaskTexture = result.CreateTexture
    return result
end
local native = frame()
native.layoutIndex, native.includeAsLayoutChildWhenHidden = 1, true
function native:GetBaseSpellID() return 1 end
function native:GetSpellID() return 1 end
function native:ShouldBeShown() return true end
children[1] = native
function CreateFrame(_, _, parent)
    assert(parent == container)
    local result = frame()
    children[#children + 1] = result
    return result
end
local editing = false
BuffIconCooldownViewer = {
    itemFramePool = pool({native}), IsVisible = function() return true end,
    IsEditing = function() return editing end, GetItemContainerFrame = function() return container end,
}
-- Intellect is present, so hide its reminder; the missing item buff packs first.
auras = { {spellId = 1} }
driver.onEvent(driver, "UNIT_AURA", "player")
assert(not native.shown and not native.includeAsLayoutChildWhenHidden)
assert(#container.visible == 1 and container.visible[1].spellID == 5, "Missing item buff fills the first slot")
assert(container.layoutFramesGoingRight, "Grow from the left")
assert(container.points[1][1] == "TOPLEFT", "Keep the left edge fixed as icons hide")
auras = { {spellId = 1}, {spellId = 5} }
driver.onEvent(driver, "UNIT_AURA", "player")
assert(#container.visible == 0, "Hide item reminder when its buff is active")
auras = nil
driver.onEvent(driver, "UNIT_AURA", "player")
assert(#container.visible == 0, "Unknown aura state must not show a false missing reminder")
editing = true
driver.onEvent(driver, "UNIT_AURA", "player")
assert(native.includeAsLayoutChildWhenHidden == true and native.shown, "Restore native behavior while editing")
assert(container.points[1][1] == "CENTER" and not container.layoutFramesGoingRight, "Restore layout anchors while editing")
assert(#container.visible == 2, "Preview custom reminders in edit mode")
editing = false
addon.RemoveBuffReminder(5)
auras = {}
driver.onEvent(driver, "UNIT_AURA", "player")
assert(not children[2].shown, "Hide a removed custom reminder")
-- Blizzard's actual viewer is its own item container, rather than a child.
-- Preserve its Edit Mode anchors instead of clearing them and self-anchoring.
container.points = { { "CENTER", {}, "CENTER", 120, -60 } }
container.itemFramePool = pool({native})
container.IsVisible = function() return true end
container.IsEditing = function() return editing end
container.GetItemContainerFrame = function(self) return self end
BuffIconCooldownViewer = container
driver.onEvent(driver, "UNIT_AURA", "player")
assert(container.points[1][1] == "CENTER" and container.points[1][4] == 120,
    "A viewer that is its own container must keep its original HUD anchors")
driver.onEvent(driver, "UNIT_AURA", "player")
assert(#container.points == 1, "Repeated refreshes must not detach the row")
-- A bar viewer's aura maps are forbidden to addon execution. Leave the bar
-- viewer and its native stack labels entirely alone, including during login.
BuffIconCooldownViewer = nil
BuffBarCooldownViewer = setmetatable({}, {
    __index = function() error("Addon must not access Blizzard's buff-bar viewer") end,
    __newindex = function() error("Addon must not modify Blizzard's buff-bar viewer") end,
})
function hooksecurefunc(target)
    assert(target ~= BuffBarCooldownViewer, "Do not hook the buff-bar refresh")
end
addon.AttachOptions = function() end
CooldownViewerSettings = nil
C_Item = { GetItemCount = function() return 0 end }
applySettings()
driver.onEvent(driver, "PLAYER_LOGIN")
-- Single-target and group intellect buffs suppress either reminder, across
-- ranks, including ranks discovered from localized spell metadata.
names[1459], names[10157], names[23028] = "Arcane Intellect", "Arcane Intellect", "Arcane Brilliance"
names[999901] = "Arcane Intellect"
BuffIconCooldownViewer = container
addon.AddBuffReminder(23028)
auras = { {spellId = 10157} }
driver.onEvent(driver, "UNIT_AURA", "player")
assert(not children[2].shown, "High-rank Arcane Intellect must suppress Arcane Brilliance")
auras = { {spellId = 999901} }
driver.onEvent(driver, "UNIT_AURA", "player")
assert(not children[2].shown, "Additional ranks with the localized Intellect name must suppress Brilliance")
auras = { {spellId = 4} }
driver.onEvent(driver, "UNIT_AURA", "player")
assert(children[2].shown, "Unrelated buffs must not suppress Brilliance")
addon.RemoveBuffReminder(23028)
addon.AddBuffReminder(1459)
auras = { {spellId = 23028} }
driver.onEvent(driver, "UNIT_AURA", "player")
assert(not children[2].shown, "Arcane Brilliance must suppress Arcane Intellect too")
auras = {}
driver.onEvent(driver, "UNIT_AURA", "player")
assert(children[2].shown, "Show the reminder when both intellect buffs are absent")
auras = nil
driver.onEvent(driver, "UNIT_AURA", "player")
assert(not children[2].shown, "An unknown aura state must not claim that intellect is missing")
addon.RemoveBuffReminder(1459)
addon.AddBuffReminder(18264)
auras = { {spellId = 10157} }
driver.onEvent(driver, "UNIT_AURA", "player")
assert(children[2].shown, "Intellect must not suppress the separate Headmaster's Charge reminder")
auras = { {spellId = 18264} }
driver.onEvent(driver, "UNIT_AURA", "player")
assert(not children[2].shown, "Hide Headmaster's Charge reminder while its own buff is active")
auras = {}
driver.onEvent(driver, "UNIT_AURA", "player")
assert(children[2].shown, "Show Headmaster's Charge when its buff expires")
print("Buff alternatives: learned Brilliance, active buffs, hidden entries, deduplication, selected view, and API failure passed")
print("Custom buffs: expired item discovery, persistence, missing/present/unknown states, compact left layout, edit mode, and removal passed")
print("Buff-bar isolation: settings and login do not access, modify, or hook the native bar viewer")
print("Intellect equivalence: Brilliance, Intellect, known and localized ranks, unrelated buffs, absence, and unknown states passed")
print("Headmaster's Charge: preset discovery and independent missing-buff tracking passed")
