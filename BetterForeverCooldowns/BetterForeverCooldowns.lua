local addonName, Addon = ...
local db
local spells, spellsByID = {}, {}
local activeBuffs = {}
local buffListComplete
local manaGemsSpellID = 1318827
local manaGemItemIDs = { 5514, 5513, 8007, 8008 }
local manaGemsMissing
local manaGemHooks = setmetatable({}, { __mode = "k" })
local manaGemSettingsAttached
local viewerNames = {
    cooldowns = { "EssentialCooldownViewer", "UtilityCooldownViewer" },
    auras = { "BuffIconCooldownViewer" },
}

local defaults = {
    cooldowns = { overrides = {}, dividers = {} },
    auras = { overrides = {}, selfAuras = {}, discoveredDebuffs = {}, selfAuraOrder = {}, selfAuraPositions = {} },
}
local classDebuffs = {
    MAGE = { 400573, 41425 },
    PALADIN = { 25771 },
    PRIEST = { 6788 },
    SHAMAN = { 57724 },
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

local function refreshManaGemIcon(item, method)
    if not isManaGems(item) then return end
    if not manaGemHooks[item] then
        hooksecurefunc(item, method, function(self)
            if manaGemsMissing and isManaGems(self) then
                local icon = method == "RefreshIconState" and self.Icon or self:GetIconTexture()
                if icon then icon:SetDesaturated(true) end
            end
        end)
        manaGemHooks[item] = true
    end
    item[method](item)
end

local function refreshManaGemSettings(manager)
    for display in manager.categoryPool:EnumerateActive() do
        for item in display.itemPool:EnumerateActive() do
            refreshManaGemIcon(item, "RefreshIconState")
        end
    end
end

local function refreshManaGemAvailability()
    local missing = true
    for _, id in ipairs(manaGemItemIDs) do
        if number(apiCall(C_Item.GetItemCount, id, false)) ~= 0 then
            missing = false
            break
        end
    end
    manaGemsMissing = missing

    for _, name in ipairs(viewerNames.cooldowns) do
        local viewer = _G[name]
        if viewer and viewer.itemFramePool then
            for item in viewer.itemFramePool:EnumerateActive() do
                refreshManaGemIcon(item, "RefreshIconDesaturation")
            end
        end
    end
    local manager = _G.CooldownViewerSettings
    if manager and manager.categoryPool then
        if not manaGemSettingsAttached then
            hooksecurefunc(manager, "RefreshLayout", refreshManaGemSettings)
            manaGemSettingsAttached = true
        end
        if manager:IsShown() then refreshManaGemSettings(manager) end
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

function Addon.GetSelfAuraChoices(selectedOnly)
    local entries, seen = {}, {}
    local function add(id)
        if seen[id] then return end
        seen[id] = true
        local name, icon = spellMetadata(id)
        entries[#entries + 1] = { id = id, name = name, icon = icon }
    end
    local _, class = UnitClass("player")
    if not selectedOnly then
        for _, id in ipairs(classDebuffs[class] or {}) do
            if C_Spell.GetSpellInfo(id) then add(id) end
        end
        for id in pairs(db.auras.discoveredDebuffs) do add(id) end
    end
    for id in pairs(db.auras.selfAuras) do add(id) end
    table.sort(entries, sortEntries)
    return entries, db.auras.selfAuras
end

-- Native layout indices belong to Blizzard. Custom entries sort between them.
function Addon.PlaceSelfAuraFrames(native, custom)
    table.sort(native, function(a, b) return a.layoutIndex < b.layoutIndex end)
    local slots, indices, ordered = {}, {}, {}
    for i, item in ipairs(native) do indices[item:GetCooldownID()] = i end
    local positions = db.auras.selfAuraPositions
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
    for _, id in ipairs(db.auras.selfAuraOrder) do place(id) end
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

local selfAuraIcons = {}
local selfAuraInstances = {}

local function findPlayerAura(id)
    local api = C_UnitAuras
    local aura = apiCall(api.GetUnitAuraBySpellID, "player", id)
    if readable(aura) and aura then return aura end
    aura = apiCall(api.GetPlayerAuraBySpellID, id)
    if readable(aura) and aura then return aura end
end

local function refreshSelfAuras()
    local viewer = _G.BuffIconCooldownViewer
    if not viewer or not viewer.itemFramePool then return end
    local selected, discovered = db.auras.selfAuras, db.auras.discoveredDebuffs
    local active, seenInstances, resolvedIDs = {}, {}, {}
    local auras = apiCall(C_UnitAuras.GetUnitAuras, "player", "HARMFUL")
    if readable(auras) and type(auras) == "table" then
        for _, aura in ipairs(auras) do
            if readable(aura) then
                local id = number(aura.spellId)
                local instance = number(aura.auraInstanceID)
                if instance then seenInstances[instance] = aura end
                if id and readable(aura.sourceUnit) and aura.sourceUnit == "player" then discovered[id] = true end
                if id then resolvedIDs[id] = aura end
            end
        end
    end
    if not viewer:IsShown() then return end
    if next(selected) then
        local buffs = apiCall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
        if readable(buffs) and type(buffs) == "table" then
            for _, aura in ipairs(buffs) do
                if readable(aura) then
                    local id = number(aura.spellId)
                    local instance = number(aura.auraInstanceID)
                    if instance then seenInstances[instance] = aura end
                    if id then resolvedIDs[id] = aura end
                end
            end
        end
    end
    local instances, displayIDs = {}, {}
    for id in pairs(selected) do
        local linkedID = number(apiCall(C_UnitAuras.GetCooldownAuraBySpellID, id))
        local aura = resolvedIDs[id] or findPlayerAura(id)
        if not aura and linkedID and linkedID ~= id then
            aura = resolvedIDs[linkedID] or findPlayerAura(linkedID)
        end
        local retainedInstance
        if not aura and selfAuraInstances[id] then
            -- An aura already identified out of combat may still be readable by instance.
            local instance = selfAuraInstances[id]
            local previous = seenInstances[instance] or apiCall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instance)
            if readable(previous) and previous then
                local spellID = previous.spellId
                if not readable(spellID) or spellID == id or (linkedID and spellID == linkedID) then
                    aura = previous
                    retainedInstance = instance
                end
            end
        end
        if aura then
            instances[id] = number(aura.auraInstanceID) or retainedInstance
            active[id] = aura
            displayIDs[id] = number(aura.spellId) or linkedID or id
        end
    end
    selfAuraInstances = instances
    local native, nativeFrames = {}, {}
    for item in viewer.itemFramePool:EnumerateActive() do
        if item.layoutIndex and number(item:GetCooldownID()) then
            local id = number(apiCall(item.GetAuraSpellID, item))
            if id and item:IsShown() then native[id] = true end
            nativeFrames[#nativeFrames + 1] = item
        end
    end
    local ids = {}
    for id in pairs(active) do
        if not native[displayIDs[id]] then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local displayed, uniqueIDs = {}, {}
    local container = viewer:GetItemContainerFrame()
    local custom, changed = {}, false
    for _, id in ipairs(ids) do
        local identity = displayIDs[id]
        if not displayed[identity] then
            displayed[identity] = true
            uniqueIDs[#uniqueIDs + 1] = id
        end
    end
    for index, id in ipairs(uniqueIDs) do
        local aura = active[id]
        local icon = selfAuraIcons[index]
        if not icon then
            icon = CreateFrame("Frame", nil, container)
            icon:Hide()
            icon:SetSize(40, 40)
            icon.texture = icon:CreateTexture(nil, "ARTWORK")
            icon.texture:SetAllPoints()
            local mask = icon:CreateMaskTexture()
            mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
            mask:SetAllPoints()
            icon.texture:AddMaskTexture(mask)
            icon.cooldown = CreateFrame("Cooldown", nil, icon)
            icon.cooldown:SetAllPoints()
            icon.cooldown:SetReverse(true)
            icon.cooldown:SetDrawSwipe(true)
            icon.cooldown:SetDrawBling(false)
            icon.cooldown:SetSwipeTexture([[Interface\HUD\UI-HUD-CoolDownManager-Icon-Swipe]], 1, 1, 1, 1)
            icon.cooldown:SetSwipeColor(0, 0, 0, 0.7)
            icon.cooldown:SetCountdownFont("GameFontHighlightOutline")
            local overlay = CreateFrame("Frame", nil, icon.cooldown)
            overlay:SetAllPoints()
            icon.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            icon.count:SetPoint("BOTTOMRIGHT", -2, 2)
            selfAuraIcons[index] = icon
        end
        local scale = viewer.iconScale or 1
        if icon:GetScale() ~= scale then
            icon:SetScale(scale)
            changed = true
        end
        custom[id] = icon
        icon.texture:SetTexture(number(aura.icon) or C_Spell.GetSpellTexture(displayIDs[id]) or 134400)
        icon.cooldown:SetHideCountdownNumbers(viewer.timerShown == false)
        local instanceID = instances[id]
        local stacks = number(aura.applications)
        if stacks then
            icon.count:SetText(stacks > 1 and stacks or "")
        else
            local text = instanceID and apiCall(C_UnitAuras.GetAuraApplicationDisplayCount, "player", instanceID, 2)
            if not readable(text) then
                icon.count:SetText(text)
            else
                icon.count:SetText(text or "")
            end
        end
        local duration = instanceID and apiCall(C_UnitAuras.GetAuraDuration, "player", instanceID)
        if not setDuration(icon.cooldown, duration) then
            local expires, total = number(aura.expirationTime), number(aura.duration)
            if expires and expires > GetTime() and total and total > 0 then
                icon.cooldown:SetCooldown(expires - total, total, number(aura.timeMod) or 1)
            else
                icon.cooldown:Clear()
            end
        end
    end
    for index = #uniqueIDs + 1, #selfAuraIcons do
        if selfAuraIcons[index]:IsShown() then
            selfAuraIcons[index]:Hide()
            changed = true
        end
    end
    local _, positioned = Addon.PlaceSelfAuraFrames(nativeFrames, custom)
    if #selfAuraIcons > 0 then
        local stride = viewer:GetStride() + #uniqueIDs
        if container.stride ~= stride then
            container.stride = stride
            changed = true
        end
        if changed or positioned then container:Layout() end
    end
end

function Addon.SetSelfAura(id, enabled)
    if type(id) ~= "number" or id < 1 or id % 1 ~= 0 or id > 2147483647 then return false end
    if enabled and not C_Spell.GetSpellInfo(id) then return false end
    db.auras.selfAuras[id] = enabled and true or nil
    if not enabled then
        db.auras.selfAuraPositions[id] = nil
        tDeleteItem(db.auras.selfAuraOrder, id)
    end
    refreshSelfAuras()
    Addon.UpdateChoices()
    return true
end

function Addon.MoveSelfAura(id, anchor, before, neighbor)
    local order, positions = db.auras.selfAuraOrder, db.auras.selfAuraPositions
    if not db.auras.selfAuras[id] or id == neighbor then return end
    tDeleteItem(order, id)
    if neighbor then
        local position = positions[neighbor]
        positions[id] = position and { anchor = position.anchor, before = position.before }
        local index = tIndexOf(order, neighbor)
        if not index then
            order[#order + 1] = neighbor
            index = #order
        end
        table.insert(order, before and index or index + 1, id)
    else
        positions[id] = { anchor = anchor, before = before }
        order[#order + 1] = id
    end
    refreshSelfAuras()
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

local function isAuraMissing(id)
    if activeBuffs[id] then return false end
    if not buffListComplete then return nil end
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local restricted = apiCall(C_Secrets.ShouldSpellAuraBeSecret, id)
        if not readable(restricted) or restricted ~= false then return nil end
    end
    return true
end

local function missingForOverride(id, override)
    local missing = isAuraMissing(id)
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
        local name, icon = spellMetadata(spellID)
        entries[#entries + 1] = { id = spellID, name = name, icon = icon }
    end
    local override = Addon.GetIconOverride("auras", id)
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

local viewerHooks, itemHooks = {}, {}
local spellTimers = setmetatable({}, { __mode = "k" })
local filteredItems = setmetatable({}, { __mode = "k" })

local function restoreNativeTimer(timer, item)
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
    local timer = spellTimers[item]
    local nativeCooldown = key == "cooldowns" and id and not viewer:IsEditing() and item:GetCooldownFrame()
    -- Fill in a missing native combat timer without replacing a countdown Blizzard is already displaying.
    local fallback = nativeCooldown and not rank and InCombatLockdown()
        and number(apiCall(nativeCooldown.GetCooldownDuration, nativeCooldown)) == 0
    if timer and timer.nativeCooldown and not rank then restoreNativeTimer(timer, item) end
    if nativeCooldown and (rank or fallback) then
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
            cooldown:SetScript("OnCooldownDone", function() restoreNativeTimer(timer, item) end)
            spellTimers[item] = timer
        end
        timer.cooldown:SetHideCountdownNumbers(nativeCooldown:GetHideCountdownNumbers())
        timer.cooldown:SetCountdownFormatter(nativeCooldown:GetCountdownFormatter())
        timer.cooldown:SetCountdownAbbrevThreshold(nativeCooldown:GetCountdownAbbrevThreshold())
        timer.cooldown:SetCountdownMillisecondsThreshold(nativeCooldown:GetCountdownMillisecondsThreshold())
        timer.cooldown:SetMinimumCountdownDuration(nativeCooldown:GetMinimumCountdownDuration())
        local applied, desaturated = updateSpellTimer(timer, rank and rank.id or id, rank and rank.slot, rank and rank.lowerRank)
        if applied then
            if rank and not timer.nativeCooldown then
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
            timer.countFrame:SetShown(not not rank)
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
            show = missingForOverride(override.auraID or id, override)
            local activeID = number(apiCall(item.GetAuraSpellID, item))
            if activeID and activeBuffs[activeID] then show = false end
        end
        filteredItems[item] = true
        item:SetShown(show == true)
    elseif filteredItems[item] then
        filteredItems[item] = nil
        local shown = apiCall(item.ShouldBeShown, item)
        if readable(shown) and type(shown) == "boolean" then item:SetShown(shown) end
    end
end

local dividerFrames = {}

local function refreshDividers(viewer)
    local selected = db.cooldowns.dividers
    local frames = dividerFrames[viewer]
    if not frames and not next(selected) then return end

    local items = {}
    for item in viewer.itemFramePool:EnumerateActive() do
        local id = number(item:GetCooldownID())
        if id and item.layoutIndex then
            items[item.layoutIndex] = item
        end
    end

    local container = viewer:GetItemContainerFrame()
    local horizontal = container.isHorizontal
    local forward = (horizontal and container.layoutFramesGoingRight) or (not horizontal and container.layoutFramesGoingUp)
    local stride = container.stride or 1
    local padding = (horizontal and container.childXPadding or container.childYPadding) or 0
    local side = horizontal and (forward and "RIGHT" or "LEFT") or (forward and "TOP" or "BOTTOM")
    frames = frames or {}
    dividerFrames[viewer] = frames
    local used = 0
    for index, item in pairs(items) do
        if items[index + 1] and index % stride ~= 0 and selected[number(item:GetCooldownID())] then
            used = used + 1
            local frame = frames[used]
            if not frame then
                frame = CreateFrame("Frame", nil, container)
                frame.ignoreInLayout = true
                frame:Hide()
                local shadow = frame:CreateTexture(nil, "ARTWORK")
                shadow:SetPoint("CENTER")
                shadow:SetColorTexture(0, 0, 0, 0.85)
                local line = frame:CreateTexture(nil, "OVERLAY")
                line:SetPoint("CENTER")
                line:SetColorTexture(0.85, 0.85, 0.85, 0.85)
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
    end
end

function Addon.HasDivider(id)
    return db and db.cooldowns.dividers[id]
end

function Addon.SetDivider(id, enabled)
    db.cooldowns.dividers[id] = enabled and true or nil
    for _, name in ipairs(viewerNames.cooldowns) do
        local viewer = _G[name]
        if viewer and viewer.itemFramePool then refreshDividers(viewer) end
    end
end

local function styleViewer(viewer, key)
    if not viewer.itemFramePool then return end
    for item in viewer.itemFramePool:EnumerateActive() do
        if not itemHooks[item] then
            if item.UpdateShownState then
                hooksecurefunc(item, "UpdateShownState", function(self)
                    updateNativeIcon(self, viewer, key)
                end)
            end
            local cooldown = item:GetCooldownFrame()
            if cooldown and key == "cooldowns" then
                cooldown:HookScript("OnCooldownDone", function()
                    updateNativeIcon(item, viewer, key)
                end)
            end
            itemHooks[item] = true
        end
        updateNativeIcon(item, viewer, key)
        if key == "cooldowns" then refreshManaGemIcon(item, "RefreshIconDesaturation") end
    end
    if key == "cooldowns" then
        refreshDividers(viewer)
    else
        refreshSelfAuras()
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
                    hooksecurefunc(viewer, "RefreshData", refreshViewer)
                    hooksecurefunc(viewer, "SetTimerShown", refreshViewer)
                    hooksecurefunc(viewer, "SetIsEditing", refreshViewer)
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
            label:Show()
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
    attachBarStacks()
    Addon.UpdateChoices()
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
    if update.auras then
        scanAuras()
        updateNativeIcons("auras")
        refreshSelfAuras()
    end
    if update.blizzard then
        styleBlizzardViewers()
        attachBarStacks()
        Addon.AttachOptions()
    end
    if update.blizzard or update.bags then refreshManaGemAvailability() end
    if (update.catalog or update.auras) and Addon.UpdateChoices then Addon.UpdateChoices() end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("BAG_UPDATE_DELAYED")
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
        db.cooldowns = { overrides = db.cooldowns.overrides, dividers = db.cooldowns.dividers }
        db.auras = {
            overrides = db.auras.overrides, selfAuras = db.auras.selfAuras,
            discoveredDebuffs = db.auras.discoveredDebuffs,
            selfAuraOrder = db.auras.selfAuraOrder, selfAuraPositions = db.auras.selfAuraPositions,
        }
        for id, override in pairs(db.cooldowns.overrides) do
            if type(override) == "table" and (override.rankID or override.visibility == "ready") then
                db.cooldowns.overrides[id] = {
                    rankID = override.rankID,
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
        return
    end
    if not db then return end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        pending.catalog, pending.auras, pending.blizzard = true, true, true
    elseif event == "ADDON_LOADED" and name == "Blizzard_CooldownViewer" then
        pending.blizzard = true
    elseif catalogEvents[event] then
        pending.catalog = true
    elseif event == "BAG_UPDATE_DELAYED" then
        pending.bags = true
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
