local _, Addon = ...
local picker
local openPicker
local attached
local pageSize = 8

local function change(section, key, value)
    Addon.GetSettings(section)[key] = value
    Addon.ApplySettings()
end

local function addToggle(menu, text, section, key)
    menu:CreateCheckbox(text, function()
        return Addon.GetSettings(section)[key]
    end, function()
        change(section, key, not Addon.GetSettings(section)[key])
    end)
end

local function addChoices(menu, title, section, key, choices)
    local submenu = menu:CreateButton(title)
    for _, choice in ipairs(choices) do
        submenu:CreateRadio(choice[1], function()
            return Addon.GetSettings(section)[key] == choice[2]
        end, function()
            change(section, key, choice[2])
        end)
    end
end

local function chooseColor(section)
    if not ColorPickerFrame and C_AddOns then C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame") end
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then return end
    local color = Addon.GetSettings(section).color
    local function component(start) return (tonumber(color:sub(start, start + 1), 16) or 255) / 255 end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = component(1), g = component(3), b = component(5), hasOpacity = false,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            change(section, "color", ("%02x%02x%02x"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5))
        end,
        cancelFunc = function() change(section, "color", color) end,
    })
end

local function displayMenu(menu, section)
    addToggle(menu, "Style Blizzard icons", section, "styleBlizzard")
    addToggle(menu, "Countdown numbers", section, "numbers")
    addToggle(menu, "Radial swipe", section, "swipe")
    addToggle(menu, section == "auras" and "Show stacks" or "Show charges", section, "stacks")
    if section == "cooldowns" then
        addToggle(menu, "Ignore global cooldown on selected ranks", section, "ignoreGCD")
    end
    menu:CreateDivider()
    menu:CreateButton("Countdown color…", function() chooseColor(section) end)
    addChoices(menu, "Countdown size", section, "fontSize", { {"Small", 12}, {"Medium", 17}, {"Large", 22}, {"Extra large", 28} })
    addChoices(menu, "Countdown decimals", section, "decimals", { {"Off", 0}, {"Under 3 seconds", 3}, {"Under 5 seconds", 5}, {"Under 10 seconds", 10} })
    if section == "auras" then
        local layout = menu:CreateButton("Added icon layout")
        addChoices(layout, "Size", section, "size", { {"28", 28}, {"38", 38}, {"48", 48}, {"60", 60} })
        addChoices(layout, "Spacing", section, "gap", { {"Tight", 2}, {"Normal", 4}, {"Wide", 8} })
        addChoices(layout, "Icons per row", section, "columns", { {"6", 6}, {"8", 8}, {"12", 12}, {"16", 16} })
        addChoices(layout, "Alignment", section, "alignment", { {"Left", "LEFT"}, {"Center", "CENTER"}, {"Right", "RIGHT"} })
    end
end

local function missingToggle(menu, id, auraID)
    local function checked()
        local override = Addon.GetIconOverride("auras", id, "HELPFUL")
        return override and override.visibility == "missing"
    end
    menu:CreateCheckbox("Show only when missing", checked, function()
        Addon.SetMissingReminder(id, auraID, not checked())
    end)
    menu:CreateButton("Choose alternative buffs…", function()
        openPicker("alternatives", "HELPFUL", id, auraID)
    end)
end

local function iconMenu(menu, section, id, filter)
    for _, field in ipairs({ {"Countdown numbers", "numbers"}, {"Radial swipe", "swipe"} }) do
        local key = field[2]
        local submenu = menu:CreateButton(field[1])
        for _, choice in ipairs({ {"Use display setting"}, {"Show", true}, {"Hide", false} }) do
            local value = choice[2]
            submenu:CreateRadio(choice[1], function()
                local override = Addon.GetIconOverride(section, id, filter)
                if override then return override[key] == value end
                return value == nil
            end, function()
                Addon.SetIconOverride(section, id, filter, key, value)
            end)
        end
    end
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
    local section, filter = picker.section, picker.filter
    local settings = Addon.GetSettings(section == "range" and "cooldowns" or "auras")
    local query = picker.search:GetText():lower():match("^%s*(.-)%s*$")
    local entries = {}
    local alternatives
    if section == "range" then
        for _, spell in ipairs(Addon.GetRangeChoices()) do
            if not picker.trackedOnly or settings.rangeSpells[spell.id] then entries[#entries + 1] = spell end
        end
    elseif section == "alternatives" then
        entries = Addon.GetBuffAlternatives(picker.reminderID, picker.auraID, picker.trackedOnly)
        local override = Addon.GetIconOverride("auras", picker.reminderID, "HELPFUL")
        alternatives = override and override.alternatives or {}
    elseif picker.trackedOnly then
        for _, pin in ipairs(settings.entries) do
            if pin.filter == filter then entries[#entries + 1] = Addon.GetEntryDetails(section, pin.id) end
        end
    else
        entries = Addon.GetAuraChoices(filter)
    end
    local matches = {}
    for _, entry in ipairs(entries) do
        local name = entry.name
        if entry.rank and entry.rank ~= "" then name = name .. " (" .. entry.rank .. ")" end
        if entry.level and entry.level > 0 then name = name .. " · Lv. " .. entry.level end
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
            local tracked
            if section == "range" then
                tracked = settings.rangeSpells[entry.id]
            elseif alternatives then
                tracked = alternatives[entry.id]
            else
                tracked = Addon.FindPin(section, entry.id, filter)
            end
            row.mark:SetText(tracked and "✓" or "")
        end
    end
    picker.empty:SetText(section == "alternatives" and not picker.trackedOnly and "No matching buffs in Not Displayed" or "No matching entries")
    picker.empty:SetShown(#matches == 0)
    picker.pageText:SetText(("%d / %d"):format(picker.page, pages))
    picker.previous:SetEnabled(picker.page > 1)
    picker.next:SetEnabled(picker.page < pages)
end

Addon.UpdateOptions = Addon.UpdateChoices

local function addAuraID()
    local id = tonumber(picker.search:GetText():match("^%s*(%d+)%s*$"))
    if not id or id < 1 or id > 2147483647 or not C_Spell.GetSpellInfo(id) then
        picker.status:SetText("Enter the effect's aura spell ID.")
        return
    end
    Addon.Pin(picker.section, id, picker.filter)
    picker.search:SetText("")
    picker.status:SetText("Aura added. View it under Tracked.")
end

local function movePin(section, id, filter, offset)
    local index = Addon.FindPin(section, id, filter)
    if not index then return end
    local entries = Addon.GetSettings(section).entries
    local target = index + offset
    while entries[target] and entries[target].filter ~= filter do target = target + offset end
    if not entries[target] then return end
    entries[index], entries[target] = entries[target], entries[index]
    Addon.ApplySettings()
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
        picker.status:SetText("")
        Addon.UpdateChoices()
    end)
    picker.search:SetScript("OnEnterPressed", function(self)
        if picker.section == "auras" then addAuraID() end
        self:ClearFocus()
    end)
    picker.mode = button(picker, "Tracked", 90, function(self)
        picker.trackedOnly = not picker.trackedOnly
        picker.page = 1
        if picker.section == "alternatives" then
            self:SetText(picker.trackedOnly and "Not Displayed" or "Selected")
        else
            self:SetText(picker.trackedOnly and "Browse" or "Tracked")
        end
        Addon.UpdateChoices()
    end)
    picker.mode:SetPoint("TOPRIGHT", -14, -32)
    picker.rows = {}
    for index = 1, pageSize do
        local row = CreateFrame("Button", nil, picker)
        row:SetSize(316, 27)
        row:SetPoint("TOPLEFT", 15, -65 - (index - 1) * 27)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
        row:SetScript("OnClick", function(self, mouseButton)
            if not self.entry then return end
            local id = self.entry.id
            local section, filter = picker.section, picker.filter
            if section == "alternatives" then
                if mouseButton == "LeftButton" then
                    local override = Addon.GetIconOverride("auras", picker.reminderID, "HELPFUL")
                    local selected = override and override.alternatives and override.alternatives[id]
                    Addon.SetBuffAlternative(picker.reminderID, picker.auraID, id, not selected)
                end
                return
            end
            if section == "range" then
                if mouseButton == "LeftButton" then
                    local settings = Addon.GetSettings("cooldowns")
                    settings.rangeSpells[id] = not settings.rangeSpells[id] or nil
                    Addon.ApplySettings()
                    Addon.RefreshCategoryButtons()
                end
                return
            end
            if mouseButton == "RightButton" then
                MenuUtil.CreateContextMenu(self, function(_, root)
                    local menu = root:CreateButton("Better CDM")
                    if filter == "HELPFUL" then missingToggle(menu, id, id) end
                    iconMenu(menu, section, id, filter)
                    if Addon.FindPin(section, id, filter) then
                        menu:CreateDivider()
                        menu:CreateButton("Move earlier", function() movePin(section, id, filter, -1) end)
                        menu:CreateButton("Move later", function() movePin(section, id, filter, 1) end)
                    end
                end)
                return
            end
            local pin = Addon.FindPin(section, id, filter)
            if pin then
                table.remove(Addon.GetSettings(section).entries, pin)
                Addon.ApplySettings()
            else
                Addon.Pin(section, id, filter)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.entry.id)
            local hint = picker.section == "alternatives" and "Left-click to toggle this alternative"
                or picker.section == "range" and "Left-click to toggle range tracking"
                or "Left-click to track · Right-click for display"
            GameTooltip:AddLine(hint, 0.8, 0.8, 0.8)
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
    picker.addID = button(picker, "Add aura ID", 103, addAuraID)
    picker.addID:SetPoint("TOPRIGHT", -14, -290)
    picker.status = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    picker.status:SetPoint("BOTTOMLEFT", 16, 27)
    local hint = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 12)
    picker.hint = hint
end

openPicker = function(section, filter, reminderID, auraID)
    if not CooldownViewerSettings:IsVisible() then return end
    if not picker then makePicker(CooldownViewerSettings) end
    picker.section, picker.filter = section, filter
    picker.reminderID, picker.auraID = reminderID, auraID
    picker.trackedOnly, picker.page = false, 1
    picker.mode:SetText(section == "alternatives" and "Selected" or "Tracked")
    local title = section == "alternatives" and "Alternative buffs"
        or section == "range" and "Essential range abilities"
        or filter == "HELPFUL" and "Add self buffs" or "Add self debuffs"
    picker.TitleText:SetText(title)
    picker.addID:SetShown(section == "auras")
    local hint = section == "alternatives" and "Pick a buff from Not Displayed to suppress this reminder."
        or section == "range" and "Click to toggle an Essential range icon."
        or "Click to toggle tracking. Right-click for display."
    picker.hint:SetText(hint)
    picker.search:SetText("")
    picker.status:SetText("")
    picker:Show()
    Addon.UpdateChoices()
end

local function toggleConjuredItem(family)
    local items = Addon.GetSettings("cooldowns").items
    items[family.name] = not items[family.name] or nil
    Addon.ApplySettings()
    Addon.RefreshCategoryButtons()
end

local function settingsMenu(_, root)
    root:CreateDivider()
    displayMenu(root:CreateButton("Cooldown icon display"), "cooldowns")
    root:CreateButton("Add Essential range abilities…", function() openPicker("range") end)
    local conjured = root:CreateButton("Conjured items")
    for _, family in ipairs(Addon.GetConjuredItems()) do
        conjured:CreateCheckbox(family.name, function()
            return Addon.GetSettings("cooldowns").items[family.name] == true
        end, function() toggleConjuredItem(family) end)
    end
    local auras = root:CreateButton("Self auras")
    auras:CreateButton("Add self buffs…", function() openPicker("auras", "HELPFUL") end)
    auras:CreateButton("Add self debuffs…", function() openPicker("auras", "HARMFUL") end)
    displayMenu(auras:CreateButton("Aura icon display"), "auras")
    addToggle(auras, "Stacks on tracked bar icons", "auras", "barStacks")
end

local categoryButtons = setmetatable({}, { __mode = "k" })

local function updateCategoryButtons(manager)
    local categories = Enum.CooldownViewerCategory
    for display in manager.categoryPool:EnumerateActive() do
        local categoryObject = display:GetCategoryObject()
        local category = categoryObject:GetCategory()
        -- The Items group reports EquipSlotEssential as its primary category.
        local isItems = categoryObject:MatchesCategory(categories.SpecAgnosticEssential)
        local buttons = categoryButtons[display]
        if isItems or category == categories.Essential or buttons then
            buttons = buttons or {}
            categoryButtons[display] = buttons
            local count = 0
            local function add(label, texture, action, selected)
                count = count + 1
                local icon = buttons[count]
                if not icon then
                    icon = CreateFrame("Button", nil, display.Container)
                    icon:SetSize(36, 36)
                    icon.layoutIndex = 100000 + count
                    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
                    icon:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(self.tooltip)
                        GameTooltip:Show()
                    end)
                    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    buttons[count] = icon
                end
                icon.tooltip = label
                icon:SetNormalTexture(texture)
                icon:GetNormalTexture():SetDesaturated(selected == false)
                icon:SetScript("OnClick", action)
                icon:Show()
            end
            if isItems then
                for _, family in ipairs(Addon.GetConjuredItems()) do
                    local id = Addon.GetConjuredItem(family)
                    local items = Addon.GetSettings("cooldowns").items
                    local itemName = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
                    local label = itemName and itemName ~= family.name and (family.name .. " (" .. itemName .. ")") or family.name
                    add(label .. " — click to toggle tracking", C_Item.GetItemIconByID(id) or 134400,
                        function() toggleConjuredItem(family) end, items[family.name] == true)
                end
            elseif category == categories.Essential then
                add("Add Essential range abilities", 136243, function() openPicker("range") end, true)
                local selected = Addon.GetSettings("cooldowns").rangeSpells
                for _, spell in ipairs(Addon.GetRangeChoices()) do
                    if selected[spell.id] then
                        add(spell.name .. " — click to remove range tracking", spell.icon, function()
                            selected[spell.id] = nil
                            Addon.ApplySettings()
                            updateCategoryButtons(manager)
                        end, true)
                    end
                end
            end
            for index = count + 1, #buttons do buttons[index]:Hide() end
            display.Container:Layout()
            display:Layout()
        end
    end
end

function Addon.RefreshCategoryButtons()
    local manager = CooldownViewerSettings
    if manager and manager:IsVisible() and manager.categoryPool then updateCategoryButtons(manager) end
end

local function itemMenu(owner, root)
    local category = owner:GetCategory()
    if issecretvalue and issecretvalue(category) then return end
    if category == nil then return end
    local categories = Enum.CooldownViewerCategory
    local aura = category == categories.TrackedBuff or category == categories.HiddenPassive
    local spell = category == categories.Essential or category == categories.Utility or category == categories.HiddenActive
    if not aura and not spell then return end
    local id = owner:GetBaseSpellID()
    if (not issecretvalue or not issecretvalue(id)) and id == nil then id = owner:GetSpellID() end
    if issecretvalue and issecretvalue(id) then return end
    if type(id) ~= "number" then return end
    root:CreateDivider()
    local menu = root:CreateButton("Better CDM")
    local section, filter = aura and "auras" or "cooldowns", aura and "HELPFUL" or nil
    local displayID = owner:GetSpellID()
    if issecretvalue and issecretvalue(displayID) then displayID = nil end
    local function current(key)
        local override = Addon.GetIconOverride(section, id, filter)
        if override then return override[key] end
    end
    local function set(key, value)
        Addon.SetIconOverride(section, id, filter, key, value)
    end
    if spell then
        local ranks = Addon.GetRanks(id, displayID)
        if #ranks > 1 then
            local rank = menu:CreateButton("Rank")
            rank:CreateRadio("Default", function() return current("rankID") == nil end, function()
                set("rankID", nil)
            end)
            for _, entry in ipairs(ranks) do
                rank:CreateRadio(entry.rank, function() return current("rankID") == entry.id end, function()
                    set("rankID", entry.id)
                end)
            end
        end
        menu:CreateCheckbox("Show only when ready", function() return current("visibility") == "ready" end, function()
            local mode = current("visibility") ~= "ready" and "ready" or nil
            set("visibility", mode)
        end)
    elseif displayID then
        missingToggle(menu, id, displayID)
    end
    iconMenu(menu:CreateButton("Icon display"), section, id, filter)
    if aura then
        if type(displayID) == "number" then
            menu:CreateButton("Track on yourself…", function()
                openPicker("auras", "HELPFUL")
                if picker and picker:IsVisible() then picker.search:SetText(tostring(displayID)) end
            end)
        end
    end
end

function Addon.AttachOptions()
    if attached or not Menu or not Menu.ModifyMenu then return end
    attached = true
    Menu.ModifyMenu("COOLDOWN_VIEWER_SETTINGS_MENU", settingsMenu)
    Menu.ModifyMenu("MENU_COOLDOWN_SETTINGS_ITEM", itemMenu)
    local manager = CooldownViewerSettings
    if manager and manager.categoryPool then
        hooksecurefunc(manager, "ClearDisplayCategories", function()
            for _, buttons in pairs(categoryButtons) do
                for _, icon in ipairs(buttons) do icon:Hide() end
            end
        end)
        hooksecurefunc(manager, "RefreshLayout", updateCategoryButtons)
        if manager:IsVisible() then updateCategoryButtons(manager) end
    end
end

function Addon.ShowOptions()
    Addon.AttachOptions()
    if CooldownViewerSettings and not InCombatLockdown() and not CooldownViewerSettings:IsVisible() then
        CooldownViewerSettings:ShowUIPanel()
    end
end
