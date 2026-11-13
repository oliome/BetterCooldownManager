local _, Addon = ...
local window, moveDone, syncing
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
    local control = checkbox(window, value, x, y, function(checked)
        Addon.GetSettings(section)[key] = checked
        Addon.ApplySettings()
    end)
    window.checkboxes[key] = control
end

local function settingSlider(value, key, y, low, high)
    local control = CreateFrame("Slider", nil, window, "UISliderTemplate")
    control:SetPoint("TOPLEFT", 540, y - 15)
    control:SetWidth(212)
    control:SetHeight(12)
    control:SetMinMaxValues(low, high)
    control:SetValueStep(1)
    control:SetObeyStepOnDrag(true)
    control.caption = label(window, value, 538, y)
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
    local row = CreateFrame("Button", nil, window)
    row:SetSize(240, 25)
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
        list.rows[index] = createEntryRow(x, -143 - (index - 1) * 26, isPinned)
    end
    list.previous = button(window, "<", x, -330, 36, function()
        if isPinned then pinnedPage = pinnedPage - 1 else resultPage = resultPage - 1 end
        Addon.UpdateChoices()
    end)
    list.page = label(window, "", x + 49, -335, "GameFontHighlightSmall")
    list.next = button(window, ">", x + 104, -330, 36, function()
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
    local control = button(window, title, x, -394, 120, function()
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

local function beginMoving()
    window:Hide()
    moveDone:Show()
    Addon.SetMoving(true)
end

local function makeWindow()
    window = CreateFrame("Frame", "BetterForeverCooldownsOptions", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(778, 522)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window.TitleText:SetText("Better Forever Cooldowns")
    table.insert(UISpecialFrames, window:GetName())
    window.checkboxes, window.sliders, window.overrides = {}, {}, {}

    window.cooldowns = button(window, "Cooldowns", 18, -34, 112, function() switchSection("cooldowns") end)
    window.auras = button(window, "Self Auras", 136, -34, 112, function() switchSection("auras") end)
    button(window, "Move icon sections", 603, -34, 149, beginMoving)
    moveDone = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    moveDone:SetSize(200, 26)
    moveDone:SetPoint("TOP", UIParent, "TOP", 0, -100)
    moveDone:SetFrameStrata("DIALOG")
    moveDone:SetText("Done moving icon sections")
    moveDone:SetScript("OnClick", Addon.ShowOptions)
    moveDone:Hide()

    window.resultsTitle = label(window, "", 18, -76)
    window.search = editbox(window, 22, -100, 230)
    window.search:SetScript("OnTextChanged", function()
        resultPage = 1
        Addon.UpdateChoices()
    end)
    window.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    window.empty = label(window, "", 22, -153, "GameFontDisableSmall")
    label(window, "Click an entry to track it", 18, -124, "GameFontDisableSmall")
    label(window, "Tracked icons", 274, -76)
    label(window, "Select an icon to reorder or style it", 274, -124, "GameFontDisableSmall")
    window.results = makeList(18, false)
    window.pinned = makeList(274, true)
    window.helpful = button(window, "Buffs", 274, -98, 84, function() switchFilter("HELPFUL") end)
    window.harmful = button(window, "Debuffs", 362, -98, 84, function() switchFilter("HARMFUL") end)
    window.remove = button(window, "Remove", 274, -363, 90, function()
        if not selected then return end
        local index = Addon.FindPin(section, selected.id, selected.filter)
        if not index then return end
        table.remove(Addon.GetSettings(section).entries, index)
        selected = nil
        Addon.ApplySettings()
    end)
    window.up = button(window, "Up", 372, -363, 56, function() changePinPosition(-1) end)
    window.down = button(window, "Down", 434, -363, 64, function() changePinPosition(1) end)
    overrideButton("numbers", "Timer", 274)
    overrideButton("swipe", "Swipe", 396)
    window.idLabel = label(window, "Aura spell ID", 18, -367, "GameFontHighlightSmall")
    window.auraID = editbox(window, 22, -390, 115)
    window.auraID:SetNumeric(true)
    window.auraID:SetScript("OnEnterPressed", addAuraByID)
    window.addID = button(window, "Add", 146, -390, 72, addAuraByID)
    window.status = label(window, "", 18, -422, "GameFontHighlightSmall")
    window.note = label(window, "", 18, -464, "GameFontDisableSmall")
    window.note:SetWidth(494)
    window.note:SetJustifyH("LEFT")

    label(window, "Icon display", 538, -76)
    settingCheckbox("Countdown numbers", "numbers", 534, -92)
    settingCheckbox("Radial swipe", "swipe", 534, -117)
    settingCheckbox("Stacks or charges", "stacks", 534, -142)
    settingCheckbox("Show missing buffs", "showMissing", 534, -167)
    settingCheckbox("Ignore global cooldown", "ignoreGCD", 534, -167)
    settingCheckbox("Show all learned abilities", "showAll", 534, -192)
    settingCheckbox("Show all learned ranks", "allRanks", 534, -217)
    settingCheckbox("Style Blizzard cooldown icons", "styleBlizzard", 534, -242)
    settingSlider("Timer size", "fontSize", -278, 8, 32)
    settingSlider("Decimals below (seconds)", "decimals", -311, 0, 10)
    settingSlider("Icon size", "size", -344, 20, 68)
    settingSlider("Icon spacing", "gap", -377, 0, 14)
    settingSlider("Icons per row", "columns", -410, 1, 16)
    window.alignment = button(window, "", 538, -452, 212, function()
        local settings = Addon.GetSettings(section)
        local nextAlignment = { CENTER = "LEFT", LEFT = "RIGHT", RIGHT = "CENTER" }
        settings.alignment = nextAlignment[settings.alignment] or "CENTER"
        Addon.ApplySettings()
    end)
    label(window, "Timer color (RRGGBB)", 538, -487, "GameFontHighlightSmall")
    window.color = editbox(window, 671, -482, 78)
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
    window.resultsTitle:SetText(isAura and "Search active effects on you" or "Search learned abilities")
    window.note:SetText(isAura
        and "Dimmed icons mark missing tracked buffs. Debuffs appear while active. Use the effect's aura spell ID when it differs from the cast."
        or "Pin a specific rank to keep it after learning a higher one. Blizzard's Edit Mode controls the placement of Essential and Utility icons.")
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

function Addon.ShowOptions()
    if not window then makeWindow() end
    if moveDone:IsShown() then
        moveDone:Hide()
        Addon.SetMoving(false)
    end
    window:Show()
    Addon.UpdateOptions()
end
