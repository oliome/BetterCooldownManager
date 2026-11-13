local addonName, Addon = ...
local db
local spells, spellsByID = {}, {}
local activeAuras = { HELPFUL = {}, HARMFUL = {} }
local auraListComplete = {}
local auraSection
local essentialExtras, itemExtras
local unknownIcon = 134400
local viewerNames = {
    cooldowns = { "EssentialCooldownViewer", "UtilityCooldownViewer" },
    auras = { "BuffIconCooldownViewer" },
}

local defaults = {
    cooldowns = {
        numbers = true, swipe = true, stacks = true, ignoreGCD = true,
        styleBlizzard = true,
        fontSize = 17, color = "ffffff", decimals = 5,
        overrides = {}, rangeSpells = {}, items = {},
    },
    auras = {
        numbers = true, swipe = true, stacks = true, styleBlizzard = true,
        fontSize = 17, color = "ffffff", decimals = 5,
        size = 38, gap = 4, columns = 12, alignment = "CENTER",
        entries = {}, overrides = {}, barStacks = true,
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
                            skillLine = line,
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

function Addon.GetAuraChoices(filter)
    local choices = {}
    for id in pairs(activeAuras[filter]) do
        local name, icon = spellMetadata(id)
        choices[#choices + 1] = { id = id, name = name, icon = icon }
    end
    table.sort(choices, sortEntries)
    return choices
end

function Addon.GetRangeChoices()
    local choices = {}
    for _, spell in ipairs(spells) do
        local hasRange = apiCall(C_Spell.SpellHasRange, spell.id)
        if not spell.lowerRank and readable(hasRange) and hasRange == true then
            choices[#choices + 1] = spell
        end
    end
    return choices
end

local conjuredItems = {
    { name = "Healthstone", ids = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 } },
    { name = "Mana Gem", ids = { 8008, 8007, 5513, 5514 } },
    { name = "Soulstone", ids = { 16896, 16895, 16893, 16892, 5232 } },
}

function Addon.GetConjuredItems()
    return conjuredItems
end

function Addon.GetConjuredItem(family)
    for _, id in ipairs(family.ids) do
        local count = number(apiCall(C_Item.GetItemCount, id))
        if count and count > 0 then return id, count end
    end
    return family.ids[1], 0
end

function Addon.GetEntryDetails(section, id)
    if section == "cooldowns" and spellsByID[id] then return spellsByID[id] end
    local name, icon = spellMetadata(id)
    return { id = id, name = name, icon = icon }
end

function Addon.GetRanks(id, displayID)
    local seed = spellsByID[displayID] or spellsByID[id]
    local name = seed and seed.name or spellMetadata(displayID or id)
    local ranks = {}
    for _, spell in ipairs(spells) do
        if spell.name == name and spell.rank and spell.rank ~= ""
            and (not seed or seed.skillLine == spell.skillLine) then
            ranks[#ranks + 1] = spell
        end
    end
    return ranks
end

function Addon.FindPin(section, id, filter)
    if section ~= "auras" then return end
    for index, entry in ipairs(db[section].entries) do
        if entry.id == id and entry.filter == filter then return index, entry end
    end
end

function Addon.Pin(section, id, filter)
    if section ~= "auras" then return false end
    if not Addon.FindPin(section, id, filter) then
        table.insert(db[section].entries, { id = id, filter = filter })
        Addon.ApplySettings()
    end
    return true
end

function Addon.GetIconOverride(section, id, filter)
    local _, pin = Addon.FindPin(section, id, filter)
    return db[section].overrides[id] or pin
end

local function editableOverride(section, id, filter)
    local overrides = db[section].overrides
    if not overrides[id] then
        local previous = Addon.GetIconOverride(section, id, filter)
        overrides[id] = { numbers = previous and previous.numbers, swipe = previous and previous.swipe }
    end
    return overrides[id]
end

function Addon.SetIconOverride(section, id, filter, key, value)
    editableOverride(section, id, filter)[key] = value
    Addon.ApplySettings()
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

local function isSpellReady(id)
    local charges = apiCall(C_Spell.GetSpellCharges, id)
    if not readable(charges) then return nil end
    if charges then
        local current = number(charges.currentCharges)
        if current ~= nil then return current > 0 end
        return nil
    end
    local duration = apiCall(C_Spell.GetSpellCooldownDuration, id, true)
    if readable(duration) and (type(duration) == "table" or type(duration) == "userdata") then
        local remaining = number(apiCall(duration.GetRemainingDuration, duration))
        if remaining ~= nil then return remaining <= 0 end
    end
    local info = apiCall(C_Spell.GetSpellCooldown, id)
    if readable(info) and info then
        local start, seconds = number(info.startTime), number(info.duration)
        if start == 0 or seconds == 0 then return true end
        local gcd = apiCall(C_Spell.GetSpellCooldown, 61304)
        if start and seconds and readable(gcd) and gcd then
            local gcdStart, gcdSeconds = number(gcd.startTime), number(gcd.duration)
            if gcdStart and gcdSeconds then
                return (start == gcdStart and seconds == gcdSeconds) or start + seconds <= GetTime()
            end
        end
    end
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
        if self.entry.item then
            GameTooltip:SetItemByID(self.entry.id)
        else
            GameTooltip:SetSpellByID(self.entry.id)
        end
        if self.unknown then
            GameTooltip:AddLine("Status unavailable", 0.8, 0.8, 0.8)
        elseif self.missing:IsShown() then
            GameTooltip:AddLine("Missing buff", 1, 0.55, 0.3)
        end
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return icon
end

local function createSection()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame.icons = {}
    frame:Hide()
    return frame
end

local function visibleBuffs(viewer)
    local visible = {}
    if not viewer.itemFramePool then return visible end
    for item in viewer.itemFramePool:EnumerateActive() do
        local id = number(apiCall(item.GetSpellID, item))
        local baseID = number(apiCall(item.GetBaseSpellID, item))
        local override = db.auras.overrides[baseID or id]
        if item:IsVisible() or (override and override.visibility == "missing") then
            if id then visible[id] = true end
            if override and override.auraID then visible[override.auraID] = true end
        end
    end
    return visible
end

local function isAuraMissing(id, filter)
    if activeAuras[filter][id] then return false end
    if not auraListComplete[filter] then return nil end
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local restricted = apiCall(C_Secrets.ShouldSpellAuraBeSecret, id)
        if not readable(restricted) or restricted ~= false then return nil end
    end
    return true
end

local function missingForOverride(id, override)
    local missing = isAuraMissing(id, "HELPFUL")
    if missing == false then return false end
    for alternative in pairs(override.alternatives or {}) do
        local absent = isAuraMissing(alternative, "HELPFUL")
        if absent == false then return false end
        if absent == nil then missing = nil end
    end
    return missing
end

function Addon.SetMissingReminder(id, auraID, enabled)
    local override = editableOverride("auras", id, "HELPFUL")
    override.auraID = auraID
    override.visibility = enabled and "missing" or nil
    Addon.ApplySettings()
end

function Addon.SetBuffAlternative(id, auraID, alternative, enabled)
    if alternative == id or alternative == auraID then return end
    local override = editableOverride("auras", id, "HELPFUL")
    override.alternatives = override.alternatives or {}
    override.alternatives[alternative] = enabled and true or nil
    if enabled then
        override.auraID = auraID
        override.visibility = "missing"
    end
    Addon.ApplySettings()
end

function Addon.GetBuffAlternatives(id, auraID, selectedOnly)
    local entries, seen = {}, { [id] = true, [auraID] = true }
    local function add(spellID)
        if not spellID or seen[spellID] then return end
        seen[spellID] = true
        entries[#entries + 1] = Addon.GetEntryDetails("auras", spellID)
    end
    local override = Addon.GetIconOverride("auras", id, "HELPFUL")
    if selectedOnly then
        for spellID in pairs(override and override.alternatives or {}) do add(spellID) end
    else
        local manager = _G.CooldownViewerSettings
        if manager and manager.categoryPool then
            for display in manager.categoryPool:EnumerateActive() do
                if display:GetCategoryObject():GetCategory() == Enum.CooldownViewerCategory.HiddenPassive then
                    for item in display.itemPool:EnumerateActive() do
                        add(number(apiCall(item.GetSpellID, item)))
                    end
                end
            end
        end
    end
    table.sort(entries, sortEntries)
    return entries
end

local function migrateBuffAlternatives()
    for id, override in pairs(db.auras.overrides) do
        if override.alternatives == true then
            -- Preserve the old armor reminder as an editable list of spell IDs.
            local alternatives = {}
            for _, spellID in ipairs({ 168, 7300, 7301, 7302, 7320, 10219, 10220, 6117, 22782, 22783 }) do
                if spellID ~= id and spellID ~= override.auraID then alternatives[spellID] = true end
            end
            override.alternatives = alternatives
        elseif type(override.alternatives) ~= "table" then
            override.alternatives = nil
        end
    end
end

local function auraEntries(settings, visible)
    local entries = {}
    for _, pin in ipairs(settings.entries) do
        local aura = activeAuras[pin.filter][pin.id]
        local override = Addon.GetIconOverride("auras", pin.id, pin.filter)
        local missingOnly = pin.filter == "HELPFUL" and override and override.visibility == "missing"
        local missing
        if missingOnly then missing = missingForOverride(pin.id, override) end
        local unknown = InCombatLockdown()
            and (missingOnly and missing == nil or not missingOnly and not aura and isAuraMissing(pin.id, pin.filter) == nil)
        if (pin.filter == "HARMFUL" or not visible[pin.id]) and (missing or unknown or (aura and not missingOnly)) then
            entries[#entries + 1] = {
                entry = Addon.GetEntryDetails("auras", pin.id),
                override = override, aura = aura, missing = missing, unknown = unknown,
            }
        end
    end
    return entries
end

local function layoutAuras()
    local frame = auraSection
    local settings = db.auras
    local anchor = _G.BuffIconCooldownViewer
    if not anchor or not anchor:IsVisible() or anchor:IsEditing() then
        frame:Hide()
        return
    end
    local entries = auraEntries(settings, visibleBuffs(anchor))
    local count = #entries
    local columns = math.max(1, math.min(settings.columns, count))
    local step = settings.size + settings.gap
    local width = columns * step - settings.gap
    local height = math.max(1, math.ceil(count / columns)) * step - settings.gap
    frame:SetSize(width, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", anchor, "BOTTOM", 0, -settings.gap)
    frame:SetFrameStrata(anchor:GetFrameStrata())

    for index, item in ipairs(entries) do
        local icon = frame.icons[index]
        if not icon then
            icon = createIcon(frame)
            frame.icons[index] = icon
            icon.cooldown:SetReverse(true)
            icon.cooldown:SetUseAuraDisplayTime(true)
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
        icon.unknown = item.unknown
        icon.texture:SetDesaturated(item.missing == true or item.unknown == true)
        icon:SetAlpha((item.missing or item.unknown) and 0.55 or 1)
        icon.missing:SetText(item.unknown and "?" or "!")
        icon.missing:SetShown(item.missing == true or item.unknown == true)
        applyTimerStyle(icon.cooldown, settings, item.override)
        updateAuraTimer(icon, settings, item.aura)
        icon:Show()
    end
    for index = count + 1, #frame.icons do
        frame.icons[index].entry = nil
        frame.icons[index]:Hide()
    end
    frame:SetShown(count > 0)
end

local viewerHooks, itemHooks = {}, {}
local savedStyles = setmetatable({}, { __mode = "k" })
local rankTimers = setmetatable({}, { __mode = "k" })
local filteredItems = setmetatable({}, { __mode = "k" })

local function updateRange(icon)
    local inRange = apiCall(C_Spell.IsSpellInRange, icon.entry.id, "target")
    if readable(inRange) and inRange == false then
        icon.texture:SetVertexColor(1, 0.25, 0.25)
    else
        icon.texture:SetVertexColor(1, 1, 1)
    end
end

local function updateConjured(icon, family)
    local id, count = Addon.GetConjuredItem(family)
    if count == 0 and icon.family == family and icon.entry then id = icon.entry.id end
    icon.family = family
    icon.entry = { id = id, item = true }
    icon.texture:SetTexture(C_Item.GetItemIconByID(id) or unknownIcon)
    icon.texture:SetDesaturated(count == 0)
    icon.count:SetText(count)
    local info = apiCall(C_Spell.GetItemCooldown, id)
    if not setSpellTimerFromNumbers(icon.cooldown, info, false) then
        local ok, start, duration, enabled = pcall(C_Item.GetItemCooldown, id)
        start, duration = number(start), number(duration)
        if ok and readable(enabled) and enabled and start and duration and start > 0 and duration > 0 then
            icon.cooldown:SetCooldown(start, duration)
        else
            icon.cooldown:Clear()
        end
    end
end

local function updateExtraRow(frame, anchor, entries, render)
    if not anchor or not anchor:IsVisible() or (anchor.IsEditing and anchor:IsEditing()) or #entries == 0 then
        frame:Hide()
        return
    end
    local size, gap = 34, 4
    local width = math.min(12, #entries)
    frame:SetSize(width * (size + gap) - gap, math.ceil(#entries / 12) * (size + gap) - gap)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    frame:SetFrameStrata(anchor:GetFrameStrata())
    for index, entry in ipairs(entries) do
        local icon = frame.icons[index]
        if not icon then
            icon = createIcon(frame)
            icon.missing:Hide()
            frame.icons[index] = icon
        end
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", ((index - 1) % 12) * (size + gap), -math.floor((index - 1) / 12) * (size + gap))
        icon:SetSize(size, size)
        applyTimerStyle(icon.cooldown, db.cooldowns)
        render(icon, entry)
        icon:Show()
    end
    for index = #entries + 1, #frame.icons do frame.icons[index]:Hide() end
    frame:Show()
end

local function updateExtras()
    local essential, utility = _G.EssentialCooldownViewer, _G.UtilityCooldownViewer
    local existing = {}
    if essential and essential.itemFramePool then
        for item in essential.itemFramePool:EnumerateActive() do
            if item:IsVisible() then
                local id = number(apiCall(item.GetSpellID, item))
                local base = number(apiCall(item.GetBaseSpellID, item))
                if id then existing[id] = true end
                if base then existing[base] = true end
            end
        end
    end
    local rangeEntries = {}
    for _, spell in ipairs(spells) do
        if db.cooldowns.rangeSpells[spell.id] and not existing[spell.id] then rangeEntries[#rangeEntries + 1] = spell end
    end
    updateExtraRow(essentialExtras, essential, rangeEntries, function(icon, spell)
        icon.entry = spell
        icon.texture:SetTexture(spell.icon)
        updateRange(icon)
        updateSpellTimer(icon, db.cooldowns)
    end)
    local items = {}
    for _, family in ipairs(conjuredItems) do
        if db.cooldowns.items[family.name] then items[#items + 1] = family end
    end
    local itemAnchor = utility and utility:IsVisible() and utility or essential
    if itemAnchor == essential and essentialExtras:IsShown() then itemAnchor = essentialExtras end
    updateExtraRow(itemExtras, itemAnchor, items, updateConjured)
end


local function viewerOverride(item, key, id)
    local settings = db[key]
    local filter = key == "auras" and "HELPFUL" or nil
    local baseID = number(apiCall(item.GetBaseSpellID, item))
    local nativeOverride = settings.overrides[baseID or id]
    return nativeOverride or Addon.GetIconOverride(key, id, filter)
end

local unknownLabels = setmetatable({}, { __mode = "k" })

local function showUnknown(item, parent, unknown)
    local label = unknownLabels[item]
    if unknown and not label then
        label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetText("?")
        unknownLabels[item] = label
    end
    if label then
        if unknown and (label:GetParent() ~= parent or label:GetNumPoints() == 0) then
            label:SetParent(parent)
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
        end
        label:SetShown(unknown)
    end
end

local function updateNativeIcon(item, viewer, key)
    local id = number(apiCall(item.GetSpellID, item)) or number(apiCall(item.GetBaseSpellID, item))
    local override = id and not viewer:IsEditing() and viewerOverride(item, key, id)
    local rank = override and spellsByID[override.rankID]
    local timer = rankTimers[item]
    local nativeCooldown = rank and item:GetCooldownFrame()
    if nativeCooldown then
        if not timer then
            local frame = CreateFrame("Frame", nil, item)
            frame:SetAllPoints(item)
            frame:SetFrameLevel(item:GetFrameLevel() + 4)
            local cooldown = CreateFrame("Cooldown", nil, frame)
            cooldown:SetAllPoints(nativeCooldown)
            cooldown:SetSwipeTexture([[Interface\HUD\UI-HUD-CoolDownManager-Icon-Swipe]], 1, 1, 1, 1)
            cooldown:SetDrawBling(false)
            cooldown:SetDrawEdge(false)
            cooldown:SetCountdownFont(item.cooldownFont or "GameFontHighlightOutline")
            cooldown:SetScript("OnCooldownDone", function() updateNativeIcon(item, viewer, key) end)
            local countFrame = CreateFrame("Frame", nil, frame)
            countFrame:SetAllPoints(item)
            countFrame:SetFrameLevel(cooldown:GetFrameLevel() + 1)
            local font = viewer == _G.EssentialCooldownViewer and "NumberFontNormal" or "NumberFontNormalSmall"
            local count = countFrame:CreateFontString(nil, "OVERLAY", font)
            count:SetPoint("BOTTOMRIGHT", -2, 2)
            timer = { frame = frame, cooldown = cooldown, count = count }
            rankTimers[item] = timer
        end
        if not timer.nativeCooldown then
            timer.nativeCooldown = nativeCooldown
            timer.cooldownAlpha = nativeCooldown:GetAlpha()
            nativeCooldown:SetAlpha(0)
            local chargeFrame = item:GetChargeCountFrame()
            if chargeFrame then
                timer.chargeFrame = chargeFrame
                timer.chargeAlpha = chargeFrame:GetAlpha()
                chargeFrame:SetAlpha(0)
            end
        end
        timer.entry = rank
        applyTimerStyle(timer.cooldown, db[key], override)
        updateSpellTimer(timer, db[key])
        timer.frame:Show()
    elseif timer and timer.nativeCooldown then
        timer.frame:Hide()
        timer.nativeCooldown:SetAlpha(timer.cooldownAlpha)
        if timer.chargeFrame then timer.chargeFrame:SetAlpha(timer.chargeAlpha) end
        timer.nativeCooldown, timer.chargeFrame = nil, nil
    end

    local mode = override and override.visibility
    if mode == "ready" or mode == "missing" then
        local show
        if mode == "ready" then
            show = isSpellReady(rank and rank.id or id)
        else
            show = missingForOverride(override.auraID or id, override)
            local activeID = number(apiCall(item.GetAuraSpellID, item))
            if activeID and activeAuras.HELPFUL[activeID] then show = false end
        end
        local unknown = show == nil and InCombatLockdown()
        showUnknown(item, nativeCooldown and timer.frame or item, unknown)
        filteredItems[item] = true
        item:SetShown(show == true or unknown == true)
    else
        showUnknown(item, item, false)
        if filteredItems[item] then
            filteredItems[item] = nil
            local shown = apiCall(item.ShouldBeShown, item)
            if readable(shown) and type(shown) == "boolean" then item:SetShown(shown) end
        end
    end
end

local function styleStackCount(item, viewer, key)
    local label
    if key == "auras" and item.GetApplicationsFontString then
        label = item:GetApplicationsFontString()
    elseif key == "cooldowns" and item.GetChargeCountFrame then
        label = item:GetChargeCountFrame().Current
    end
    if label then label:SetShown(viewer:IsEditing() or not db[key].styleBlizzard or db[key].stacks) end
end

local function styleViewerItem(item, viewer, key)
    styleStackCount(item, viewer, key)
    if not item.GetCooldownFrame then return end
    local cooldown = item:GetCooldownFrame()
    if not cooldown then return end
    local settings = db[key]
    local id = number(apiCall(item.GetSpellID, item))
    local editing = viewer.IsEditing and viewer:IsEditing()
    if not settings.styleBlizzard or editing or not id then
        local original = savedStyles[cooldown]
        if original then
            cooldown:SetHideCountdownNumbers(not viewer.timerShown)
            local swipe = item.cooldownShowSwipe
            if key == "auras" then swipe = original.swipe end
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
        local style = {
            decimals = cooldown:GetCountdownMillisecondsThreshold(),
            swipe = apiCall(cooldown.GetDrawSwipe, cooldown),
        }
        local label = cooldown:GetCountdownFontString()
        if label then
            style.font, style.size, style.flags = label:GetFont()
            style.color = { label:GetTextColor() }
        end
        savedStyles[cooldown] = style
    end
    applyTimerStyle(cooldown, settings, viewerOverride(item, key, id))
end

local function styleViewer(viewer, key)
    if not viewer.itemFramePool then return end
    for item in viewer.itemFramePool:EnumerateActive() do
        local method = key == "auras" and "RefreshCooldownInfo" or "RefreshSpellCooldownInfo"
        if not itemHooks[item] and item[method] then
            hooksecurefunc(item, method, function(self)
                local cooldown = self:GetCooldownFrame()
                if cooldown and db[key].styleBlizzard and not viewer:IsEditing() then
                    local id = number(apiCall(self.GetSpellID, self))
                    if not id then return end
                    local override = viewerOverride(self, key, id)
                    local swipe = db[key].swipe
                    if override and override.swipe ~= nil then swipe = override.swipe end
                    cooldown:SetDrawSwipe(swipe)
                end
            end)
            local countMethod = key == "auras" and "RefreshApplications" or "RefreshSpellChargeInfo"
            if item[countMethod] then
                hooksecurefunc(item, countMethod, function(self) styleStackCount(self, viewer, key) end)
            end
            if item.UpdateShownState then
                hooksecurefunc(item, "UpdateShownState", function(self)
                    updateNativeIcon(self, viewer, key)
                end)
            end
            local cooldown = item:GetCooldownFrame()
            if cooldown then
                cooldown:HookScript("OnCooldownDone", function()
                    updateNativeIcon(item, viewer, key)
                end)
            end
            itemHooks[item] = true
        end
        styleViewerItem(item, viewer, key)
        updateNativeIcon(item, viewer, key)
    end
end

local function updateNativeIcons(key)
    for _, name in ipairs(viewerNames[key]) do
        local viewer = _G[name]
        if viewer and viewer:IsVisible() and viewer.itemFramePool then
            for item in viewer.itemFramePool:EnumerateActive() do
                updateNativeIcon(item, viewer, key)
            end
        end
    end
end

local function styleBlizzardViewers()
    for key, names in pairs(viewerNames) do
        for _, name in ipairs(names) do
            local viewer = _G[name]
            if viewer and viewer.itemFramePool then
                if not viewerHooks[viewer] then
                    local function refreshViewer(self) styleViewer(self, key) end
                    local layoutPending
                    local function queueLayout()
                        if layoutPending then return end
                        layoutPending = true
                        C_Timer.After(0, function()
                            layoutPending = false
                            if key == "auras" then layoutAuras() else updateExtras() end
                        end)
                    end
                    hooksecurefunc(viewer, "RefreshData", function(self)
                        refreshViewer(self)
                        queueLayout()
                    end)
                    hooksecurefunc(viewer, "SetTimerShown", refreshViewer)
                    hooksecurefunc(viewer, "SetIsEditing", function(self)
                        refreshViewer(self)
                        queueLayout()
                    end)
                    viewer:HookScript("OnShow", queueLayout)
                    viewer:HookScript("OnHide", queueLayout)
                    viewerHooks[viewer] = true
                end
                styleViewer(viewer, key)
            end
        end
    end
end

local function updateBarStacks()
    local viewer = _G.BuffBarCooldownViewer
    if not viewer or not viewer.itemFramePool then return end
    for item in viewer.itemFramePool:EnumerateActive() do
        local label = item:GetApplicationsFontString()
        if label then
            label:ClearAllPoints()
            label:SetPoint("BOTTOMRIGHT", item:GetIconFrame(), "BOTTOMRIGHT", -2, 2)
            label:SetShown(db.auras.barStacks)
        end
    end
end

local function attachBarStacks()
    local viewer = _G.BuffBarCooldownViewer
    if viewer and not viewerHooks[viewer] then
        hooksecurefunc(viewer, "RefreshData", updateBarStacks)
        viewerHooks[viewer] = true
    end
    updateBarStacks()
end

function Addon.ApplySettings()
    styleBlizzardViewers()
    layoutAuras()
    updateExtras()
    attachBarStacks()
    if Addon.UpdateOptions then Addon.UpdateOptions() end
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
    if update.catalog then scanSpellbook() end
    if update.catalog or update.cooldowns then updateNativeIcons("cooldowns") end
    if update.catalog or update.cooldowns or update.items then updateExtras() end
    if update.bags and Addon.RefreshCategoryButtons then Addon.RefreshCategoryButtons() end
    if update.auras then
        scanAuras()
        updateNativeIcons("auras")
        layoutAuras()
    end
    if update.blizzard then
        styleBlizzardViewers()
        attachBarStacks()
        Addon.AttachOptions()
    end
    if (update.catalog or update.auras) and Addon.UpdateChoices then Addon.UpdateChoices() end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("BAG_UPDATE_DELAYED")
driver:RegisterEvent("BAG_UPDATE_COOLDOWN")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
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
        migrateBuffAlternatives()
        db.cooldowns.showAll, db.cooldowns.allRanks = nil, nil
        db.auras.showMissing = nil
        if type(db.cooldowns.entries) == "table" then
            for _, pin in ipairs(db.cooldowns.entries) do
                if not db.cooldowns.overrides[pin.id] and (pin.numbers ~= nil or pin.swipe ~= nil) then
                    db.cooldowns.overrides[pin.id] = { numbers = pin.numbers, swipe = pin.swipe }
                end
            end
        end
        db.cooldowns.entries = nil
        auraSection = createSection()
        essentialExtras = createSection()
        itemExtras = createSection()
        local elapsed = 0
        essentialExtras:SetScript("OnUpdate", function(self, delta)
            elapsed = elapsed + delta
            if elapsed < 0.15 then return end
            elapsed = 0
            for _, icon in ipairs(self.icons) do
                if icon:IsShown() then updateRange(icon) end
            end
        end)
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
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE_COOLDOWN" or event == "PLAYER_TARGET_CHANGED" then
        pending.items = true
        if event == "BAG_UPDATE_DELAYED" then pending.bags = true end
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
