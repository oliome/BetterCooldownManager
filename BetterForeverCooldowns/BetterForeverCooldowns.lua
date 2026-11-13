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

local defaults = { cooldowns = { overrides = {}, dividers = {} }, auras = { overrides = {} } }

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

local function setSpellTimerFromNumbers(cooldown, info)
    if not readable(info) or not info then return false end
    local start, duration = number(info.startTime), number(info.duration)
    if not start or start <= 0 or not duration or duration <= 0 then return false end
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

local function updateSpellTimer(icon)
    local spell = icon.entry
    local book = C_SpellBook
    local bank = Enum.SpellBookSpellBank.Player
    local id = spell.id
    if not spell.lowerRank then
        local overrideID = number(apiCall(C_Spell.GetOverrideSpell, id))
        if overrideID and overrideID > 0 then id = overrideID end
    end
    local charges
    if spell.slot then charges = apiCall(book.GetSpellBookItemCharges, spell.slot, bank) end
    if readable(charges) and not charges then charges = apiCall(C_Spell.GetSpellCharges, id) end
    local current, maximum
    if readable(charges) and charges then
        current = number(charges.currentCharges)
        maximum = number(charges.maxCharges)
    end
    icon.count:SetText(current or "")

    local duration
    local recharging = current and maximum and current < maximum
    if recharging then
        if spell.slot then duration = apiCall(book.GetSpellBookItemChargeDuration, spell.slot, bank) end
        if readable(duration) and not duration then duration = apiCall(C_Spell.GetSpellChargeDuration, id) end
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
    if spell.slot then
        duration = apiCall(book.GetSpellBookItemCooldownDuration, spell.slot, bank, true)
        if setDuration(cooldown, duration) then return end
    end
    duration = apiCall(C_Spell.GetSpellCooldownDuration, id, true)
    if setDuration(cooldown, duration) then return end
    local info
    if spell.slot then info = apiCall(book.GetSpellBookItemCooldown, spell.slot, bank) end
    if not readable(info) or not info then info = apiCall(C_Spell.GetSpellCooldown, id) end
    if not setSpellTimerFromNumbers(cooldown, info) then cooldown:Clear() end
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

local function updateNativeIcon(item, viewer, key)
    local baseID = number(apiCall(item.GetBaseSpellID, item))
    local id = number(apiCall(item.GetSpellID, item)) or baseID
    local override = id and not viewer:IsEditing() and (Addon.GetIconOverride(key, baseID or id) or Addon.GetIconOverride(key, id))
    local rank = override and spellsByID[override.rankID]
    local timer = spellTimers[item]
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
            spellTimers[item] = timer
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
        timer.cooldown:SetHideCountdownNumbers(not viewer.timerShown)
        timer.cooldown:SetDrawSwipe(true)
        updateSpellTimer(timer)
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

    local anchors, lastIndex = {}, 0
    for item in viewer.itemFramePool:EnumerateActive() do
        local id = number(item:GetCooldownID())
        if id and item.layoutIndex then
            lastIndex = math.max(lastIndex, item.layoutIndex)
            if selected[id] then anchors[item.layoutIndex] = item end
        end
    end

    local container = viewer:GetItemContainerFrame()
    local horizontal = container.isHorizontal
    frames = frames or {}
    dividerFrames[viewer] = frames
    local used, changed = 0, false
    for index = 1, lastIndex - 1 do
        local item = anchors[index]
        if item then
            used = used + 1
            local frame = frames[used]
            if not frame then
                frame = CreateFrame("Frame", nil, container)
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
            local slotWidth, slotHeight = horizontal and 22 or width, horizontal and height or 22
            if frame:GetWidth() ~= slotWidth or frame:GetHeight() ~= slotHeight or frame:GetScale() ~= scale then
                frame:SetSize(slotWidth, slotHeight)
                frame:SetScale(scale)
                changed = true
            end
            local lineWidth, lineHeight = horizontal and 2 or width * 0.65, horizontal and height * 0.65 or 2
            frame.line:SetSize(lineWidth, lineHeight)
            frame.shadow:SetSize(lineWidth + 2, lineHeight + 2)

            -- Native item indices are used to look up cooldown IDs. Leave them intact.
            local layoutIndex = index + 0.5
            if frame.layoutIndex ~= layoutIndex or not frame:IsShown() then
                frame.layoutIndex = layoutIndex
                frame:Show()
                changed = true
            end
        end
    end

    for index = used + 1, #frames do
        if frames[index]:IsShown() then
            frames[index]:Hide()
            changed = true
        end
    end
    if changed then container:Layout() end
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
            if cooldown then
                cooldown:HookScript("OnCooldownDone", function()
                    updateNativeIcon(item, viewer, key)
                end)
            end
            itemHooks[item] = true
        end
        updateNativeIcon(item, viewer, key)
        if key == "cooldowns" then refreshManaGemIcon(item, "RefreshIconDesaturation") end
    end
    if key == "cooldowns" then refreshDividers(viewer) end
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
        db.auras = { overrides = db.auras.overrides }
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
