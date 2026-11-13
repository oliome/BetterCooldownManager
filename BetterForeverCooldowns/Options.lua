local _, Addon = ...
local picker
local openPicker
local attached
local pageSize = 8

local function missingToggle(menu, id, auraID)
    local function checked()
        local override = Addon.GetIconOverride("auras", id)
        return override and override.visibility == "missing"
    end
    menu:CreateCheckbox("Show only when missing", checked, function()
        Addon.SetMissingReminder(id, auraID, not checked())
    end)
    menu:CreateButton("Choose alternative buffs…", function()
        openPicker(id, auraID)
    end)
end

local function button(parent, text, width, action)
    local frame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    frame:SetSize(width, 22)
    frame:SetText(text)
    frame:SetScript("OnClick", action)
    return frame
end

function Addon.UpdateChoices()
    if not picker or not picker:IsVisible() then return end
    local query = picker.search:GetText():lower():match("^%s*(.-)%s*$")
    local entries, selected
    if picker.selfAuras then
        entries, selected = Addon.GetSelfAuraChoices(picker.selectedOnly)
    else
        entries = Addon.GetBuffAlternatives(picker.reminderID, picker.auraID, picker.selectedOnly)
        local override = Addon.GetIconOverride("auras", picker.reminderID)
        selected = override and override.alternatives or {}
    end
    local matches = {}
    for _, entry in ipairs(entries) do
        local name = entry.name
        if (name .. " " .. entry.id):lower():find(query, 1, true) then
            local label = picker.selfAuras and ("%s (%d)"):format(name, entry.id) or name
            matches[#matches + 1] = { id = entry.id, icon = entry.icon, text = label }
        end
    end
    local pages = math.max(1, math.ceil(#matches / pageSize))
    picker.page = math.min(pages, math.max(1, picker.page))
    for index, row in ipairs(picker.rows) do
        local entry = matches[(picker.page - 1) * pageSize + index]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.icon:SetTexture(entry.icon)
            row.label:SetText(entry.text)
            row.mark:SetText(selected[entry.id] and "✓" or "")
        end
    end
    picker.empty:SetText(not picker.selfAuras and not picker.selectedOnly and "No matching buffs in Not Displayed" or "No matching entries")
    picker.empty:SetShown(#matches == 0)
    picker.pageText:SetText(("%d / %d"):format(picker.page, pages))
    picker.previous:SetEnabled(picker.page > 1)
    picker.next:SetEnabled(picker.page < pages)
end

local function makePicker(manager)
    picker = CreateFrame("Frame", "BetterForeverCooldownsPicker", manager, "BasicFrameTemplateWithInset")
    picker:SetPoint("CENTER")
    picker:SetSize(347, 371)
    picker:SetFrameLevel(manager:GetFrameLevel() + 50)
    picker:EnableMouse(true)
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel", function() end)
    picker:Hide()
    manager:HookScript("OnHide", function() picker:Hide() end)
    hooksecurefunc(manager, "SetDisplayMode", function() picker:Hide() end)
    table.insert(UISpecialFrames, picker:GetName())

    picker.search = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
    picker.search:SetAutoFocus(false)
    picker.search:SetSize(215, 25)
    picker.search:SetPoint("TOPLEFT", 15, -31)
    picker.search:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        picker.page = 1
        Addon.UpdateChoices()
    end)
    picker.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    picker.mode = button(picker, "Selected", 90, function(self)
        picker.selectedOnly = not picker.selectedOnly
        picker.page = 1
        self:SetText(picker.selectedOnly and (picker.selfAuras and "Class debuffs" or "Not Displayed") or "Selected")
        Addon.UpdateChoices()
    end)
    picker.mode:SetPoint("TOPRIGHT", -14, -32)
    picker.rows = {}
    for index = 1, pageSize do
        local row = CreateFrame("Button", nil, picker)
        row:SetSize(316, 27)
        row:SetPoint("TOPLEFT", 15, -65 - (index - 1) * 27)
        row:RegisterForClicks("LeftButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT")
        row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.mark:SetPoint("RIGHT", -6, 0)
        row.mark:SetWidth(16)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
        row.label:SetPoint("RIGHT", row.mark, "LEFT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetMaxLines(1)
        row:SetScript("OnClick", function(self)
            if not self.entry then return end
            local id = self.entry.id
            if picker.selfAuras then
                local _, selected = Addon.GetSelfAuraChoices(true)
                Addon.SetSelfAura(id, not selected[id])
                return
            end
            local override = Addon.GetIconOverride("auras", picker.reminderID)
            local selected = override and override.alternatives and override.alternatives[id]
            Addon.SetBuffAlternative(picker.reminderID, picker.auraID, id, not selected)
        end)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.entry.id)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        picker.rows[index] = row
    end
    picker.empty = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    picker.empty:SetPoint("TOPLEFT", 17, -77)
    picker.empty:SetText("No matching entries")
    picker.previous = button(picker, "<", 32, function()
        picker.page = picker.page - 1
        Addon.UpdateChoices()
    end)
    picker.previous:SetPoint("TOPLEFT", 15, -290)
    picker.next = button(picker, ">", 32, function()
        picker.page = picker.page + 1
        Addon.UpdateChoices()
    end)
    picker.next:SetPoint("LEFT", picker.previous, "RIGHT", 67, 0)
    picker.pageText = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    picker.pageText:SetPoint("LEFT", picker.previous, "RIGHT", 16, 0)
    local hint = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 12)
    picker.hint = hint

    local function addSpellID()
        local id = tonumber(picker.spellID:GetText())
        if not Addon.SetSelfAura(id, true) then
            picker.hint:SetText("Enter a valid aura spell ID.")
            return
        end
        picker.spellID:SetText("")
        picker.spellID:ClearFocus()
        picker.search:SetText("")
        picker.hint:SetText("Added. Shows while the aura is active on you.")
    end
    picker.spellID = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    picker.spellID:SetAutoFocus(false)
    picker.spellID:SetNumeric(true)
    picker.spellID:SetMaxLetters(10)
    picker.spellID:SetSize(101, 22)
    picker.spellID:SetPoint("BOTTOMLEFT", 20, 29)
    picker.spellID:SetScript("OnEnterPressed", addSpellID)
    picker.spellID:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    picker.addID = button(picker, "Add by ID", 91, addSpellID)
    picker.addID:SetPoint("LEFT", picker.spellID, "RIGHT", 7, 0)
end

openPicker = function(reminderID, auraID)
    if not CooldownViewerSettings:IsVisible() then return end
    if not picker then makePicker(CooldownViewerSettings) end
    picker.selfAuras = reminderID == nil
    picker.reminderID, picker.auraID = reminderID, auraID
    picker.selectedOnly, picker.page = false, 1
    picker.mode:SetText("Selected")
    picker.TitleText:SetText(picker.selfAuras and "Tracked self auras" or "Alternative buffs")
    picker.hint:SetText(picker.selfAuras and "Choose a class debuff or enter a buff or debuff ID."
        or "Pick a buff from Not Displayed to suppress this reminder.")
    picker.spellID:SetShown(picker.selfAuras)
    picker.addID:SetShown(picker.selfAuras)
    picker.spellID:SetText("")
    picker.search:SetText("")
    picker:Show()
    Addon.UpdateChoices()
end

local function attachSelfAuraButton(manager)
    for display in manager.categoryPool:EnumerateActive() do
        local tracked = display:GetCategoryObject():GetCategory() == Enum.CooldownViewerCategory.TrackedBuff
        local control = display.betterCDMSelfAuras
        if tracked and not control then
            control = button(display.Header, "Self Auras", 90, function() openPicker() end)
            control:SetPoint("RIGHT", display.Header, "RIGHT", -32, 0)
            control.ignoreInLayout = true
            display.betterCDMSelfAuras = control
        end
        if control then control:SetShown(tracked) end
    end
end

local function itemMenu(owner, root)
    local category = owner:GetCategory()
    if issecretvalue and issecretvalue(category) then return end
    if category == nil then return end
    local categories = Enum.CooldownViewerCategory
    local aura = category == categories.TrackedBuff
    local displayed = category == categories.Essential or category == categories.Utility
    local spell = displayed or category == categories.HiddenActive
    if not aura and not spell then return end
    local cooldownID = spell and owner:GetCooldownID()
    local dividerEnabled = (not issecretvalue or not issecretvalue(cooldownID)) and type(cooldownID) == "number"
    local hasDivider = dividerEnabled and Addon.HasDivider(cooldownID)
    local canSetDivider = dividerEnabled and (displayed or hasDivider)
    local id = owner:GetBaseSpellID()
    if (not issecretvalue or not issecretvalue(id)) and id == nil then id = owner:GetSpellID() end
    local hasSpellID = (not issecretvalue or not issecretvalue(id)) and type(id) == "number"
    if not hasSpellID and not canSetDivider then return end
    local section = aura and "auras" or "cooldowns"
    local displayID = owner:GetSpellID()
    if issecretvalue and issecretvalue(displayID) then displayID = nil end
    if aura and type(displayID) ~= "number" then return end
    root:CreateDivider()
    root:CreateTitle("Better CDM")
    if canSetDivider then
        local label = hasDivider and "Remove divider after this ability" or "Add divider after this ability"
        root:CreateButton(label, function() Addon.SetDivider(cooldownID, not hasDivider) end)
    end
    if not hasSpellID then return end
    local function current(key)
        local override = Addon.GetIconOverride(section, id)
        if override then return override[key] end
    end
    local function set(key, value)
        Addon.SetIconOverride(section, id, key, value)
    end
    if spell then
        local ranks = Addon.GetRanks(id, displayID)
        if #ranks > 1 then
            local rank = root:CreateButton("Rank")
            rank:CreateRadio("Default", function() return current("rankID") == nil end, function()
                set("rankID", nil)
            end)
            for _, entry in ipairs(ranks) do
                rank:CreateRadio(entry.rank, function() return current("rankID") == entry.id end, function()
                    set("rankID", entry.id)
                end)
            end
        end
        root:CreateCheckbox("Show only when ready", function() return current("visibility") == "ready" end, function()
            local mode = current("visibility") ~= "ready" and "ready" or nil
            set("visibility", mode)
        end)
    elseif displayID then
        missingToggle(root, id, displayID)
    end
end

function Addon.AttachOptions()
    if attached or not Menu or not Menu.ModifyMenu then return end
    attached = true
    Menu.ModifyMenu("MENU_COOLDOWN_SETTINGS_ITEM", itemMenu)
    if CooldownViewerSettings and CooldownViewerSettings.categoryPool then
        hooksecurefunc(CooldownViewerSettings, "RefreshLayout", attachSelfAuraButton)
        attachSelfAuraButton(CooldownViewerSettings)
    end
end

function Addon.ShowOptions()
    Addon.AttachOptions()
    if CooldownViewerSettings and not InCombatLockdown() and not CooldownViewerSettings:IsVisible() then
        CooldownViewerSettings:ShowUIPanel()
    end
end
