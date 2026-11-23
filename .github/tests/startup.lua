-- Load the shipped TOC in order with a shared private namespace, rather than
-- stubbing the options module out of startup tests.
local originalPrint = print
local function run(skipOptions)
    local driver, messages, registrations, panels = nil, {}, 0, 0
    BetterForeverCooldownsDB, CooldownViewerSettings = nil, nil
    SlashCmdList = {}
    Enum = { SpellBookSpellBank = { Player = 0 } }
    C_SpellBook = { GetNumSpellBookSkillLines = function() return 0 end }
    C_Spell = { RequestLoadSpellData = function() end }
    C_Item = { GetItemCount = function() return 0 end }
    C_UnitAuras = { GetUnitAuras = function() return {} end }
    C_Timer = { After = function(_, callback) callback() end }
    Menu = { ModifyMenu = function() registrations = registrations + 1 end }
    function print(message) messages[#messages + 1] = message end
    function wipe(values) for key in pairs(values) do values[key] = nil end end
    function CreateFrame()
        local frame = { scripts = {} }
        function frame:RegisterEvent() end
        function frame:RegisterUnitEvent() end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        if not driver then driver = frame end
        return frame
    end
    local addon, loaded = {}, {}
    for line in io.lines("BetterForeverCooldowns/BetterForeverCooldowns.toc") do
        local path = line:match("^%s*(.-)%s*$")
        if path:match("%.lua$") then
            local chunk = assert(loadfile("BetterForeverCooldowns/" .. path))
            if not (skipOptions and path == "Options.lua") then
                chunk("BetterForeverCooldowns", addon)
                loaded[path] = true
            end
        end
    end
    assert(loaded["BetterForeverCooldowns.lua"])
    if not skipOptions then
        assert(loaded["Options.lua"], "The TOC must ship and load Options.lua")
        assert(type(addon.AttachOptions) == "function" and type(addon.UpdateChoices) == "function")
    end
    local function event(name, argument) driver.scripts.OnEvent(driver, name, argument) end
    event("ADDON_LOADED", "BetterForeverCooldowns")
    event("PLAYER_LOGIN")
    event("PLAYER_ENTERING_WORLD")
    event("ADDON_LOADED", "Blizzard_CooldownViewer")
    addon.ApplySettings()
    CooldownViewerSettings = {
        IsVisible = function() return false end,
        ShowUIPanel = function() panels = panels + 1 end,
    }
    SlashCmdList.BETTERFOREVERCOOLDOWNS("")
    assert(panels == 1, "The settings command must still open Blizzard's panel")
    if skipOptions then
        assert(#messages == 1 and messages[1]:find("Options.lua did not load", 1, true),
            "A missing options module must report once without repeated nil-call errors")
        assert(registrations == 0)
    else
        assert(#messages == 0 and registrations == 1, "Normal startup must attach options exactly once")
    end
end
run(false)
run(true)
print = originalPrint
print("Startup: real TOC load, shared namespace, menu attachment, missing-module recovery, and settings command passed")
