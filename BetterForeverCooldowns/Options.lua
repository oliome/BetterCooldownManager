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
    local entries = Addon.GetBuffAlternatives(picker.reminderID, picker.auraID, picker.selectedOnly)
    local override = Addon.GetIconOverride("auras", picker.reminderID)
    local selected = override and override.alternatives or {}
    local matches = {}
    for _, entry in ipairs(entries) do
        local name = entry.name
        if (name .. " " .. entry.id):lower():find(query, 1, true) then
            matches[#matches + 1] = { id = entry.id, icon = entry.icon, text = name }
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
    picker.empty:SetText(not picker.selectedOnly and "No matching buffs in Not Displayed" or "No matching entries")
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
        self:SetText(picker.selectedOnly and "Not Displayed" or "Selected")
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
end

openPicker = function(reminderID, auraID)
    if not CooldownViewerSettings:IsVisible() then return end
    if not picker then makePicker(CooldownViewerSettings) end
    picker.reminderID, picker.auraID = reminderID, auraID
    picker.selectedOnly, picker.page = false, 1
    picker.mode:SetText("Selected")
    picker.TitleText:SetText("Alternative buffs")
    picker.hint:SetText("Pick a buff from Not Displayed to suppress this reminder.")
    picker.search:SetText("")
    picker:Show()
    Addon.UpdateChoices()
end

local trackedDisplays = {}
local customRows = {}

local refreshTrackedEntries
local cooldownSections = { { "Essential", "essential" }, { "Utility", "utility" }, { "Items", "items" } }
local dragPreview

local function positionDragPreview(frame)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

local function stopDragPreview(row)
    if not dragPreview or dragPreview.source ~= row then return end
    dragPreview.source = nil
    dragPreview:SetScript("OnUpdate", nil)
    dragPreview:Hide()
    row:SetAlpha(1)
    row.dragging = nil
end

local function showDragPreview(row)
    if not dragPreview then
        dragPreview = CreateFrame("Frame", nil, UIParent)
        dragPreview:SetFrameStrata("TOOLTIP")
        dragPreview:EnableMouse(false)
        dragPreview.icon = dragPreview:CreateTexture(nil, "ARTWORK")
        dragPreview.icon:SetAllPoints()
        local border = dragPreview:CreateTexture(nil, "OVERLAY")
        border:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
        border:SetPoint("TOPLEFT", -6, 5)
        border:SetPoint("BOTTOMRIGHT", 6, -5)
    end
    if dragPreview.source then stopDragPreview(dragPreview.source) end
    local width, height = row:GetSize()
    local scale = row:GetEffectiveScale() / UIParent:GetEffectiveScale()
    dragPreview:SetSize(width * scale, height * scale)
    dragPreview.icon:SetTexture(row.icon:GetTexture())
    dragPreview.source = row
    row.dragging = true
    row:SetAlpha(0.45)
    positionDragPreview(dragPreview)
    dragPreview:SetScript("OnUpdate", positionDragPreview)
    dragPreview:Show()
end

local function canDropEntry(destination, isItem)
    return destination == "essential" or destination == "utility" or (destination == "items" and isItem)
end

local function clearTrackedEntries()
    for display in pairs(trackedDisplays) do display.Container.betterCDMOrder = nil end
    wipe(trackedDisplays)
    for _, rows in pairs(customRows) do
        for _, row in ipairs(rows) do
            row.layoutIndex = nil
            row:Hide()
        end
    end
end

local function addTrackedEntry(id, section, target)
    if not id or id < 1 or id > 2147483647 or id % 1 ~= 0 then return false end
    local manager = CooldownViewerSettings
    local categories = Enum.CooldownViewerCategory
    local provider = manager:GetDataProvider()
    if section == "items" then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        Addon.SetCustomCooldown(id, true, section)
        return true
    end
    local sources = { target, categories.HiddenActive, target == categories.Essential and categories.Utility or categories.Essential }
    for _, category in ipairs(sources) do
        for _, cooldownID in ipairs(provider:GetOrderedCooldownIDsForCategory(category)) do
            local info = provider:GetCooldownInfoForID(cooldownID)
            if info and (info.spellID == id or info.overrideSpellID == id
                or (info.linkedSpellIDs and tContains(info.linkedSpellIDs, id))) then
                if category ~= target then
                    local status = provider:SetCooldownToCategory(cooldownID, target)
                    manager:CheckDisplayActionStatus(Enum.CooldownLayoutAction.ChangeCategory, status)
                    if status ~= Enum.CooldownLayoutStatus.Success then return false end
                end
                Addon.SetCustomCooldown(id, false, nil)
                manager:RefreshLayout()
                return true
            end
        end
    end
    Addon.SetCustomCooldown(id, false, section)
    return true
end

local function createTrackedRow(container)
    local row = CreateFrame("Button", nil, container)
    row:RegisterForClicks("RightButtonUp")
    row:RegisterForDrag("LeftButton")
    row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints()
    row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    row.count:SetPoint("BOTTOMRIGHT", -3, 3)
    row.border = row:CreateTexture(nil, "OVERLAY")
    row.border:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
    row.border:SetPoint("TOPLEFT", -6, 5)
    row.border:SetPoint("BOTTOMRIGHT", 6, -5)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.isItem then
            GameTooltip:SetItemByID(self.entryID)
        else
            GameTooltip:SetSpellByID(self.entryID)
        end
        GameTooltip:AddLine("Drag to reorder or move to another section. Right-click for options.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local id, section, isItem = self.entryID, self.section, self.isItem
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Better CDM")
            if isItem then
                local appearance = root:CreateButton("Icon")
                for _, choice in ipairs({ { "Item artwork" }, { "Engineering", "engineering" }, { "Potion", "potion" } }) do
                    local style = choice[2]
                    appearance:CreateRadio(choice[1], function() return Addon.GetItemIconStyle(id) == style end, function()
                        Addon.SetItemIconStyle(id, style)
                        refreshTrackedEntries()
                    end)
                end
            end
            for _, destination in ipairs(cooldownSections) do
                local label, target = destination[1], destination[2]
                if target ~= section and canDropEntry(target, isItem) then
                    root:CreateButton("Move to " .. label, function()
                        Addon.SetCustomCooldown(id, isItem, target)
                        refreshTrackedEntries()
                    end)
                end
            end
            root:CreateButton("Remove", function()
                Addon.SetCustomCooldown(id, isItem, nil)
                refreshTrackedEntries()
            end)
        end)
    end)
    row:SetScript("OnDragStart", function(self)
        if CooldownViewerSettings:GetReorderSourceItem() then return end
        GameTooltip:Hide()
        showDragPreview(self)
    end)
    row:SetScript("OnHide", stopDragPreview)
    row:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        stopDragPreview(self)
        local container, destination
        for display, section in pairs(trackedDisplays) do
            if display:IsVisible() and canDropEntry(section, self.isItem) then
                if display.Container:IsVisible() and display.Container:IsMouseOver() then
                    container, destination = display.Container, section
                    break
                elseif display.Header:IsMouseOver() then
                    destination = section
                    break
                end
            end
        end
        if not destination then return end
        local x, y = GetCursorPosition()
        local anchor, before, neighbor
        if container then
            local scale = container:GetEffectiveScale()
            x, y = x / scale, y / scale
            local nearest, distance
            for _, item in ipairs(container.betterCDMOrder or {}) do
                local cx, cy = item:GetCenter()
                if cx and cy then
                    local delta = (cx - x)^2 + (cy - y)^2
                    if not distance or delta < distance then nearest, distance = item, delta end
                end
            end
            if nearest == self then return end
            if nearest then
                neighbor = nearest.betterCDMEntryKey
                anchor = not neighbor and nearest:GetCooldownID() or nil
                before = x < nearest:GetCenter()
            end
        end
        if not container and destination == self.section then return end
        Addon.MoveCustomCooldown(self.betterCDMEntryKey, destination, anchor, before, neighbor)
        refreshTrackedEntries()
    end)
    return row
end

local function refreshTrackedDisplay(display, section)
    local rows = customRows[section] or {}
    customRows[section] = rows
    local container = display.Container
    local native, custom = {}, {}
    local width, height = 48, 48
    for item in display.itemPool:EnumerateActive() do
        width, height = item:GetSize(true)
        if item:GetCooldownID() then native[#native + 1] = item end
    end
    local entries, order, positions = Addon.GetCustomCooldowns(section)
    local query = (CooldownViewerSettings:GetFilterText() or ""):lower()
    for i, entry in ipairs(entries) do
        local row = rows[i]
        if not row then
            row = createTrackedRow(container)
            row:Hide()
            rows[i] = row
        end
        row:SetParent(container)
        row:SetSize(width, height)
        row.entryID, row.isItem, row.section = entry.id, entry.isItem, section
        row.betterCDMEntryKey = entry.key
        row.icon:SetTexture(entry.icon)
        row.icon:SetDesaturated(entry.count == 0)
        row.count:SetText(entry.count or "")
        local matches = (entry.name .. " " .. entry.id):lower():find(query, 1, true)
        row.icon:SetAlpha(matches and 1 or 0.3)
    end
    for i = #entries + 1, #rows do
        rows[i].layoutIndex = nil
        rows[i]:Hide()
    end
    for i, entry in ipairs(entries) do custom[entry.key] = rows[i] end
    container.betterCDMOrder = Addon.PlaceCustomCooldownFrames(native, custom, order, positions)
    container:Layout()
    display:Layout()
end

refreshTrackedEntries = function()
    for display, section in pairs(trackedDisplays) do refreshTrackedDisplay(display, section) end
end

local function attachTrackedControls(manager)
    local categories = Enum.CooldownViewerCategory
    local sections = {
        [categories.Essential] = "essential",
        [categories.Utility] = "utility", [categories.EquipSlotEssential] = "items",
    }
    for display in manager.categoryPool:EnumerateActive() do
        local category = display:GetCategoryObject():GetCategory()
        local section = sections[category]
        local controls = display.betterCDMTrackedControls
        if section then
            trackedDisplays[display] = section
            if not controls then
                controls = CreateFrame("Frame", nil, display.Header)
                controls:SetHeight(22)
                controls:SetPoint("RIGHT", -24, 0)
                controls.ignoreInLayout = true
                display.betterCDMTrackedControls = controls
                local input = CreateFrame("EditBox", nil, controls, "InputBoxTemplate")
                input:SetAutoFocus(false)
                input:SetMaxLetters(120)
                input:SetSize(108, 22)
                input:SetPoint("LEFT", 3, 0)
                local hint = input:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                hint:SetPoint("LEFT", 5, 0)
                controls.hint = hint
                input:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
                input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                local function add()
                    local current = trackedDisplays[display]
                    if not current then return end
                    local query = input:GetText() or ""
                    local id = Addon.ResolveCooldownEntry(query, current == "items")
                    if not addTrackedEntry(id, current, display:GetCategoryObject():GetCategory()) then
                        UIErrorsFrame:AddMessage("Could not add that name or ID.", 1, 0.3, 0.3)
                        return
                    end
                    input:SetText("")
                    input:ClearFocus()
                    refreshTrackedEntries()
                end
                input:SetScript("OnEnterPressed", add)
                local addButton = button(controls, "Add", 43, add)
                addButton:SetPoint("LEFT", input, "RIGHT", 5, 0)
                controls.bags = button(controls, "Bags", 45, function(owner)
                    MenuUtil.CreateContextMenu(owner, function(_, root)
                        root:CreateTitle("Usable bag items")
                        root:SetScrollMode(260)
                        local entries = Addon.GetUsableBagItems()
                        if #entries == 0 then root:CreateTitle("No untracked usable items") end
                        for _, entry in ipairs(entries) do
                            local label = entry.count and ("%s (%d)"):format(entry.name, entry.count) or entry.name
                            root:CreateButton(label, function()
                                addTrackedEntry(entry.id, "items", categories.EquipSlotEssential)
                                refreshTrackedEntries()
                            end)
                        end
                    end)
                end)
                controls.bags:SetPoint("LEFT", addButton, "RIGHT", 4, 0)
                hooksecurefunc(display, "RefreshLayout", function(self)
                    local current = trackedDisplays[self]
                    if current then refreshTrackedDisplay(self, current) end
                end)
                hooksecurefunc(display, "SetCollapsed", function(self, collapsed)
                    local current = trackedDisplays[self]
                    if current and not collapsed then refreshTrackedDisplay(self, current) end
                end)
            end
            controls:SetWidth(section == "items" and 208 or 159)
            controls.bags:SetShown(section == "items")
            controls.hint:SetText(section == "items" and "Item name or ID" or "Spell name or ID")
            refreshTrackedDisplay(display, section)
        end
        if controls then controls:SetShown(section ~= nil) end
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
    local itemData = CreateFrame("Frame")
    itemData:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    itemData:RegisterEvent("BAG_UPDATE_DELAYED")
    itemData:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    itemData:SetScript("OnEvent", function(_, event, _, success)
        if event ~= "GET_ITEM_INFO_RECEIVED" or success then refreshTrackedEntries() end
    end)
    if CooldownViewerSettings and CooldownViewerSettings.categoryPool then
        hooksecurefunc(CooldownViewerSettings, "ClearDisplayCategories", clearTrackedEntries)
        hooksecurefunc(CooldownViewerSettings, "RefreshLayout", attachTrackedControls)
        hooksecurefunc(CooldownViewerSettings, "ApplyFilter", refreshTrackedEntries)
        CooldownViewerSettings:HookScript("OnHide", clearTrackedEntries)
        CooldownViewerSettings:HookScript("OnShow", attachTrackedControls)
        attachTrackedControls(CooldownViewerSettings)
    end
end

function Addon.ShowOptions()
    Addon.AttachOptions()
    if CooldownViewerSettings and not CooldownViewerSettings:IsVisible() then
        CooldownViewerSettings:ShowUIPanel()
    end
end
