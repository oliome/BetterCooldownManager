local addonName, Addon = ...
local db
local spells, spellsByID = {}, {}
local activeAuras = { HELPFUL = {}, HARMFUL = {} }
local auraListComplete = {}
local sections = {}
local unknownIcon = 134400

local defaults = {
    cooldowns = {
        numbers = true, swipe = true, stacks = true, ignoreGCD = true,
        showAll = false, allRanks = false, styleBlizzard = true,
        fontSize = 17, color = "ffffff", decimals = 5,
        size = 38, gap = 4, columns = 12, alignment = "CENTER", x = 0, y = 190,
        entries = {},
    },
    auras = {
        numbers = true, swipe = true, stacks = true, showMissing = true,
        fontSize = 17, color = "ffffff", decimals = 5,
        size = 38, gap = 4, columns = 12, alignment = "CENTER", x = 0, y = 125,
        entries = {},
    },
}

local function fillDefaults(values, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(values[key]) ~= "table" then values[key] = {} end
            fillDefaults(values[key], value)
        elseif type(values[key]) ~= type(value) then
            values[key] = value
        end
    end
end

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function number(value)
    if readable(value) and type(value) == "number" then return value end
end

local function apiCall(callback, ...)
    if not callback then return end
    local ok, result = pcall(callback, ...)
    if ok then return result end
end

local function spellMetadata(id)
    local info = C_Spell.GetSpellInfo(id)
    return info and info.name or ("Spell " .. id), info and info.iconID or unknownIcon
end

local function sortEntries(left, right)
    local a, b = left.name:lower(), right.name:lower()
    if a ~= b then return a < b end
    if left.level ~= right.level then return (left.level or 0) > (right.level or 0) end
    return left.id < right.id
end

local function scanSpellbook()
    wipe(spells)
    wipe(spellsByID)
    local book = C_SpellBook
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, book.GetNumSpellBookSkillLines() do
        local info = book.GetSpellBookSkillLineInfo(line)
        if info then
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = book.GetSpellBookItemInfo(slot, bank)
                if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive and not item.isOffSpec then
                    -- Keep the spellbook ID for pins and the slot for active overrides.
                    local id = item.actionID
                    if id and id > 0 and not spellsByID[id] then
                        local name, icon = spellMetadata(id)
                        local rank = C_Spell.GetSpellSubtext(id)
                        if not rank or rank == "" then rank = item.subName end
                        local entry = {
                            id = id, name = name, icon = icon, slot = slot,
                            rank = rank,
                            level = book.GetSpellBookItemLevelLearned(slot, bank),
                            lowerRank = book.IsSpellBookItemLowRank(slot, bank),
                        }
                        spellsByID[id] = entry
                        spells[#spells + 1] = entry
                    end
                end
            end
        end
    end
    table.sort(spells, sortEntries)
end

local function scanAuras()
    for filter, active in pairs(activeAuras) do
        wipe(active)
        local results = apiCall(C_UnitAuras.GetUnitAuras, "player", filter)
        auraListComplete[filter] = readable(results) and type(results) == "table"
        if auraListComplete[filter] then
            for _, aura in ipairs(results) do
                local id = readable(aura) and number(aura.spellId)
                if id then
                    active[id] = aura
                else
                    auraListComplete[filter] = false
                end
            end
        end
    end
end

function Addon.GetSettings(section)
    return db[section]
end

function Addon.GetChoices(section, filter, allRanks)
    local choices = {}
    if section == "cooldowns" then
        for _, entry in ipairs(spells) do
            if allRanks or not entry.lowerRank then choices[#choices + 1] = entry end
        end
    else
        for id in pairs(activeAuras[filter]) do
            local name, icon = spellMetadata(id)
            choices[#choices + 1] = { id = id, name = name, icon = icon, filter = filter }
        end
        table.sort(choices, sortEntries)
    end
    return choices
end

function Addon.GetEntryDetails(section, id)
    if section == "cooldowns" and spellsByID[id] then return spellsByID[id] end
    local name, icon = spellMetadata(id)
    return { id = id, name = name, icon = icon }
end

function Addon.FindPin(section, id, filter)
    for index, entry in ipairs(db[section].entries) do
        if entry.id == id and entry.filter == filter then return index, entry end
    end
end

function Addon.Pin(section, id, filter)
    if section == "cooldowns" and not spellsByID[id] then return false end
    if not Addon.FindPin(section, id, filter) then
        table.insert(db[section].entries, { id = id, filter = filter })
        Addon.ApplySettings()
    end
    return true
end

local function applyTimerStyle(cooldown, settings, override)
    local numbers = settings.numbers
    local swipe = settings.swipe
    if override then
        if override.numbers ~= nil then numbers = override.numbers end
        if override.swipe ~= nil then swipe = override.swipe end
    end
    cooldown:SetHideCountdownNumbers(not numbers)
    cooldown:SetDrawSwipe(swipe)
    cooldown:SetCountdownMillisecondsThreshold(settings.decimals)
    local label = cooldown:GetCountdownFontString()
    if label then
        local r = tonumber(settings.color:sub(1, 2), 16) or 255
        local g = tonumber(settings.color:sub(3, 4), 16) or 255
        local b = tonumber(settings.color:sub(5, 6), 16) or 255
        label:SetFont(STANDARD_TEXT_FONT, settings.fontSize, "OUTLINE")
        label:SetTextColor(r / 255, g / 255, b / 255)
    end
end

local function setDuration(cooldown, duration)
    if readable(duration) and duration and cooldown.SetCooldownFromDurationObject then
        local ok = pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration, true)
        return ok
    end
    return false
end

local function setSpellTimerFromNumbers(cooldown, info, ignoreGCD)
    if not readable(info) or not info then return false end
    local start, duration = number(info.startTime), number(info.duration)
    if not start or start <= 0 or not duration or duration <= 0 then return false end
    if ignoreGCD then
        local gcd = apiCall(C_Spell.GetSpellCooldown, 61304)
        -- If the comparison is unavailable, avoid displaying a GCD-only timer.
        if not readable(gcd) or not gcd then return false end
        local gcdStart, gcdDuration = number(gcd.startTime), number(gcd.duration)
        if not gcdStart or not gcdDuration or (start == gcdStart and duration == gcdDuration) then
            return false
        end
    end
    cooldown:SetCooldown(start, duration, number(info.modRate) or 1)
    return true
end

local function updateSpellTimer(icon, settings)
    local spell = icon.entry
    local book = C_SpellBook
    local bank = Enum.SpellBookSpellBank.Player
    local charges = apiCall(book.GetSpellBookItemCharges, spell.slot, bank)
    local current, maximum
    if readable(charges) and charges then
        current = number(charges.currentCharges)
        maximum = number(charges.maxCharges)
    end
    icon.count:SetText(settings.stacks and current or "")

    local duration
    local recharging = current and maximum and current < maximum
    if recharging then
        duration = apiCall(book.GetSpellBookItemChargeDuration, spell.slot, bank)
    end
    local cooldown = icon.cooldown
    if setDuration(cooldown, duration) then return end
    if recharging then
        local start = number(charges.cooldownStartTime)
        local seconds = number(charges.cooldownDuration)
        if start and start > 0 and seconds and seconds > 0 then
            cooldown:SetCooldown(start, seconds, number(charges.chargeModRate) or 1)
            return
        end
    end
    duration = apiCall(book.GetSpellBookItemCooldownDuration, spell.slot, bank, settings.ignoreGCD)
    if setDuration(cooldown, duration) then return end
    local id = spell.id
    if not spell.lowerRank then
        local overrideID = number(apiCall(C_Spell.GetOverrideSpell, id))
        if overrideID and overrideID > 0 then id = overrideID end
    end
    duration = apiCall(C_Spell.GetSpellCooldownDuration, id, settings.ignoreGCD)
    if setDuration(cooldown, duration) then return end
    local info = apiCall(book.GetSpellBookItemCooldown, spell.slot, bank)
    if not readable(info) or not info then info = apiCall(C_Spell.GetSpellCooldown, id) end
    if not setSpellTimerFromNumbers(cooldown, info, settings.ignoreGCD) then cooldown:Clear() end
end

local function updateAuraTimer(icon, settings, aura)
    local cooldown = icon.cooldown
    if not aura then
        cooldown:Clear()
        icon.count:SetText("")
        return
    end

    local instanceID = number(aura.auraInstanceID)
    local count = number(aura.applications)
    if settings.stacks and instanceID and not count then
        local formatted = apiCall(C_UnitAuras.GetAuraApplicationDisplayCount, "player", instanceID, 1)
        -- The native text widget may display a secret string without Lua reading it.
        if not readable(formatted) then
            if not pcall(icon.count.SetText, icon.count, formatted) then icon.count:SetText("") end
        else
            icon.count:SetText(formatted or "")
        end
    else
        icon.count:SetText(settings.stacks and count and count > 0 and count or "")
    end

    local duration = instanceID and apiCall(C_UnitAuras.GetAuraDuration, "player", instanceID)
    if not setDuration(cooldown, duration) then
        local seconds = number(aura.duration)
        local expires = number(aura.expirationTime)
        if seconds and seconds > 0 and expires and expires > 0 then
            cooldown:SetCooldown(expires - seconds, seconds, number(aura.timeMod) or 1)
        else
            cooldown:Clear()
        end
    end
end

local function createIcon(parent)
    local icon = CreateFrame("Frame", nil, parent)
    local border = icon:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.08, 0.08, 0.08, 1)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", 1, -1)
    icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon.texture)
    icon.cooldown:SetDrawBling(false)
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetMinimumCountdownDuration(0)
    icon.cooldown:SetCountdownAbbrevThreshold(600)
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)
    icon.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.count:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.missing = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icon.missing:SetPoint("CENTER")
    icon.missing:SetText("!")
    icon:SetMouseClickEnabled(false)
    icon:SetMouseMotionEnabled(true)
    icon:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.entry.id)
        if self.missing:IsShown() then GameTooltip:AddLine("Missing buff", 1, 0.55, 0.3) end
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return icon
end

local function savePosition(frame, settings)
    frame:StopMovingOrSizing()
    settings.x = (frame:GetLeft() + frame:GetRight()) / 2 - UIParent:GetWidth() / 2
    settings.y = frame:GetBottom()
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", settings.x, settings.y)
end

local function createSection(key, label)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame.icons = {}
    frame.handle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.handle:SetSize(158, 22)
    frame.handle:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.handle:SetText("Move " .. label)
    frame.handle:RegisterForDrag("LeftButton")
    frame.handle:SetScript("OnDragStart", function()
        frame.moving = true
        frame:StartMoving()
    end)
    local function stopMoving()
        if not frame.moving then return end
        frame.moving = nil
        savePosition(frame, db[key])
    end
    frame.handle:SetScript("OnDragStop", stopMoving)
    frame.handle:SetScript("OnHide", stopMoving)
    frame.handle:Hide()
    frame:Hide()
    return frame
end

local function cooldownEntries(settings)
    local entries, pinned = {}, {}
    for _, pin in ipairs(settings.entries) do
        local spell = spellsByID[pin.id]
        if spell then
            entries[#entries + 1] = { entry = spell, override = pin }
            pinned[pin.id] = true
        end
    end
    if settings.showAll then
        for _, spell in ipairs(spells) do
            if not pinned[spell.id] and (settings.allRanks or not spell.lowerRank) then
                entries[#entries + 1] = { entry = spell }
            end
        end
    end
    return entries
end

local function auraEntries(settings)
    local entries = {}
    for _, pin in ipairs(settings.entries) do
        local aura = activeAuras[pin.filter][pin.id]
        local missing = not aura and settings.showMissing and pin.filter == "HELPFUL" and auraListComplete.HELPFUL
        if missing and C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
            missing = apiCall(C_Secrets.ShouldSpellAuraBeSecret, pin.id) == false
        end
        if aura or missing then
            entries[#entries + 1] = {
                entry = Addon.GetEntryDetails("auras", pin.id), override = pin, aura = aura, missing = missing,
            }
        end
    end
    return entries
end

local function layoutSection(key)
    local frame = sections[key]
    local settings = db[key]
    local isAura = key == "auras"
    local entries = isAura and auraEntries(settings) or cooldownEntries(settings)
    local count = #entries
    local columns = math.max(1, math.min(settings.columns, count))
    local step = settings.size + settings.gap
    local width = columns * step - settings.gap
    local height = math.max(1, math.ceil(count / columns)) * step - settings.gap
    frame:SetSize(width, height)
    if not frame.moving then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", settings.x, settings.y)
    end

    for index, item in ipairs(entries) do
        local icon = frame.icons[index]
        if not icon then
            icon = createIcon(frame)
            frame.icons[index] = icon
            icon.cooldown:SetReverse(isAura)
            icon.cooldown:SetUseAuraDisplayTime(isAura)
        end
        local row = math.floor((index - 1) / columns)
        local column = (index - 1) % columns
        local spare = columns - math.min(columns, count - row * columns)
        local offset = settings.alignment == "RIGHT" and spare or settings.alignment == "CENTER" and spare / 2 or 0
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", frame, "TOPLEFT", (column + offset) * step, -row * step)
        icon:SetSize(settings.size, settings.size)
        icon.entry = item.entry
        icon.texture:SetTexture(item.entry.icon)
        icon.texture:SetDesaturated(item.missing == true)
        icon:SetAlpha(item.missing and 0.5 or 1)
        icon.missing:SetShown(item.missing == true)
        applyTimerStyle(icon.cooldown, settings, item.override)
        if isAura then
            updateAuraTimer(icon, settings, item.aura)
        else
            updateSpellTimer(icon, settings)
        end
        icon:Show()
    end
    for index = count + 1, #frame.icons do
        frame.icons[index].entry = nil
        frame.icons[index]:Hide()
    end
    frame:SetShown(count > 0 or frame.handle:IsShown())
end

local viewerHooks, itemHooks = {}, {}
local savedStyles = setmetatable({}, { __mode = "k" })

local function styleViewerItem(item, viewer)
    if not item.GetCooldownFrame then return end
    local cooldown = item:GetCooldownFrame()
    if not cooldown then return end
    local settings = db.cooldowns
    local id = apiCall(item.GetSpellID, item)
    local editing = viewer.IsEditing and viewer:IsEditing()
    if not settings.styleBlizzard or editing or not number(id) then
        local original = savedStyles[cooldown]
        if original then
            cooldown:SetHideCountdownNumbers(not viewer.timerShown)
            local swipe = item.cooldownShowSwipe
            if readable(swipe) and type(swipe) == "boolean" then cooldown:SetDrawSwipe(swipe) end
            cooldown:SetCountdownMillisecondsThreshold(original.decimals)
            local label = cooldown:GetCountdownFontString()
            if label and original.font then
                label:SetFont(original.font, original.size, original.flags)
                label:SetTextColor(unpack(original.color))
            end
            savedStyles[cooldown] = nil
        end
        return
    end

    if not savedStyles[cooldown] then
        local style = { decimals = cooldown:GetCountdownMillisecondsThreshold() }
        local label = cooldown:GetCountdownFontString()
        if label then
            style.font, style.size, style.flags = label:GetFont()
            style.color = { label:GetTextColor() }
        end
        savedStyles[cooldown] = style
    end
    local _, override = Addon.FindPin("cooldowns", id)
    applyTimerStyle(cooldown, settings, override)
end

local function styleViewer(viewer)
    if not viewer.itemFramePool then return end
    for item in viewer.itemFramePool:EnumerateActive() do
        if not itemHooks[item] and item.RefreshSpellCooldownInfo then
            hooksecurefunc(item, "RefreshSpellCooldownInfo", function(self)
                local cooldown = self:GetCooldownFrame()
                if cooldown and db.cooldowns.styleBlizzard and not viewer:IsEditing() then
                    local id = number(apiCall(self.GetSpellID, self))
                    if not id then return end
                    local _, override = Addon.FindPin("cooldowns", id)
                    local swipe = db.cooldowns.swipe
                    if override and override.swipe ~= nil then swipe = override.swipe end
                    cooldown:SetDrawSwipe(swipe)
                end
            end)
            itemHooks[item] = true
        end
        styleViewerItem(item, viewer)
    end
end

local function styleBlizzardViewers()
    for _, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer" }) do
        local viewer = _G[name]
        if viewer and viewer.itemFramePool then
            if not viewerHooks[viewer] then
                hooksecurefunc(viewer, "RefreshData", styleViewer)
                hooksecurefunc(viewer, "SetTimerShown", styleViewer)
                viewerHooks[viewer] = true
            end
            styleViewer(viewer)
        end
    end
end

function Addon.ApplySettings()
    layoutSection("cooldowns")
    layoutSection("auras")
    styleBlizzardViewers()
    if Addon.UpdateOptions then Addon.UpdateOptions() end
end

function Addon.SetMoving(moving)
    for key, section in pairs(sections) do
        section.handle:SetShown(moving)
        layoutSection(key)
    end
end

local catalogEvents = {
    PLAYER_ENTERING_WORLD = true, SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true,
    SPELL_TEXT_UPDATE = true, PLAYER_SPECIALIZATION_CHANGED = true,
}
local pending = {}
local scheduled
local function refresh()
    scheduled = false
    local update = pending
    pending = {}
    if update.catalog then
        scanSpellbook()
        layoutSection("cooldowns")
    elseif update.cooldowns then
        for _, icon in ipairs(sections.cooldowns.icons) do
            if icon.entry then updateSpellTimer(icon, db.cooldowns) end
        end
    end
    if update.auras then
        scanAuras()
        layoutSection("auras")
    end
    if update.blizzard then styleBlizzardViewers() end
    if (update.catalog or update.auras) and Addon.UpdateChoices then Addon.UpdateChoices() end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
for event in pairs(catalogEvents) do driver:RegisterEvent(event) end
driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
driver:RegisterEvent("SPELL_UPDATE_CHARGES")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterUnitEvent("UNIT_AURA", "player")
driver:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        if type(BetterForeverCooldownsDB) ~= "table" then BetterForeverCooldownsDB = {} end
        db = BetterForeverCooldownsDB
        fillDefaults(db, defaults)
        sections.cooldowns = createSection("cooldowns", "Cooldowns")
        sections.auras = createSection("auras", "Self Auras")
        return
    end
    if not db then return end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        pending.catalog, pending.auras, pending.blizzard = true, true, true
    elseif event == "ADDON_LOADED" and name == "Blizzard_CooldownViewer" then
        pending.blizzard = true
    elseif catalogEvents[event] then
        pending.catalog = true
    elseif event == "UNIT_AURA" then
        pending.auras = true
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        pending.cooldowns, pending.auras = true, true
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        pending.cooldowns = true
    else
        return
    end
    if not scheduled then
        scheduled = true
        C_Timer.After(0, refresh)
    end
end)

SLASH_BETTERFOREVERCOOLDOWNS1 = "/bfc"
SLASH_BETTERFOREVERCOOLDOWNS2 = "/betterforevercooldowns"
SlashCmdList.BETTERFOREVERCOOLDOWNS = function() Addon.ShowOptions() end
