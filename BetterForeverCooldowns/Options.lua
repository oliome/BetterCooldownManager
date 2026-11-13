local _, Addon = ...
local window, entryButton, syncing
local section, filter = "cooldowns", "HELPFUL"
local selected
local resultPage, pinnedPage = 1, 1
local pageSize = 7

local function label(parent, value, x, y, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    text:SetPoint("TOPLEFT", x, y)
    text:SetText(value)
    return text
end

local function button(parent, value, x, y, width, action)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 22)
    control:SetPoint("TOPLEFT", x, y)
    control:SetText(value)
    control:SetScript("OnClick", action)
    return control
end

local function checkbox(parent, value, x, y, action)
    local control = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    control:SetPoint("TOPLEFT", x, y)
    control.caption = label(parent, value, x + 27, y - 9, "GameFontHighlightSmall")
    control:SetScript("OnClick", function(self) action(self:GetChecked()) end)
    return control
end

local function settingCheckbox(value, key, x, y)
    local control = checkbox(window.display, value, x, y, function(checked)
        Addon.GetSettings(section)[key] = checked
        Addon.ApplySettings()
    end)
    window.checkboxes[key] = control
end

local function settingSlider(value, key, y, low, high)
    local control = CreateFrame("Slider", nil, window.display, "UISliderTemplate")
    control:SetPoint("TOPLEFT", 187, y - 16)
    control:SetWidth(154)
    control:SetHeight(12)
    control:SetMinMaxValues(low, high)
    control:SetValueStep(1)
    control:SetObeyStepOnDrag(true)
    control.caption = label(window.display, value, 185, y, "GameFontHighlightSmall")
    control.title = value
    control:SetScript("OnValueChanged", function(_, current)
        if syncing then return end
        Addon.GetSettings(section)[key] = math.floor(current + 0.5)
        Addon.ApplySettings()
    end)
    window.sliders[key] = control
end

local function editbox(parent, x, y, width)
    local control = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    control:SetPoint("TOPLEFT", x, y)
    control:SetSize(width, 22)
    control:SetAutoFocus(false)
    control:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return control
end

local function entryText(entry)
    local parts = { entry.name }
    if entry.rank and entry.rank ~= "" then parts[#parts + 1] = entry.rank end
    if entry.level and entry.level > 0 then parts[#parts + 1] = "Lv. " .. entry.level end
    if entry.filter == "HARMFUL" then parts[#parts + 1] = "Debuff" end
    return table.concat(parts, "  ·  ")
end

local function sameEntry(left, right)
    return right ~= nil and left.id == right.id and left.filter == right.filter
end

local function updatePinControls()
    local pinIndex, pin
    if selected then pinIndex, pin = Addon.FindPin(section, selected.id, selected.filter) end
    local total = #Addon.GetSettings(section).entries
    window.remove:SetEnabled(pin ~= nil)
    window.up:SetEnabled(pinIndex ~= nil and pinIndex > 1)
    window.down:SetEnabled(pinIndex ~= nil and pinIndex < total)
    for key, control in pairs(window.overrides) do
        local state = pin and pin[key]
        local value = state == true and "On" or state == false and "Off" or "Default"
        control:SetText(control.title .. ": " .. value)
        control:SetEnabled(pin ~= nil)
    end
end

local function createEntryRow(x, y, isPinned)
    local row = CreateFrame("Button", nil, window.tracking)
    row:SetSize(165, 25)
    row:SetPoint("TOPLEFT", x, y)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.76, 0.2, 0.2)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetSize(20, 20)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.label:SetPoint("RIGHT", -3, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetMaxLines(1)
    row:SetScript("OnClick", function(self)
        if not self.entry then return end
        selected = { id = self.entry.id, filter = self.entry.filter }
        if not isPinned then Addon.Pin(section, selected.id, selected.filter) end
        Addon.UpdateChoices()
    end)
    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.entry.id)
        GameTooltip:AddLine("Spell ID " .. self.entry.id, 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function updateRows(list, entries, page, isPinned)
    local pages = math.max(1, math.ceil(#entries / pageSize))
    page = math.min(math.max(1, page), pages)
    for index, row in ipairs(list.rows) do
        local entry = entries[(page - 1) * pageSize + index]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.icon:SetTexture(entry.icon)
            local prefix = ""
            if not isPinned and Addon.FindPin(section, entry.id, entry.filter) then prefix = "+ " end
            row.label:SetText(prefix .. entryText(entry))
            row.selected:SetShown(sameEntry(entry, selected))
        end
    end
    list.page:SetText(page .. " / " .. pages)
    list.previous:SetEnabled(page > 1)
    list.next:SetEnabled(page < pages)
    return page
end

function Addon.UpdateChoices()
    if not window or not window:IsShown() then return end
    local settings = Addon.GetSettings(section)
    local query = window.search:GetText():lower():match("^%s*(.-)%s*$")
    local choices = {}
    for _, entry in ipairs(Addon.GetChoices(section, filter, settings.allRanks)) do
        local text = (entryText(entry) .. " " .. entry.id):lower()
        if query == "" or text:find(query, 1, true) then choices[#choices + 1] = entry end
    end
    resultPage = updateRows(window.results, choices, resultPage, false)
    local pins = {}
    for index, entry in ipairs(settings.entries) do
        local details = Addon.GetEntryDetails(section, entry.id)
        pins[index] = {
            id = entry.id, filter = entry.filter, name = details.name,
            icon = details.icon, rank = details.rank, level = details.level,
        }
    end
    pinnedPage = updateRows(window.pinned, pins, pinnedPage, true)
    if #choices == 0 then
        window.empty:SetText(section == "auras" and "No matching active effects" or "No matching abilities")
    else
        window.empty:SetText("")
    end
    updatePinControls()
end

local function addAuraByID()
    local text = window.auraID:GetText():match("^%s*(%d+)%s*$")
    local id = text and tonumber(text)
    if not id or id < 1 or id > 2147483647 or not C_Spell.GetSpellInfo(id) then
        window.status:SetText("Enter a valid aura spell ID.")
        return
    end
    selected = { id = id, filter = filter }
    Addon.Pin(section, id, filter)
    window.auraID:SetText("")
    window.auraID:ClearFocus()
    window.status:SetText("")
    Addon.UpdateChoices()
end

local function switchSection(key)
    section = key
    selected = nil
    pinnedPage, resultPage = 1, 1
    window.search:SetText("")
    window.status:SetText("")
    Addon.UpdateOptions()
end

local function switchFilter(value)
    filter = value
    resultPage = 1
    window.status:SetText("")
    Addon.UpdateOptions()
end

local function makeList(x, isPinned)
    local list = { rows = {} }
    for index = 1, pageSize do
        list.rows[index] = createEntryRow(x, -93 - (index - 1) * 26, isPinned)
    end
    list.previous = button(window.tracking, "<", x, -280, 36, function()
        if isPinned then pinnedPage = pinnedPage - 1 else resultPage = resultPage - 1 end
        Addon.UpdateChoices()
    end)
    list.page = label(window.tracking, "", x + 49, -285, "GameFontHighlightSmall")
    list.next = button(window.tracking, ">", x + 104, -280, 36, function()
        if isPinned then pinnedPage = pinnedPage + 1 else resultPage = resultPage + 1 end
        Addon.UpdateChoices()
    end)
    return list
end

local function changePinPosition(offset)
    if not selected then return end
    local entries = Addon.GetSettings(section).entries
    local index = Addon.FindPin(section, selected.id, selected.filter)
    if not index or not entries[index + offset] then return end
    entries[index], entries[index + offset] = entries[index + offset], entries[index]
    pinnedPage = math.ceil((index + offset) / pageSize)
    Addon.ApplySettings()
end

local function overrideButton(key, title, x)
    local control = button(window.tracking, title, x, -352, 112, function()
        if not selected then return end
        local _, pin = Addon.FindPin(section, selected.id, selected.filter)
        if not pin then return end
        if pin[key] == nil then
            pin[key] = true
        elseif pin[key] then
            pin[key] = false
        else
            pin[key] = nil
        end
        Addon.ApplySettings()
    end)
    control.title = title
    window.overrides[key] = control
end

local function makeWindow(manager)
    window = CreateFrame("Frame", "BetterForeverCooldownsOptions", manager)
    window:SetPoint("TOPLEFT", 12, -66)
    window:SetPoint("BOTTOMRIGHT", -12, 29)
    window:SetFrameLevel(manager:GetFrameLevel() + 20)
    window:EnableMouse(true)
    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", function() end)
    local background = window:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.08, 0.07, 0.06, 1)
    window.checkboxes, window.sliders, window.overrides = {}, {}, {}

    window.cooldowns = button(window, "Cooldowns", 10, -9, 100, function() switchSection("cooldowns") end)
    window.auras = button(window, "Self Auras", 113, -9, 100, function() switchSection("auras") end)
    window.tracking = CreateFrame("Frame", nil, window)
    window.tracking:SetPoint("TOPLEFT", 0, -36)
    window.tracking:SetPoint("BOTTOMRIGHT")
    window.display = CreateFrame("Frame", nil, window)
    window.display:SetAllPoints(window.tracking)
    window.display:Hide()
    window.page = button(window, "Display", 260, -9, 100, function(self)
        local showDisplay = not window.display:IsShown()
        window.display:SetShown(showDisplay)
        window.tracking:SetShown(not showDisplay)
        self:SetText(showDisplay and "Tracking" or "Display")
    end)

    local tracking = window.tracking
    window.resultsTitle = label(tracking, "", 12, -8)
    window.search = editbox(tracking, 16, -32, 156)
    window.search:SetScript("OnTextChanged", function()
        resultPage = 1
        Addon.UpdateChoices()
    end)
    window.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    window.empty = label(tracking, "", 12, -104, "GameFontDisableSmall")
    label(tracking, "Click an entry to track it", 12, -68, "GameFontDisableSmall")
    label(tracking, "Tracked icons", 192, -8)
    label(tracking, "Select an icon to edit it", 192, -68, "GameFontDisableSmall")
    window.results = makeList(12, false)
    window.pinned = makeList(192, true)
    window.helpful = button(tracking, "Buffs", 192, -32, 75, function() switchFilter("HELPFUL") end)
    window.harmful = button(tracking, "Debuffs", 275, -32, 78, function() switchFilter("HARMFUL") end)
    window.remove = button(tracking, "Remove", 192, -315, 68, function()
        if not selected then return end
        local index = Addon.FindPin(section, selected.id, selected.filter)
        if not index then return end
        table.remove(Addon.GetSettings(section).entries, index)
        selected = nil
        Addon.ApplySettings()
    end)
    window.up = button(tracking, "Up", 264, -315, 40, function() changePinPosition(-1) end)
    window.down = button(tracking, "Down", 308, -315, 47, function() changePinPosition(1) end)
    overrideButton("numbers", "Timer", 125)
    overrideButton("swipe", "Swipe", 243)
    window.idLabel = label(tracking, "Aura spell ID", 12, -311, "GameFontHighlightSmall")
    window.auraID = editbox(tracking, 16, -327, 85)
    window.auraID:SetNumeric(true)
    window.auraID:SetScript("OnEnterPressed", addAuraByID)
    window.addID = button(tracking, "Add", 105, -327, 55, addAuraByID)
    window.status = label(tracking, "", 12, -383, "GameFontHighlightSmall")
    window.note = label(tracking, "", 12, -409, "GameFontDisableSmall")
    window.note:SetWidth(343)
    window.note:SetJustifyH("LEFT")

    local display = window.display
    label(display, "Icon display", 12, -12)
    settingCheckbox("Countdown numbers", "numbers", 8, -35)
    settingCheckbox("Radial swipe", "swipe", 8, -64)
    settingCheckbox("Stacks on extra icons", "stacks", 8, -93)
    settingCheckbox("Show missing buffs", "showMissing", 8, -122)
    settingCheckbox("Ignore global cooldown", "ignoreGCD", 8, -122)
    settingCheckbox("Show all learned abilities", "showAll", 8, -151)
    settingCheckbox("Show all learned ranks", "allRanks", 8, -180)
    settingCheckbox("Style Blizzard icons", "styleBlizzard", 8, -209)
    settingSlider("Timer size", "fontSize", -35, 8, 32)
    settingSlider("Decimals below (sec)", "decimals", -75, 0, 10)
    settingSlider("Extra icon size", "size", -115, 20, 68)
    settingSlider("Extra icon spacing", "gap", -155, 0, 14)
    settingSlider("Extra icons per row", "columns", -195, 1, 16)
    window.alignment = button(display, "", 185, -235, 158, function()
        local settings = Addon.GetSettings(section)
        local nextAlignment = { CENTER = "LEFT", LEFT = "RIGHT", RIGHT = "CENTER" }
        settings.alignment = nextAlignment[settings.alignment] or "CENTER"
        Addon.ApplySettings()
    end)
    label(display, "Timer color (RRGGBB)", 185, -271, "GameFontHighlightSmall")
    window.color = editbox(display, 189, -290, 78)
    window.color:SetMaxLetters(6)
    window.color:SetScript("OnEditFocusLost", function(self)
        local color = self:GetText():lower()
        if color:match("^%x%x%x%x%x%x$") and color ~= Addon.GetSettings(section).color then
            Addon.GetSettings(section).color = color
            Addon.ApplySettings()
        else
            self:SetText(Addon.GetSettings(section).color)
        end
    end)
    window.color:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
end

function Addon.UpdateOptions()
    if not window or not window:IsShown() then return end
    syncing = true
    local isAura = section == "auras"
    local settings = Addon.GetSettings(section)
    window.cooldowns:SetEnabled(isAura)
    window.auras:SetEnabled(not isAura)
    window.helpful:SetEnabled(filter ~= "HELPFUL")
    window.harmful:SetEnabled(filter ~= "HARMFUL")
    for _, control in ipairs({ window.helpful, window.harmful, window.idLabel, window.auraID, window.addID }) do
        control:SetShown(isAura)
    end
    window.resultsTitle:SetText(isAura and "Search active effects" or "Search learned abilities")
    window.note:SetText(isAura
        and "Dimmed icons mark missing tracked buffs. Debuffs appear while active. Use the effect's aura spell ID when it differs from the cast."
        or "Extra abilities follow Essential or Utility. Move the Blizzard viewers in Edit Mode.")
    for key, control in pairs(window.checkboxes) do
        control:SetChecked(settings[key] == true)
        local visible = settings[key] ~= nil
        control:SetShown(visible)
        control.caption:SetShown(visible)
    end
    for key, control in pairs(window.sliders) do
        control:SetValue(settings[key])
        control.caption:SetText(control.title .. ": " .. settings[key])
    end
    window.alignment:SetText("Alignment: " .. settings.alignment:lower())
    if not window.color:HasFocus() then window.color:SetText(settings.color) end
    syncing = false
    Addon.UpdateChoices()
end

local function showPage(shown)
    if shown then
        if not window then makeWindow(CooldownViewerSettings) end
        window:Show()
        Addon.UpdateOptions()
    elseif window then
        window:Hide()
    end
    entryButton:SetText(shown and "Blizzard" or "Extras")
end

function Addon.AttachOptions()
    local manager = CooldownViewerSettings
    if entryButton or not manager or not manager.SettingsDropdown then return end
    entryButton = button(manager, "Extras", 0, 0, 75, function()
        showPage(not window or not window:IsShown())
    end)
    entryButton:ClearAllPoints()
    entryButton:SetPoint("LEFT", manager.SettingsDropdown, "RIGHT", 8, 0)
    manager:HookScript("OnHide", function() showPage(false) end)
    hooksecurefunc(manager, "SetDisplayMode", function() showPage(false) end)
end

function Addon.ShowOptions()
    Addon.AttachOptions()
    if not entryButton or InCombatLockdown() then return end
    if not CooldownViewerSettings:IsVisible() then CooldownViewerSettings:ShowUIPanel() end
    if CooldownViewerSettings:IsVisible() then showPage(true) end
end
