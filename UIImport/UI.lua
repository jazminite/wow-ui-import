local _, ns = ...
local UII = ns.UII

local WIDTH, HEIGHT = 660, 600
local PAGE_WIDTH = WIDTH - 40

local GREEN, RED, GRAY, GOLD = "|cff40ff40", "|cffff5555", "|cff999999", "|cffffd100"

local frame, pages, tabs = nil, {}, {}

--------------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------------

local function SetBoxBackdrop(box)
	box:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	box:SetBackdropColor(0, 0, 0, 0.6)
	box:SetBackdropBorderColor(0.4, 0.4, 0.4)
end

local function CreateLabel(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
	label:SetJustifyH("LEFT")
	label:SetText(text or "")
	return label
end

local function CreateButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 120, 22)
	button:SetText(text)
	return button
end

local function CreateInput(parent, width)
	local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	input:SetSize(width, 20)
	input:SetAutoFocus(false)
	input:SetScript("OnEscapePressed", input.ClearFocus)
	input:SetScript("OnEnterPressed", input.ClearFocus)
	return input
end

-- A bordered, scrolling, multi-line edit box. Returns the EditBox; its outer
-- frame (for anchoring) is edit.box.
local function CreateTextArea(parent, width, height, placeholder)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetSize(width, height)
	SetBoxBackdrop(box)

	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -27, 6)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(width - 35)
	edit:SetHeight(height - 12)
	edit:SetMaxLetters(0)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	if ScrollingEdit_OnCursorChanged then
		edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
		edit:SetScript("OnUpdate", ScrollingEdit_OnUpdate)
	end
	scroll:SetScrollChild(edit)

	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)

	if placeholder then
		local hint = CreateLabel(box, placeholder, "GameFontDisableSmall")
		hint:SetPoint("TOPLEFT", 8, -8)
		hint:SetPoint("RIGHT", -30, 0)
		local function Update()
			hint:SetShown(edit:GetText() == "" and not edit:HasFocus())
		end
		edit:HookScript("OnTextChanged", Update)
		edit:HookScript("OnEditFocusGained", Update)
		edit:HookScript("OnEditFocusLost", Update)
	end

	edit.box = box
	return edit
end

-- A scroll frame whose child holds a vertical list of rows.
local function CreateList(parent, width, height)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetSize(width, height)
	SetBoxBackdrop(box)

	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -27, 6)

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width - 35, 1)
	scroll:SetScrollChild(child)

	box.child = child
	box.rowWidth = width - 35
	return box
end

local function FormatStatus(ready, reason)
	return ready and (GREEN .. "ready|r") or (GRAY .. (reason or "unavailable") .. "|r")
end

local function FormatResult(result)
	local color = (result.status == "ok" and GREEN) or (result.status == "failed" and RED) or GRAY
	return color .. result.status .. "|r " .. (result.message or "")
end

--------------------------------------------------------------------------------
-- Popups
--------------------------------------------------------------------------------

StaticPopupDialogs.UIIMPORT_CONFIRM = {
	text = "%s",
	button1 = "Import",
	button2 = CANCEL,
	OnAccept = function(self, onAccept)
		onAccept()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	preferredIndex = 3,
}

StaticPopupDialogs.UIIMPORT_RELOAD = {
	text = "UI Import is done. Reload your UI now to finish applying the settings?",
	button1 = RELOADUI or "Reload UI",
	button2 = "Later",
	OnAccept = function()
		ReloadUI()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	preferredIndex = 3,
}

--------------------------------------------------------------------------------
-- Import page
--------------------------------------------------------------------------------

local function BuildImportPage(page)
	local state = { pack = nil, rows = {} }

	local label = CreateLabel(page, "Paste a UI Import string:")
	label:SetPoint("TOPLEFT", 0, 0)

	local input = CreateTextArea(page, PAGE_WIDTH, 110, "Starts with !UII:1!")
	input.box:SetPoint("TOPLEFT", 0, -18)

	local clear = CreateButton(page, "Clear", 80)
	clear:SetPoint("TOPRIGHT", input.box, "BOTTOMRIGHT", 0, -6)

	local packsLabel = CreateLabel(page, "Included packs:", "GameFontHighlightSmall")
	packsLabel:SetPoint("TOPLEFT", input.box, "BOTTOMLEFT", 0, -11)
	packsLabel:Hide()
	state.packButtons = {}

	local info = CreateLabel(page, "", "GameFontHighlight")
	info:SetPoint("TOPLEFT", input.box, "BOTTOMLEFT", 0, -38)
	info:SetWidth(PAGE_WIDTH)
	info:SetHeight(30)
	info:SetJustifyV("TOP")

	local profileLabel = CreateLabel(page, "Profile name:")
	profileLabel:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -8)
	local profileInput = CreateInput(page, 200)
	profileInput:SetPoint("LEFT", profileLabel, "RIGHT", 12, 0)
	local profileHint = CreateLabel(page, "created (or replaced) in every addon below", "GameFontDisableSmall")
	profileHint:SetPoint("LEFT", profileInput, "RIGHT", 10, 0)

	local listLabel = CreateLabel(page, "Addons in this pack:")
	listLabel:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -14)

	local list = CreateList(page, PAGE_WIDTH, 210)
	list:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -4)

	local importButton = CreateButton(page, "Import Pack", 140)
	importButton:SetPoint("BOTTOMRIGHT", 0, 0)
	importButton:Disable()

	local summary = CreateLabel(page, "", "GameFontHighlightSmall")
	summary:SetPoint("LEFT", page, "BOTTOMLEFT", 0, 11)
	summary:SetPoint("RIGHT", importButton, "LEFT", -10, 0)

	local function GetRow(index)
		local row = state.rows[index]
		if row then
			return row
		end
		row = CreateFrame("Frame", nil, list.child)
		row:SetSize(list.rowWidth, 24)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * 24)
		row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.check:SetSize(24, 24)
		row.check:SetPoint("LEFT")
		row.title = CreateLabel(row, "")
		row.title:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
		row.title:SetWidth(170)
		row.status = CreateLabel(row, "", "GameFontHighlightSmall")
		row.status:SetPoint("LEFT", row.title, "RIGHT", 8, 0)
		row.status:SetPoint("RIGHT")
		row.status:SetWordWrap(false)
		state.rows[index] = row
		return row
	end

	local function ShowItems(items)
		for _, row in ipairs(state.rows) do
			row:Hide()
		end
		local anyReady = false
		for index, item in ipairs(items or {}) do
			local row = GetRow(index)
			row.key = item.key
			row.title:SetText(item.module and item.module.title or item.key)
			row.status:SetText(FormatStatus(item.ready, item.reason))
			row.check:SetChecked(item.ready)
			row.check:SetEnabled(item.ready)
			row:Show()
			anyReady = anyReady or item.ready
		end
		list.child:SetHeight(math.max(1, #(items or {}) * 24))
		importButton:SetEnabled(anyReady)
	end

	local function Reset(message)
		state.pack = nil
		info:SetText(message or "")
		summary:SetText("")
		ShowItems(nil)
	end

	local function Read()
		local text = input:GetText()
		if not text:match("%S") then
			Reset()
			return
		end
		local pack, err = UII:ReadPack(text)
		if not pack then
			Reset(RED .. err .. "|r")
			return
		end
		state.pack = pack
		local details = {}
		if pack.author and pack.author ~= "" then
			details[#details + 1] = "by " .. pack.author
		end
		if pack.created then
			details[#details + 1] = "made " .. date("%Y-%m-%d", pack.created)
		end
		info:SetText(GOLD .. (pack.name or "Unnamed pack") .. "|r  " .. table.concat(details, ", "))
		profileInput:SetText(pack.name or UII.DEFAULT_PROFILE_NAME)
		summary:SetText("")
		ShowItems(UII:GetPackContents(pack))
	end

	-- Read shortly after typing/pasting stops, so huge pastes are parsed once.
	local pending = 0
	input:HookScript("OnTextChanged", function(self, userInput)
		if not userInput then
			return
		end
		pending = pending + 1
		local token = pending
		C_Timer.After(0.3, function()
			if token == pending then
				Read()
			end
		end)
	end)

	clear:SetScript("OnClick", function()
		input:SetText("")
		Reset()
	end)

	local function RunImport()
		local selected = {}
		for _, row in ipairs(state.rows) do
			if row:IsShown() and row.check:GetChecked() then
				selected[row.key] = true
			end
		end

		local results = UII:ImportPack(state.pack, { profileName = profileInput:GetText(), selected = selected })
		local rowsByKey = {}
		for _, row in ipairs(state.rows) do
			if row:IsShown() then
				rowsByKey[row.key] = row
			end
		end
		local imported, failed = 0, 0
		for _, result in ipairs(results) do
			local row = rowsByKey[result.key]
			if row then
				row.status:SetText(FormatResult(result))
			end
			if result.status == "ok" then
				imported = imported + 1
			elseif result.status == "failed" then
				failed = failed + 1
			end
			UII.Print(result.title .. ": " .. FormatResult(result))
		end

		summary:SetText(("%d imported, %d failed."):format(imported, failed))
		if imported > 0 then
			StaticPopup_Show("UIIMPORT_RELOAD")
		end
	end

	importButton:SetScript("OnClick", function()
		if not state.pack then
			return
		end
		local count = 0
		for _, row in ipairs(state.rows) do
			if row:IsShown() and row.check:GetChecked() then
				count = count + 1
			end
		end
		if count == 0 then
			summary:SetText("Tick at least one addon.")
			return
		end
		local name = profileInput:GetText()
		if not name:match("%S") then
			name = state.pack.name or UII.DEFAULT_PROFILE_NAME
		end
		local text = ("Import \"%s\" into %d addon(s)?\n\nEach one gets a profile named \"%s\". An existing profile with that name is replaced."):format(
			state.pack.name or "this pack", count, name)
		StaticPopup_Show("UIIMPORT_CONFIRM", text, nil, RunImport)
	end)

	function page:Refresh()
		-- Bundled packs (Packs.lua) become one-click buttons.
		packsLabel:SetShown(#UII.packs > 0)
		local previous = packsLabel
		for index, bundled in ipairs(UII.packs) do
			local button = state.packButtons[index]
			if not button then
				button = CreateButton(page, bundled.name, 140)
				button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
				button:SetScript("OnClick", function()
					input:SetText(bundled.text)
					Read()
				end)
				state.packButtons[index] = button
			end
			previous = button
		end
		if state.pack then
			ShowItems(UII:GetPackContents(state.pack))
		end
	end
end

--------------------------------------------------------------------------------
-- Build page
--------------------------------------------------------------------------------

local BUILD_ROW_HEIGHT = 68

local function BuildBuildPage(page)
	local rows = {}

	local nameLabel = CreateLabel(page, "Pack name:")
	nameLabel:SetPoint("TOPLEFT", 0, -3)
	local nameInput = CreateInput(page, 200)
	nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
	nameInput:SetText(UnitName("player") .. "'s UI")

	local authorLabel = CreateLabel(page, "Author:")
	authorLabel:SetPoint("LEFT", nameInput, "RIGHT", 24, 0)
	local authorInput = CreateInput(page, 160)
	authorInput:SetPoint("LEFT", authorLabel, "RIGHT", 12, 0)
	authorInput:SetText(UnitName("player"))

	local help = CreateLabel(page, "Tick the addons to include. Leave an addon's box empty to use this character's current settings, or paste that addon's own export string into it.", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", 0, -30)
	help:SetWidth(PAGE_WIDTH)

	local list = CreateList(page, PAGE_WIDTH, 290)
	list:SetPoint("TOPLEFT", 0, -58)

	local createButton = CreateButton(page, "Create String", 140)
	createButton:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8)

	local report = CreateLabel(page, "", "GameFontHighlightSmall")
	report:SetPoint("LEFT", createButton, "RIGHT", 10, 0)
	report:SetPoint("RIGHT", page, "RIGHT", 0, 0)
	report:SetWordWrap(true)

	local output = CreateTextArea(page, PAGE_WIDTH, 120, "Your import string appears here. Click it, then press Ctrl+C to copy.")
	output.box:SetPoint("TOPLEFT", createButton, "BOTTOMLEFT", 0, -8)
	output.value = ""
	-- Read-only: undo any typing, but keep it selectable for Ctrl+C.
	output:HookScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(self.value)
			self:HighlightText()
		end
	end)
	output:HookScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)

	local function CreateRow(module, index)
		local row = CreateFrame("Frame", nil, list.child)
		row:SetSize(list.rowWidth, BUILD_ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * BUILD_ROW_HEIGHT)
		row.module = module
		row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.check:SetSize(24, 24)
		row.check:SetPoint("TOPLEFT")
		row.title = CreateLabel(row, module.title)
		row.title:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
		row.status = CreateLabel(row, "", "GameFontHighlightSmall")
		row.status:SetPoint("LEFT", row.title, "RIGHT", 10, 0)
		row.edit = CreateTextArea(row, list.rowWidth - 28, 40,
			module.Export and "Empty: use my current " .. module.title .. " settings" or "Paste " .. module.title .. "'s export string")
		row.edit.box:SetPoint("TOPLEFT", 26, -24)
		return row
	end

	function page:Refresh()
		for index, module in ipairs(UII:GetModules()) do
			local row = rows[module.key]
			if not row then
				row = CreateRow(module, index)
				rows[module.key] = row
				local ready = UII:IsModuleReady(module)
				row.check:SetChecked(ready)
			end
			row:SetPoint("TOPLEFT", 0, -(index - 1) * BUILD_ROW_HEIGHT)
			row.status:SetText(FormatStatus(UII:IsModuleReady(module)))
		end
		list.child:SetHeight(math.max(1, #UII:GetModules() * BUILD_ROW_HEIGHT))
	end

	createButton:SetScript("OnClick", function()
		local sources = {}
		for key, row in pairs(rows) do
			if row.check:GetChecked() then
				sources[key] = { text = row.edit:GetText() }
			end
		end
		if not next(sources) then
			report:SetText("Tick at least one addon.")
			return
		end

		local text, results = UII:BuildPack({ name = nameInput:GetText(), author = authorInput:GetText(), sources = sources })
		local lines = {}
		for _, result in ipairs(results) do
			lines[#lines + 1] = result.title .. ": " .. FormatResult(result)
			UII.Print(result.title .. ": " .. FormatResult(result))
		end
		report:SetText(table.concat(lines, "   "))

		output.value = text or ""
		output:SetText(output.value)
		if text then
			UII.Print(("import string created (%d characters)."):format(#text))
			output:SetFocus()
			output:HighlightText()
		end
	end)
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local function SelectTab(name)
	for key, page in pairs(pages) do
		page:SetShown(key == name)
		if tabs[key] then
			if key == name then
				tabs[key]:LockHighlight()
			else
				tabs[key]:UnlockHighlight()
			end
		end
	end
	if pages[name].Refresh then
		pages[name]:Refresh()
	end
end

local function CreateWindow()
	frame = CreateFrame("Frame", "UIImportFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	tinsert(UISpecialFrames, "UIImportFrame")

	local title = CreateLabel(frame, "UI Import", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -18)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local previous
	for _, info in ipairs({ { "import", "Import" }, { "build", "Build" } }) do
		local key = info[1]
		local tab = CreateButton(frame, info[2], 100)
		if previous then
			tab:SetPoint("LEFT", previous, "RIGHT", 6, 0)
		else
			tab:SetPoint("TOPLEFT", 20, -42)
		end
		tab:SetScript("OnClick", function()
			SelectTab(key)
		end)
		tabs[key] = tab
		previous = tab

		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", 20, -74)
		page:SetPoint("BOTTOMRIGHT", -20, 18)
		pages[key] = page
	end

	BuildImportPage(pages.import)
	BuildBuildPage(pages.build)
	frame:Hide()
end

function UII:ShowWindow(tab)
	if not frame then
		CreateWindow()
	end
	frame:Show()
	SelectTab(tab or "import")
end

-- Third-party modules may register after the window exists.
function UII:OnModulesChanged()
	if frame and frame:IsShown() then
		for _, page in pairs(pages) do
			if page:IsShown() and page.Refresh then
				page:Refresh()
			end
		end
	end
end
