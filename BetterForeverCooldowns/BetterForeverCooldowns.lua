local addonName, Addon = ...
local db
local spells, spellsByID = {}, {}
local activeBuffs = {}
local buffListComplete
local manaGemsSpellID = 1318827
local manaGemItemIDs = { 5514, 5513, 8007, 8008 }
local manaGemCount
local itemCountLabels = setmetatable({}, { __mode = "k" })
local itemCountDesaturation = setmetatable({}, { __mode = "k" })
local itemCountSettingsAttached
local countdownThresholds = setmetatable({}, { __mode = "k" })
local viewerNames = {
    cooldowns = { "EssentialCooldownViewer", "UtilityCooldownViewer" },
    auras = { "BuffIconCooldownViewer" },
}

local defaults = {
    compatibilityMode = true,
    knownBuffs = { [18264] = true }, -- Headmaster's Charge: buff spell, not item ID 13937.
    shortCooldownDecimals = true,
    cooldowns = { overrides = {}, dividers = {} },
    auras = { overrides = {} },
    customCooldowns = { spells = {}, items = {}, buffs = {} },
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

local function isManaGems(item)
    return number(apiCall(item.GetBaseSpellID, item)) == manaGemsSpellID
        or number(apiCall(item.GetSpellID, item)) == manaGemsSpellID
end

local function getItemCount(id)
    return number(apiCall(C_Item.GetItemCount, id, false))
end

local function visibleItemCount(count, id, slot)
    if not count or count == 0 or slot == 13 or slot == 14 then return end
    local trinketType = Enum.InventoryType and Enum.InventoryType.IndexTrinketType
    if id and trinketType and number(apiCall(C_Item.GetItemInventoryTypeByID, id)) == trinketType then
        return
    end
    return count
end

function Addon.GetShortCooldownDecimals()
    return db.shortCooldownDecimals
end

function Addon.SetShortCooldownDecimals(enabled)
    db.shortCooldownDecimals = enabled
    Addon.ApplySettings()
end

local function updateCountdownThreshold(cooldown)
    local original = countdownThresholds[cooldown]
    if db.shortCooldownDecimals then
        local current = cooldown:GetCountdownMillisecondsThreshold()
        if original == nil then
            countdownThresholds[cooldown] = current
        end
        if current ~= 3 then
            cooldown:SetCountdownMillisecondsThreshold(3)
        end
    elseif original ~= nil then
        cooldown:SetCountdownMillisecondsThreshold(original)
        countdownThresholds[cooldown] = nil
    end
end

local function updateItemCountLabel(frame, count)
    local label = itemCountLabels[frame]
    if not label and count ~= nil then
        local overlay = CreateFrame("Frame", nil, frame)
        overlay:SetAllPoints()
        overlay:SetFrameLevel(frame:GetFrameLevel() + 8)
        label = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        label:SetPoint("BOTTOMRIGHT", -3, 3)
        itemCountLabels[frame] = label
    end
    if label then label:SetText(count or "") end
end

local function getNativeItemCount(item)
    if isManaGems(item) then return manaGemCount end
    local slot = number(apiCall(item.GetEquipSlot, item))
    if slot then
        local id = number(apiCall(GetInventoryItemID, "player", slot))
        if id then return getItemCount(id), id, slot end
        return 0, nil, slot
    end
    local id = number(apiCall(item.GetSpellCategoryTooltipItemID, item))
    if id then return getItemCount(id), id end
end

local function refreshNativeItemCount(item, icon)
    if not icon then return end
    local count, id, slot = getNativeItemCount(item)
    local wasDesaturated = itemCountDesaturation[item]
    if count == 0 then
        local current = apiCall(icon.IsDesaturated, icon)
        if readable(current) and type(current) == "boolean" then
            if wasDesaturated == nil or not current then itemCountDesaturation[item] = current end
            if not current then icon:SetDesaturated(true) end
        end
    elseif wasDesaturated ~= nil then
        local current = apiCall(icon.IsDesaturated, icon)
        if readable(current) and current == true then icon:SetDesaturated(wasDesaturated) end
        itemCountDesaturation[item] = nil
    end
    updateItemCountLabel(item, visibleItemCount(count, id, slot))
end

local function refreshItemCountSettings(manager)
    for display in manager.categoryPool:EnumerateActive() do
        for item in display.itemPool:EnumerateActive() do
            refreshNativeItemCount(item, item.Icon)
        end
    end
end

local function refreshItemAvailability()
    local total = 0
    for _, id in ipairs(manaGemItemIDs) do
        local count = getItemCount(id)
        if count == nil then
            total = nil
            break
        end
        total = total + count
    end
    manaGemCount = total

    if db.compatibilityMode then return end

    local manager = _G.CooldownViewerSettings
    if manager and manager.categoryPool then
        if not itemCountSettingsAttached then
            hooksecurefunc(manager, "RefreshLayout", refreshItemCountSettings)
            itemCountSettingsAttached = true
        end
        if manager:IsShown() then refreshItemCountSettings(manager) end
    end
end

local function spellMetadata(id)
    local info = C_Spell.GetSpellInfo(id)
    return info and info.name or ("Spell " .. id), info and info.iconID or 134400
end

local function sortEntries(left, right)
    local a, b = left.name:lower(), right.name:lower()
    if a ~= b then return a < b end
    if left.level ~= right.level then return (left.level or 0) > (right.level or 0) end
    return left.id < right.id
end

-- Native layout indices belong to Blizzard. Custom entries sort between them.
function Addon.PlaceCustomCooldownFrames(native, custom, order, positions)
    table.sort(native, function(a, b) return a.layoutIndex < b.layoutIndex end)
    local slots, indices, ordered = {}, {}, {}
    for i, item in ipairs(native) do indices[number(item:GetCooldownID())] = i end
    local function place(id)
        local frame = custom[id]
        if not frame then return end
        custom[id] = nil
        local position = positions[id]
        local anchor = position and indices[position.anchor]
        local slot = anchor and (position.before and anchor - 1 or anchor) or #native
        slots[slot] = slots[slot] or {}
        table.insert(slots[slot], frame)
    end
    for _, id in ipairs(order) do place(id) end
    local remaining = {}
    for id in pairs(custom) do remaining[#remaining + 1] = id end
    table.sort(remaining)
    for _, id in ipairs(remaining) do place(id) end
    local changed = false
    for i = 0, #native do
        if native[i] then ordered[#ordered + 1] = native[i] end
        local bucket = slots[i] or {}
        local base = native[i] and native[i].layoutIndex or (native[1] and native[1].layoutIndex - 1 or 0)
        for j, frame in ipairs(bucket) do
            local index = base + j / (#bucket + 1)
            if frame.layoutIndex ~= index or not frame:IsShown() then
                frame.layoutIndex = index
                frame:Show()
                changed = true
            end
            ordered[#ordered + 1] = frame
        end
    end
    return ordered, changed
end

function Addon.ResolveCooldownEntry(text, isItem)
    local query = text:match("^%s*(.-)%s*$")
    if query == "" then return end
    local id = query:match("^%d+$") and tonumber(query)
    if id and (id < 1 or id > 2147483647) then return end
    if isItem then
        return number(apiCall(C_Item.GetItemInfoInstant, id or query))
    end
    local info = apiCall(C_Spell.GetSpellInfo, id or query)
    if readable(info) and info then return id or number(info.spellID) end
end

local itemStyles = {
    engineering = "Interface/Icons/Trade_Engineering",
    potion = "Interface/Icons/INV_Potion_114",
}

function Addon.GetUsableBagItems()
    local entries, seen = {}, {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = number(apiCall(C_Container.GetContainerItemID, bag, slot))
            if id and not seen[id] then
                seen[id] = true
                local spell = apiCall(C_Item.GetItemSpell, id)
                if readable(spell) and spell and not db.customCooldowns.items[id] then
                    local name = apiCall(C_Item.GetItemNameByID, id) or ("Item " .. id)
                    entries[#entries + 1] = { id = id, name = name, count = visibleItemCount(getItemCount(id), id) }
                end
            end
        end
    end
    table.sort(entries, sortEntries)
    return entries
end

function Addon.GetItemIconStyle(id)
    local entry = db.customCooldowns.items[id]
    return entry and entry.iconStyle
end

function Addon.SetItemIconStyle(id, style)
    local entry = db.customCooldowns.items[id]
    if not entry then return end
    entry.iconStyle = itemStyles[style] and style or nil
    Addon.ApplySettings()
end

function Addon.GetCustomCooldowns(section)
    local entries, order, positions = {}, {}, {}
    for _, kind in ipairs({ "spells", "items", "buffs" }) do
        local isItem = kind == "items"
        for id, entry in pairs(db.customCooldowns[kind]) do
            if entry.section == section then
                local name, icon
                if isItem then
                    name = apiCall(C_Item.GetItemNameByID, id) or ("Item " .. id)
                    icon = itemStyles[entry.iconStyle] or apiCall(C_Item.GetItemIconByID, id) or 134400
                else
                    name, icon = spellMetadata(id)
                end
                local key = isItem and -id or id
                local count = isItem and getItemCount(id) or nil
                entries[#entries + 1] = {
                    id = id, key = key, isItem = isItem, name = name, icon = icon, order = entry.order or id,
                    count = count, displayCount = visibleItemCount(count, id),
                }
                positions[key] = entry.position
            end
        end
    end
    table.sort(entries, function(a, b) return a.order < b.order or (a.order == b.order and a.key < b.key) end)
    for i, entry in ipairs(entries) do order[i] = entry.key end
    return entries, order, positions
end

function Addon.SetCustomCooldown(id, isItem, section)
    local saved = isItem and db.customCooldowns.items or db.customCooldowns.spells
    local old = saved[id]
    if section then
        if not old or old.section ~= section then
            saved[id] = { section = section, iconStyle = old and old.iconStyle }
        end
    else
        saved[id] = nil
    end
    Addon.ApplySettings()
end

function Addon.MoveCustomCooldown(key, section, anchor, before, neighbor)
    local function entry(id)
        return id < 0 and db.customCooldowns.items[-id] or db.customCooldowns.spells[id]
    end
    local saved = entry(key)
    if not saved or key == neighbor then return end
    saved.section = section
    local _, order = Addon.GetCustomCooldowns(section)
    tDeleteItem(order, key)
    local target = neighbor and entry(neighbor)
    if target and target.section == section then
        local position = target.position
        saved.position = position and { anchor = position.anchor, before = position.before }
        local index = tIndexOf(order, neighbor)
        table.insert(order, before and index or index + 1, key)
    else
        saved.position = { anchor = anchor, before = before }
        order[#order + 1] = key
    end
    for index, entryID in ipairs(order) do entry(entryID).order = index end
    Addon.ApplySettings()
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
    wipe(activeBuffs)
    local results = apiCall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
    buffListComplete = readable(results) and type(results) == "table"
    if not buffListComplete then return end
    for _, aura in ipairs(results) do
        local id = readable(aura) and number(aura.spellId)
        if id then
            activeBuffs[id] = true
            db.knownBuffs[id] = true
        else
            buffListComplete = false
        end
    end
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

function Addon.GetIconOverride(section, id)
    return db[section].overrides[id]
end

local function editableOverride(section, id)
    local overrides = db[section].overrides
    if not overrides[id] then overrides[id] = {} end
    return overrides[id]
end

function Addon.SetIconOverride(section, id, key, value)
    editableOverride(section, id)[key] = value
    Addon.ApplySettings()
end

local function setDuration(cooldown, duration)
    if readable(duration) and duration and cooldown.SetCooldownFromDurationObject then
        local active = apiCall(duration.IsActive, duration)
        if readable(active) and active == false then return false end
        local ok = pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration, true)
        return ok, active
    end
    return false
end

local function findPlayerAura(id)
    local api = C_UnitAuras
    local aura = apiCall(api.GetUnitAuraBySpellID, "player", id)
    if readable(aura) and aura then return aura end
    aura = apiCall(api.GetPlayerAuraBySpellID, id)
    if readable(aura) and aura then return aura end
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

local function setSpellTimerFromNumbers(cooldown, info)
    if not readable(info) or not info then return false end
    local start, duration = number(info.startTime), number(info.duration)
    if not start or start <= 0 or not duration or duration <= 0 or start + duration <= GetTime() then return false end
    local gcd = apiCall(C_Spell.GetSpellCooldown, 61304)
    -- If the comparison is unavailable, avoid displaying a GCD-only timer.
    if not readable(gcd) or not gcd then return false end
    local gcdStart, gcdDuration = number(gcd.startTime), number(gcd.duration)
    if not gcdStart or not gcdDuration or (start == gcdStart and duration == gcdDuration) then
        return false
    end
    cooldown:SetCooldown(start, duration, number(info.modRate) or 1)
    return true
end

local function updateSpellTimer(icon, id, slot, lowerRank)
    local book = C_SpellBook
    local bank = Enum.SpellBookSpellBank.Player
    if not lowerRank then
        local overrideID = number(apiCall(C_Spell.GetOverrideSpell, id))
        if overrideID and overrideID > 0 then id = overrideID end
    end
    local charges
    if slot then charges = apiCall(book.GetSpellBookItemCharges, slot, bank) end
    if readable(charges) and not charges then charges = apiCall(C_Spell.GetSpellCharges, id) end
    local current, maximum
    if readable(charges) and charges then
        current = number(charges.currentCharges)
        maximum = number(charges.maxCharges)
    end
    icon.count:SetText(maximum and maximum > 1 and current or "")

    local duration
    local recharging = current and maximum and current > 0 and current < maximum
    if recharging then
        if slot then duration = apiCall(book.GetSpellBookItemChargeDuration, slot, bank) end
        if readable(duration) and not duration then duration = apiCall(C_Spell.GetSpellChargeDuration, id) end
    end
    local cooldown = icon.cooldown
    if setDuration(cooldown, duration) then return true, false end
    if recharging then
        local start = number(charges.cooldownStartTime)
        local seconds = number(charges.cooldownDuration)
        if start and start > 0 and seconds and seconds > 0 and start + seconds > GetTime() then
            cooldown:SetCooldown(start, seconds, number(charges.chargeModRate) or 1)
            return true, false
        end
    end
    if slot then
        duration = apiCall(book.GetSpellBookItemCooldownDuration, slot, bank, true)
        local applied, active = setDuration(cooldown, duration)
        if applied then return true, active end
    end
    duration = apiCall(C_Spell.GetSpellCooldownDuration, id, true)
    local applied, active = setDuration(cooldown, duration)
    if applied then return true, active end
    local info
    if slot then info = apiCall(book.GetSpellBookItemCooldown, slot, bank) end
    if not readable(info) or not info then info = apiCall(C_Spell.GetSpellCooldown, id) end
    if setSpellTimerFromNumbers(cooldown, info) then return true, true end
    return false
end

local customCooldownFrames = {}

local function addCustomIconArtwork(frame, texture, section)
    local mask = frame:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
    mask:SetAllPoints()
    texture:AddMaskTexture(mask)
    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
    local x, y = 6, 5
    if section == "essential" then x, y = 9, 8 end
    if section == "auras" then x, y = 8, 7 end
    border:SetPoint("TOPLEFT", -x, y)
    border:SetPoint("BOTTOMRIGHT", x, -y)
end

local function refreshCustomCooldowns(viewer)
    local section = viewer.betterCDMSection or (viewer == _G.EssentialCooldownViewer and "essential" or "utility")
    local entries, order, positions = Addon.GetCustomCooldowns(section)
    local frames = customCooldownFrames[viewer]
    if #entries == 0 and not frames then return end
    local container = viewer:GetItemContainerFrame()
    frames = frames or {}
    customCooldownFrames[viewer] = frames
    local native, nativeSpells, custom = {}, {}, {}
    for item in viewer.itemFramePool:EnumerateActive() do
        if item.layoutIndex and number(item:GetCooldownID()) then
            native[#native + 1] = item
            local id = number(item:GetBaseSpellID())
            if id then nativeSpells[id] = true end
            id = number(item:GetSpellID())
            if id then nativeSpells[id] = true end
        end
    end
    local template = native[1]
    local size = section == "essential" and 50 or 30
    local width, height = viewer.betterCDMWidth or size, viewer.betterCDMHeight or size
    if template then width, height = template:GetSize(true) end
    local scale = viewer.iconScale or 1
    local used, changed = 0, false
    for _, entry in ipairs(entries) do
        if entry.isItem or not nativeSpells[entry.id] then
            used = used + 1
            local frame = frames[used]
            if not frame then
                frame = CreateFrame("Frame", nil, container)
                frame:Hide()
                frame.texture = frame:CreateTexture(nil, "ARTWORK")
                frame.texture:SetAllPoints()
                addCustomIconArtwork(frame, frame.texture, section)
                frame.cooldown = CreateFrame("Cooldown", nil, frame)
                frame.cooldown:SetAllPoints()
                frame.cooldown:SetSwipeTexture([[Interface\HUD\UI-HUD-CoolDownManager-Icon-Swipe]], 1, 1, 1, 1)
                frame.cooldown:SetSwipeColor(0, 0, 0, 0.7)
                frame.cooldown:SetDrawBling(false)
                frame.cooldown:SetDrawSwipe(true)
                frame.cooldown:SetCountdownFont(section == "essential" and "GameFontHighlightHugeOutline" or "GameFontHighlightOutline")
                local overlay = CreateFrame("Frame", nil, frame)
                overlay:SetAllPoints()
                overlay:SetFrameLevel(frame:GetFrameLevel() + 8)
                frame.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                frame.count:SetPoint("BOTTOMRIGHT", -2, 2)
                frame:EnableMouse(true)
                if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
                frame:SetScript("OnEnter", function(self)
                    if not self.betterCDMTooltipsShown then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if self.isItem then GameTooltip:SetItemByID(self.entryID)
                    else GameTooltip:SetSpellByID(self.entryID) end
                    GameTooltip:Show()
                end)
                frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
                frames[used] = frame
            end
            if frame:GetWidth() ~= width or frame:GetHeight() ~= height or frame:GetScale() ~= scale then
                frame:SetSize(width, height)
                frame:SetScale(scale)
                changed = true
            end
            frame.texture:SetTexture(entry.icon)
            frame.entryID, frame.isItem = entry.id, entry.isItem
            frame.betterCDMTooltipsShown = viewer.tooltipsShown ~= false
            frame.cooldown:SetHideCountdownNumbers(viewer.timerShown == false)
            updateCountdownThreshold(frame.cooldown)
            local applied, grey
            if entry.isItem then
                local count = entry.count
                local ok, start, duration, enabled = pcall(C_Item.GetItemCooldown, entry.id)
                start, duration = number(start), number(duration)
                applied = ok and readable(enabled) and (enabled == true or enabled == 1)
                    and start and duration and start > 0 and duration > 0 and start + duration > GetTime()
                if applied then frame.cooldown:SetCooldown(start, duration) end
                grey = count == 0 or not not applied
                frame.count:SetText(entry.displayCount or "")
            else
                local spell = spellsByID[entry.id]
                applied, grey = updateSpellTimer(frame, entry.id, spell and spell.slot, spell and spell.lowerRank)
            end
            if not applied then frame.cooldown:Clear() end
            frame.texture:SetDesaturated(readable(grey) and grey == true)
            custom[entry.key] = frame
        end
    end
    for index = used + 1, #frames do
        if frames[index]:IsShown() then
            frames[index].layoutIndex = nil
            frames[index]:Hide()
            changed = true
        end
    end
    local _, positioned = Addon.PlaceCustomCooldownFrames(native, custom, order, positions)
    if changed or positioned then container:Layout() end
end

local function isExactAuraMissing(id)
    local linked = number(apiCall(C_UnitAuras.GetCooldownAuraBySpellID, id))
    if activeBuffs[id] or activeBuffs[linked] then return false end
    local lookup = C_UnitAuras.GetAuraDataBySpellName
    local spellID = linked or id
    local aura = findPlayerAura(spellID)
    if aura and readable(aura.isHelpful) and aura.isHelpful == true then return false end
    local lookupAbsent
    if lookup then
        local name = apiCall(C_Spell.GetSpellName, spellID)
        if readable(name) and type(name) == "string" then
            local ok, helpful = pcall(lookup, "player", name, "HELPFUL")
            if ok and readable(helpful) then
                if helpful and number(helpful.spellId) == spellID then return false end
                lookupAbsent = helpful == nil
            end
        end
    end
    if buffListComplete then return true end
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local restricted = apiCall(C_Secrets.ShouldSpellAuraBeSecret, spellID)
        if not readable(restricted) or restricted ~= false then return nil end
        if lookupAbsent then return true end
    end
end

-- The group and single-target versions provide the same intellect buff. Match
-- their ranks too, including additional ranks with the same localized names.
local intellectBuffs = { 1459, 1460, 1461, 10156, 10157, 23028, 27126, 27127, 42995, 43002 }
local function spellName(id)
    local info = apiCall(C_Spell.GetSpellInfo, id)
    local name = readable(info) and info and info.name
    if readable(name) and type(name) == "string" then return name end
end

local function isIntellectBuff(id)
    for _, spellID in ipairs(intellectBuffs) do if spellID == id then return true end end
    local name = spellName(id)
    return name ~= nil and (name == spellName(1459) or name == spellName(23028))
end

local function isAuraMissing(id)
    local missing = isExactAuraMissing(id)
    if missing == false or not isIntellectBuff(id) then return missing end
    for activeID in pairs(activeBuffs) do
        if isIntellectBuff(activeID) then return false end
    end
    for _, spellID in ipairs(intellectBuffs) do
        if spellID ~= id then
            local absent = isExactAuraMissing(spellID)
            if absent == false then return false end
            if absent == nil then missing = nil end
        end
    end
    return missing
end

local function nativeBuffMissing(item)
    if not item or not item.GetAuraDataUnit or not item.GetAuraSpellInstanceID then return nil end
    local ok, unit = pcall(item.GetAuraDataUnit, item)
    local instanceOK, instance = pcall(item.GetAuraSpellInstanceID, item)
    if not ok or not instanceOK or not readable(unit) or not readable(instance) then return nil end
    if unit == "player" then
        local expired = apiCall(item.IsExpired, item)
        if readable(expired) and type(expired) == "boolean" then return expired end
        return nil
    end
    if unit == nil and instance == nil then return true end
end

local function missingForOverride(item, id, override)
    local missing = isAuraMissing(id)
    local nativeMissing = nativeBuffMissing(item)
    if nativeMissing == false then return false end
    if missing == nil then missing = nativeMissing end
    if missing == false then return false end
    for alternative in pairs(override.alternatives or {}) do
        local absent = isAuraMissing(alternative)
        if absent == false then return false end
        if absent == nil then missing = nil end
    end
    return missing
end

function Addon.SetMissingReminder(id, auraID, enabled)
    local override = editableOverride("auras", id)
    override.auraID = auraID
    override.visibility = enabled and "missing" or nil
    Addon.ApplySettings()
end

function Addon.SetBuffAlternative(id, auraID, alternative, enabled)
    if alternative == id or alternative == auraID then return end
    local override = editableOverride("auras", id)
    override.alternatives = override.alternatives or {}
    override.alternatives[alternative] = enabled and true or nil
    if enabled then
        db.knownBuffs[alternative] = true
        override.auraID = auraID
        override.visibility = "missing"
    end
    Addon.ApplySettings()
end

function Addon.GetBuffAlternatives(id, auraID, selectedOnly)
    local entries, seen = {}, {}
    if id then seen[id] = true end
    if auraID then seen[auraID] = true end
    local function add(spellID)
        if not spellID or seen[spellID] then return end
        seen[spellID] = true
        local name, icon = spellMetadata(spellID)
        entries[#entries + 1] = { id = spellID, name = name, icon = icon }
    end
    local override = id and Addon.GetIconOverride("auras", id)
    if selectedOnly then
        for spellID in pairs(override and override.alternatives or {}) do add(spellID) end
    else
        -- Blizzard's cooldown catalog omits some long-duration buffs (such as
        -- Brilliance). Include learned helpful spells even when not active.
        for _, spell in ipairs(spells) do
            local helpful = apiCall(C_Spell.IsSpellHelpful, spell.id)
            if readable(helpful) and helpful == true then add(spell.id) end
        end
        for spellID in pairs(activeBuffs) do add(spellID) end
        for spellID in pairs(db.knownBuffs) do add(spellID) end
        for spellID in pairs(override and override.alternatives or {}) do add(spellID) end
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

function Addon.AddBuffReminder(id)
    if type(id) ~= "number" or id < 1 or id % 1 ~= 0 then return false end
    local info = apiCall(C_Spell.GetSpellInfo, id)
    if not readable(info) or not info then return false end
    db.knownBuffs[id] = true
    db.customCooldowns.buffs[id] = db.customCooldowns.buffs[id] or {}
    db.customCooldowns.buffs[id].section = "auras"
    Addon.SetMissingReminder(id, id, true)
    return true
end

function Addon.RemoveBuffReminder(id)
    db.customCooldowns.buffs[id] = nil
    Addon.ApplySettings()
end

local customBuffFrames = {}
local buffLayoutSettings = setmetatable({}, { __mode = "k" })
local function layoutBuffReminders(viewer)
    local container = viewer:GetItemContainerFrame()
    local saved = buffLayoutSettings[container]
    -- Blizzard's standard viewers return themselves as the item container.
    -- Their anchors belong to Edit Mode: never clear or self-anchor them.
    if container == viewer then
        if viewer:IsEditing() then
            if saved then
                container.layoutFramesGoingRight = saved.goingRight
                buffLayoutSettings[container] = nil
            end
        else
            if not saved then
                buffLayoutSettings[container] = { goingRight = container.layoutFramesGoingRight }
            end
            container.layoutFramesGoingRight = true
        end
        container:Layout()
        return
    end
    if viewer:IsEditing() then
        if saved then
            container:ClearAllPoints()
            for _, point in ipairs(saved.points) do container:SetPoint(unpack(point)) end
            container.layoutFramesGoingRight = saved.goingRight
            buffLayoutSettings[container] = nil
        end
    else
        if not saved then
            saved = { points = {}, goingRight = container.layoutFramesGoingRight }
            for index = 1, container:GetNumPoints() do
                saved.points[index] = { container:GetPoint(index) }
            end
            buffLayoutSettings[container] = saved
        end
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", viewer, "TOPLEFT", 0, 0)
        container.layoutFramesGoingRight = true
    end
    container:Layout()
end

local function refreshCustomBuffs(viewer)
    local entries = Addon.GetCustomCooldowns("auras")
    local container = viewer:GetItemContainerFrame()
    local native, lastIndex = {}, 0
    local width, height = viewer.betterCDMWidth or 40, viewer.betterCDMHeight or 40
    for item in viewer.itemFramePool:EnumerateActive() do
        lastIndex = math.max(lastIndex, item.layoutIndex or 0)
        width, height = item:GetSize(true)
        local id = number(apiCall(item.GetBaseSpellID, item))
        if id then native[id] = true end
        id = number(apiCall(item.GetSpellID, item))
        if id then native[id] = true end
    end
    for index, entry in ipairs(entries) do
        local frame = customBuffFrames[index]
        if not frame then
            frame = CreateFrame("Frame", nil, container)
            frame.icon = frame:CreateTexture(nil, "ARTWORK")
            frame.icon:SetAllPoints()
            addCustomIconArtwork(frame, frame.icon, "auras")
            frame:SetScript("OnEnter", function(self)
                if not self.betterCDMTooltipsShown then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spellID)
                GameTooltip:Show()
            end)
            frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
            frame:EnableMouse(true)
            if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
            customBuffFrames[index] = frame
        end
        frame:SetSize(width, height)
        frame:SetScale(viewer.iconScale or 1)
        frame.layoutIndex = lastIndex + index
        frame.spellID = entry.id
        frame.betterCDMTooltipsShown = viewer.tooltipsShown ~= false
        frame.icon:SetTexture(entry.icon)
        local override = Addon.GetIconOverride("auras", entry.id) or {}
        local show = override.visibility == "missing" and missingForOverride(nil, entry.id, override) == true
            or override.visibility ~= "missing" and isAuraMissing(entry.id) == false
        frame:SetShown(not native[entry.id] and (viewer:IsEditing() or show))
    end
    for index = #entries + 1, #customBuffFrames do
        customBuffFrames[index].layoutIndex = nil
        customBuffFrames[index]:Hide()
    end
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

local viewerHooks = {}
local spellTimers = setmetatable({}, { __mode = "k" })
local filteredItems = setmetatable({}, { __mode = "k" })

local function restoreNativeTimer(timer, item)
    timer.cooldownOnly = nil
    timer.frame:Hide()
    if timer.nativeCooldown then
        timer.nativeCooldown:SetAlpha(timer.cooldownAlpha)
        if timer.chargeFrame then timer.chargeFrame:SetAlpha(timer.chargeAlpha) end
        timer.nativeCooldown, timer.chargeFrame = nil, nil
    end
    if timer.nativeDesaturated ~= nil then
        local icon = item:GetIconTexture()
        local desaturated = apiCall(icon.IsDesaturated, icon)
        if readable(desaturated) and desaturated == timer.desaturated then
            icon:SetDesaturated(timer.nativeDesaturated)
        end
    end
    timer.nativeDesaturated, timer.desaturated = nil, nil
end

local function updateNativeIcon(item, viewer, key)
    local baseID = number(apiCall(item.GetBaseSpellID, item))
    local id = number(apiCall(item.GetSpellID, item)) or baseID
    local override = id and not viewer:IsEditing() and (Addon.GetIconOverride(key, baseID or id) or Addon.GetIconOverride(key, id))
    local rank = override and spellsByID[override.rankID]
    local cooldownOnly = override and override.cooldownOnly == true
    local timer = spellTimers[item]
    local cooldownFrame = key == "cooldowns" and item:GetCooldownFrame()
    if cooldownFrame then updateCountdownThreshold(cooldownFrame) end
    local nativeCooldown = id and not viewer:IsEditing() and cooldownFrame
    -- Fill in a missing native combat timer without replacing a countdown Blizzard is already displaying.
    local fallback = nativeCooldown and not rank and InCombatLockdown()
        and number(apiCall(nativeCooldown.GetCooldownDuration, nativeCooldown)) == 0
    if timer and timer.nativeCooldown and not (rank or cooldownOnly) then restoreNativeTimer(timer, item) end
    if nativeCooldown and (rank or cooldownOnly or fallback) then
        if not timer then
            local frame = CreateFrame("Frame", nil, item)
            frame:SetAllPoints(item)
            frame:SetFrameLevel(item:GetFrameLevel() + 4)
            local cooldown = CreateFrame("Cooldown", nil, frame)
            cooldown:SetAllPoints(nativeCooldown)
            cooldown:SetSwipeTexture([[Interface\HUD\UI-HUD-CoolDownManager-Icon-Swipe]], 1, 1, 1, 1)
            cooldown:SetSwipeColor(CooldownViewerConstants.ITEM_COOLDOWN_COLOR:GetRGBA())
            cooldown:SetDrawBling(false)
            cooldown:SetDrawEdge(false)
            cooldown:SetDrawSwipe(true)
            cooldown:SetCountdownFont(item.cooldownFont or "GameFontHighlightOutline")
            local countFrame = CreateFrame("Frame", nil, frame)
            countFrame:SetAllPoints(item)
            countFrame:SetFrameLevel(cooldown:GetFrameLevel() + 1)
            local font = viewer == _G.EssentialCooldownViewer and "NumberFontNormal" or "NumberFontNormalSmall"
            local count = countFrame:CreateFontString(nil, "OVERLAY", font)
            count:SetPoint("BOTTOMRIGHT", -2, 2)
            timer = { frame = frame, cooldown = cooldown, count = count, countFrame = countFrame }
            cooldown:SetScript("OnCooldownDone", function()
                -- Keep the native aura timer suppressed when the spell is ready.
                if timer.cooldownOnly then return end
                restoreNativeTimer(timer, item)
            end)
            spellTimers[item] = timer
        end
        timer.cooldown:SetHideCountdownNumbers(nativeCooldown:GetHideCountdownNumbers())
        timer.cooldown:SetCountdownFormatter(nativeCooldown:GetCountdownFormatter())
        timer.cooldown:SetCountdownAbbrevThreshold(nativeCooldown:GetCountdownAbbrevThreshold())
        timer.cooldown:SetCountdownMillisecondsThreshold(nativeCooldown:GetCountdownMillisecondsThreshold())
        timer.cooldown:SetMinimumCountdownDuration(nativeCooldown:GetMinimumCountdownDuration())
        timer.cooldownOnly = cooldownOnly
        local spell = rank or (cooldownOnly and spellsByID[baseID or id])
        local applied, desaturated = updateSpellTimer(timer, spell and spell.id or id, spell and spell.slot, spell and spell.lowerRank)
        if applied or cooldownOnly then
            if not applied then
                timer.cooldown:Clear()
                desaturated = false
            end
            if (rank or cooldownOnly) and not timer.nativeCooldown then
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
            timer.countFrame:SetShown(not not (rank or cooldownOnly))
            if readable(desaturated) and type(desaturated) == "boolean" then
                local icon = item:GetIconTexture()
                local nativeDesaturated = apiCall(icon.IsDesaturated, icon)
                if readable(nativeDesaturated) and type(nativeDesaturated) == "boolean" then
                    if nativeDesaturated ~= timer.desaturated then timer.nativeDesaturated = nativeDesaturated end
                    icon:SetDesaturated(desaturated)
                    timer.desaturated = desaturated
                end
            end
            timer.frame:Show()
        else
            restoreNativeTimer(timer, item)
        end
    elseif timer and timer.frame:IsShown() then
        restoreNativeTimer(timer, item)
    end

    local mode = override and override.visibility
    if mode == "ready" or mode == "missing" then
        local show
        if mode == "ready" then
            show = isSpellReady(rank and rank.id or baseID or id)
        else
            show = missingForOverride(item, override.auraID or id, override)
        end
        if item:IsShown() ~= (show == true) then item:SetShown(show == true) end
        if not filteredItems[item] then
            filteredItems[item] = { includeHidden = item.includeAsLayoutChildWhenHidden }
        end
        -- Compact missing-buff reminders only. Cooldown rows retain their
        -- native footprint while ready-only icons are temporarily hidden.
        if key == "auras" then item.includeAsLayoutChildWhenHidden = false end
    elseif filteredItems[item] then
        item.includeAsLayoutChildWhenHidden = filteredItems[item].includeHidden
        filteredItems[item] = nil
        local shown = apiCall(item.ShouldBeShown, item)
        if readable(shown) and type(shown) == "boolean" and item:IsShown() ~= shown then item:SetShown(shown) end
    end
end

local dividerFrames = {}

local function refreshDividers(viewer)
    local selected = db.cooldowns.dividers
    local frames = dividerFrames[viewer]
    if not frames and not next(selected) then return end

    local ids = {}
    for item in viewer.itemFramePool:EnumerateActive() do
        local id = number(item:GetCooldownID())
        if id then ids[item] = id end
    end

    local container = viewer:GetItemContainerFrame()
    local items = container:GetLayoutChildren()
    local horizontal = container.isHorizontal
    local forward = (horizontal and container.layoutFramesGoingRight) or (not horizontal and container.layoutFramesGoingUp)
    local stride = container.stride or 1
    local padding = (horizontal and container.childXPadding or container.childYPadding) or 0
    local side = horizontal and (forward and "RIGHT" or "LEFT") or (forward and "TOP" or "BOTTOM")
    frames = frames or {}
    dividerFrames[viewer] = frames
    local used = 0
    for index, item in ipairs(items) do
        local nextItem = items[index + 1]
        local id = ids[item]
        local slot = id and selected[id] and number(apiCall(item.GetEquipSlot, item))
        local emptySlot = slot and getNativeItemCount(item) == 0
        if nextItem and index % stride ~= 0 and selected[id] and not emptySlot
            and item:IsShown() and nextItem:IsShown() then
            used = used + 1
            local frame = frames[used]
            if not frame then
                frame = CreateFrame("Frame", nil, container)
                frame.ignoreInLayout = true
                frame:SetFrameLevel(container:GetFrameLevel() + 5)
                frame:Hide()
                local shadow = frame:CreateTexture(nil, "ARTWORK")
                shadow:SetPoint("CENTER")
                shadow:SetColorTexture(0, 0, 0, 0.45)
                local line = frame:CreateTexture(nil, "OVERLAY")
                line:SetPoint("CENTER")
                line:SetColorTexture(1, 1, 1, 0.25)
                frame.shadow, frame.line = shadow, line
                frames[used] = frame
            end

            local width, height = item:GetSize(true)
            local scale = item:GetScale()
            local offset = (forward and 1 or -1) * padding / (2 * scale)
            frame:SetScale(scale)
            frame:SetSize(1, 1)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", item, side, horizontal and offset or 0, horizontal and 0 or offset)
            local lineWidth, lineHeight = horizontal and 2 or width * 0.65, horizontal and height * 0.65 or 2
            frame.line:SetSize(lineWidth, lineHeight)
            frame.shadow:SetSize(lineWidth + 2, lineHeight + 2)

            frame:Show()
        end
    end

    for index = used + 1, #frames do
        frames[index]:Hide()
        frames[index]:ClearAllPoints()
    end
end

function Addon.HasDivider(id)
    return db and db.cooldowns.dividers[id]
end

function Addon.SetDivider(id, enabled)
    db.cooldowns.dividers[id] = enabled and true or nil
    if db.compatibilityMode then return end
    for _, name in ipairs(viewerNames.cooldowns) do
        local viewer = _G[name]
        if viewer and viewer.itemFramePool then refreshDividers(viewer) end
    end
end

local function styleViewer(viewer, key)
    if not viewer.itemFramePool then return end
    for item in viewer.itemFramePool:EnumerateActive() do
        updateNativeIcon(item, viewer, key)
        if key == "cooldowns" then refreshNativeItemCount(item, item:GetIconTexture()) end
    end
    if key == "cooldowns" then
        refreshCustomCooldowns(viewer)
        refreshDividers(viewer)
    elseif key == "auras" then
        refreshCustomBuffs(viewer)
        layoutBuffReminders(viewer)
    end
end

-- Keep custom HUD widgets on addon-owned layout frames. In compatibility mode
-- we never hook, resize, lay out, hide, or change a Blizzard HUD icon/timer.
local standaloneViewers = {}
local standaloneVisibilityDriver

local function nativeAppendItems(native)
    local items = {}
    for _, child in ipairs({ native:GetChildren() }) do
        local index = number(child.layoutIndex)
        if index and number(child.cooldownID)
            and (child:IsShown() or child.includeAsLayoutChildWhenHidden == true) then
            items[#items + 1] = child
        end
    end
    table.sort(items, function(a, b) return a.layoutIndex < b.layoutIndex end)
    return items
end

local function layoutAppendedIcons(container, native, section)
    local items = nativeAppendItems(native)
    local last = items[#items]
    local width = section == "essential" and 50 or section == "auras" and 40 or 30
    local height = width
    if last then
        local w, h = last:GetSize(true)
        width, height = number(w) or width, number(h) or height
    end
    local scale = math.max(0.01, number(native.iconScale) or 1)
    local padding = (number(native.iconPadding) or 8) - 4
    local stride = math.max(1, math.floor(number(native.iconLimit) or number(native.stride) or 8))
    local horizontal = native.isHorizontal ~= false
    local xDirection = native.layoutFramesGoingRight == false and -1 or 1
    local yDirection = native.layoutFramesGoingUp == true and 1 or -1
    local nativeScale = number(native:GetEffectiveScale()) or 1
    local parentScale = number(UIParent:GetEffectiveScale()) or 1
    container:SetScale(nativeScale / parentScale)
    local function position(slot)
        local column, row = slot % stride, math.floor(slot / stride)
        if not horizontal then column, row = row, column end
        return column * (width * scale + padding) * xDirection,
            row * (height * scale + padding) * yDirection
    end
    local startSlot = last and math.floor(last.layoutIndex) or 0
    local baseX, baseY = position(last and startSlot - 1 or 0)
    local custom = {}
    for _, child in ipairs({ container:GetChildren() }) do
        if child.layoutIndex and child:IsShown() then custom[#custom + 1] = child end
    end
    table.sort(custom, function(a, b) return a.layoutIndex < b.layoutIndex end)
    for index, child in ipairs(custom) do
        local x, y = position(startSlot + index - 1)
        child:SetSize(width, height)
        child:SetScale(scale)
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", last or native, "TOPLEFT", (x - baseX) / scale, (y - baseY) / scale)
    end
end

local function refreshStandaloneViewer(native, section)
    local viewer = standaloneViewers[section]
    if not viewer then
        local container = CreateFrame("Frame", nil, UIParent)
        container.betterCDMAppend = true
        container:SetSize(1, 1)
        -- This is our frame, not a replacement method on Blizzard's viewer.
        container.Layout = function() layoutAppendedIcons(container, native, section) end
        viewer = {
            native = native,
            betterCDMSection = section,
            itemFramePool = { EnumerateActive = function() return function() end end },
            GetItemContainerFrame = function() return container end,
            IsEditing = function() return native:IsEditing() end,
        }
        standaloneViewers[section] = viewer
        container:SetPoint("TOPLEFT", native, "TOPLEFT", 0, 0)
        if not standaloneVisibilityDriver then
            standaloneVisibilityDriver = CreateFrame("Frame")
            local elapsed = 0
            standaloneVisibilityDriver:SetScript("OnUpdate", function(_, seconds)
                elapsed = elapsed + seconds
                if elapsed < 0.2 then return end
                elapsed = 0
                for _, standalone in pairs(standaloneViewers) do
                    local frame = standalone:GetItemContainerFrame()
                    local shown = standalone.native:IsVisible()
                    if frame:IsShown() ~= shown then frame:SetShown(shown) end
                    if shown then frame:Layout() end
                end
            end)
        end
    end
    local container = viewer:GetItemContainerFrame()
    local items = nativeAppendItems(native)
    if items[1] then viewer.betterCDMWidth, viewer.betterCDMHeight = items[1]:GetSize(true) end
    viewer.iconScale, viewer.timerShown, viewer.tooltipsShown = native.iconScale, native.timerShown, native.tooltipsShown
    container:SetShown(native:IsVisible())
    if section == "auras" then
        refreshCustomBuffs(viewer)
        container:Layout()
    else
        refreshCustomCooldowns(viewer)
        container:Layout()
    end
end

local function updateNativeIcons(key)
    if db.compatibilityMode then
        if key == "auras" then
            local native = _G.BuffIconCooldownViewer
            if native then refreshStandaloneViewer(native, "auras") end
        else
            for _, section in ipairs({ "essential", "utility" }) do
                local native = _G[section == "essential" and "EssentialCooldownViewer" or "UtilityCooldownViewer"]
                if native then refreshStandaloneViewer(native, section) end
            end
        end
        return
    end
    for _, name in ipairs(viewerNames[key]) do
        local viewer = _G[name]
        if viewer and viewer:IsVisible() and viewer.itemFramePool then
            styleViewer(viewer, key)
        end
    end
end

local function styleBlizzardViewers()
    if db.compatibilityMode then
        updateNativeIcons("cooldowns")
        updateNativeIcons("auras")
        return
    end
    for key, names in pairs(viewerNames) do
        for _, name in ipairs(names) do
            local viewer = _G[name]
            if viewer and viewer.itemFramePool then
                if not viewerHooks[viewer] then
                    local scheduled
                    local function refreshViewer(self)
                        if scheduled then return end
                        scheduled = true
                        -- Wait for Blizzard to finish refreshing and laying out its items.
                        C_Timer.After(0, function()
                            scheduled = false
                            styleViewer(self, key)
                        end)
                    end
                    hooksecurefunc(viewer, "RefreshData", refreshViewer)
                    hooksecurefunc(viewer, "RefreshLayout", refreshViewer)
                    if viewer.RefreshActiveFramesForTargetChange then
                        hooksecurefunc(viewer, "RefreshActiveFramesForTargetChange", refreshViewer)
                    end
                    hooksecurefunc(viewer, "SetTimerShown", refreshViewer)
                    hooksecurefunc(viewer, "SetIsEditing", refreshViewer)
                    viewerHooks[viewer] = true
                end
                styleViewer(viewer, key)
            end
        end
    end
end

local warnedMissingOptions
local function attachOptions()
    if type(Addon.AttachOptions) == "function" then
        Addon.AttachOptions()
        return true
    end
    if not warnedMissingOptions then
        warnedMissingOptions = true
        print("Better Forever Cooldowns: Options.lua did not load. Reinstall the complete BetterForeverCooldowns folder (both Lua files and the TOC), then reload. Check for an earlier Options.lua error.")
    end
    return false
end

function Addon.ApplySettings()
    styleBlizzardViewers()
    if type(Addon.UpdateChoices) == "function" then Addon.UpdateChoices() end
end

function Addon.IsCompatibilityMode()
    return db.compatibilityMode
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
    if update.blizzard or update.bags then refreshItemAvailability() end
    if not update.blizzard and (update.catalog or update.cooldowns or update.bags) then updateNativeIcons("cooldowns") end
    if update.auras then
        scanAuras()
        if not update.blizzard then updateNativeIcons("auras") end
    end
    if update.blizzard then
        styleBlizzardViewers()
        attachOptions()
    end
    if (update.catalog or update.auras) and Addon.UpdateChoices then Addon.UpdateChoices() end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("BAG_UPDATE_DELAYED")
driver:RegisterEvent("BAG_UPDATE_COOLDOWN")
driver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
for event in pairs(catalogEvents) do driver:RegisterEvent(event) end
driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
driver:RegisterEvent("SPELL_UPDATE_CHARGES")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterUnitEvent("UNIT_AURA", "player")
driver:RegisterEvent("SPELL_DATA_LOAD_RESULT")
driver:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        if type(BetterForeverCooldownsDB) ~= "table" then BetterForeverCooldownsDB = {} end
        db = BetterForeverCooldownsDB
        fillDefaults(db, defaults)
        migrateBuffAlternatives()
        db.cooldowns = { overrides = db.cooldowns.overrides, dividers = db.cooldowns.dividers }
        db.auras = { overrides = db.auras.overrides }
        for id, override in pairs(db.cooldowns.overrides) do
            if type(override) == "table" and (override.rankID or override.cooldownOnly == true or override.visibility == "ready") then
                db.cooldowns.overrides[id] = {
                    rankID = override.rankID,
                    cooldownOnly = override.cooldownOnly == true or nil,
                    visibility = override.visibility == "ready" and "ready" or nil,
                }
            else
                db.cooldowns.overrides[id] = nil
            end
        end
        for id, override in pairs(db.auras.overrides) do
            if type(override) == "table" and (override.visibility == "missing" or next(override.alternatives or {})) then
                db.auras.overrides[id] = {
                    auraID = override.auraID,
                    visibility = override.visibility == "missing" and "missing" or nil,
                    alternatives = override.alternatives,
                }
            else
                db.auras.overrides[id] = nil
            end
        end
        if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(18264) end
        return
    end
    if not db then return end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        pending.catalog, pending.auras, pending.blizzard = true, true, true
    elseif event == "ADDON_LOADED" and name == "Blizzard_CooldownViewer" then
        pending.blizzard = true
    elseif catalogEvents[event] then
        pending.catalog = true
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE_COOLDOWN" or event == "PLAYER_EQUIPMENT_CHANGED" then
        pending.bags = true
    elseif event == "UNIT_AURA" then
        pending.auras = true
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        if not db.knownBuffs[name] then return end
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
SlashCmdList.BETTERFOREVERCOOLDOWNS = function(message)
    local mode = type(message) == "string" and message:lower():match("^%s*(.-)%s*$")
    if mode == "safe" or mode == "advanced" then
        db.compatibilityMode = mode == "safe"
        ReloadUI()
        return
    end
    if type(Addon.ShowOptions) == "function" then
        Addon.ShowOptions()
    else
        attachOptions()
        local manager = _G.CooldownViewerSettings
        if manager and type(manager.ShowUIPanel) == "function" then manager:ShowUIPanel() end
    end
end
