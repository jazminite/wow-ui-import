-- Minimal stand-ins for the WoW API and the target addons, enough to run
-- UI Import's logic in plain Lua 5.1. Each mock records the calls it gets in
-- `calls` so tests can check what the modules asked for.

local M = { calls = {}, widgets = {}, popups = {} }

local function record(name, ...)
	M.calls[#M.calls + 1] = { name = name, args = { ... } }
end

function M.find(name)
	local found = {}
	for _, call in ipairs(M.calls) do
		if call.name == name then
			found[#found + 1] = call
		end
	end
	return found
end

function M.reset()
	M.calls = {}
end

--------------------------------------------------------------------------------
-- Test-only data codec: Lua literal + base64. Never used in the game.
--------------------------------------------------------------------------------

local function serialize(value)
	local t = type(value)
	if t == "string" then
		return string.format("%q", value)
	elseif t == "number" or t == "boolean" or t == "nil" then
		return tostring(value)
	elseif t == "table" then
		local parts = {}
		for k, v in pairs(value) do
			parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(v)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("can't serialize " .. t)
end

local function deserialize(text)
	local fn = loadstring("return " .. text)
	if not fn then
		error("bad data")
	end
	setfenv(fn, {})
	return fn()
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64(data)
	return ((data:gsub(".", function(c)
		local bits, byte = "", c:byte()
		for i = 8, 1, -1 do
			bits = bits .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0")
		end
		return bits
	end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
		if #x < 6 then
			return ""
		end
		local c = 0
		for i = 1, 6 do
			c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
		end
		return B64:sub(c + 1, c + 1)
	end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

local function unbase64(data)
	data = data:gsub("[^" .. B64 .. "=]", "")
	return (data:gsub(".", function(x)
		if x == "=" then
			return ""
		end
		local bits, f = "", B64:find(x, 1, true) - 1
		for i = 6, 1, -1 do
			bits = bits .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0")
		end
		return bits
	end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
		if #x ~= 8 then
			return ""
		end
		local c = 0
		for i = 1, 8 do
			c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0)
		end
		return string.char(c)
	end))
end

M.serialize, M.deserialize, M.base64, M.unbase64 = serialize, deserialize, base64, unbase64

function M.pack(value)
	return base64(serialize(value))
end

function M.unpack(text)
	return deserialize(unbase64(text))
end

--------------------------------------------------------------------------------
-- WoW API
--------------------------------------------------------------------------------

function M.installWoW()
	_G.print = function() end -- keep test output readable
	_G.time = os.time
	_G.date = os.date
	_G.GetBuildInfo = function()
		return "2.5.6", "12345", "Oct 1 2026", 20506
	end
	_G.UnitName = function()
		return "Tester"
	end
	_G.ReloadUI = function()
		record("ReloadUI")
	end
	_G.tinsert = table.insert
	_G.CANCEL = "Cancel"
	_G.RELOADUI = "Reload UI"
	_G.UISpecialFrames = {}
	_G.StaticPopupDialogs = {}
	_G.SlashCmdList = {}
	_G.ChatFontNormal = {}

	_G.CopyTable = function(t)
		local copy = {}
		for k, v in pairs(t) do
			copy[k] = type(v) == "table" and CopyTable(v) or v
		end
		return copy
	end

	_G.StaticPopup_Show = function(name, text, text2, data)
		M.popups[#M.popups + 1] = { name = name, text = text, data = data }
	end

	_G.C_Timer = {
		After = function(_, fn)
			fn()
		end,
	}

	_G.Enum = {
		CompressionMethod = { Deflate = 0 },
		CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 },
	}
	_G.C_EncodingUtil = {
		SerializeCBOR = function(v)
			return serialize(v)
		end,
		DeserializeCBOR = function(s)
			return deserialize(s)
		end,
		CompressString = function(s)
			return s
		end,
		DecompressString = function(s)
			return s
		end,
		EncodeBase64 = base64,
		DecodeBase64 = unbase64,
	}

	M.loadedAddOns = {}
	M.installedAddOns = {}
	_G.C_AddOns = {
		IsAddOnLoaded = function(name)
			return M.loadedAddOns[name] and true or false
		end,
		GetAddOnInfo = function(name)
			if not M.installedAddOns[name] then
				return name, nil, nil, false, "MISSING"
			end
			return name, name, "", true, nil
		end,
		LoadAddOn = function(name)
			record("LoadAddOn", name)
		end,
	}

	-- Generic widget: records scripts and text, ignores layout calls.
	-- Unknown Capitalized keys are treated as no-op methods; lowercase keys are
	-- plain data fields.
	local Widget = {}
	local noop = function() end
	Widget.__index = function(self, key)
		local method = rawget(Widget, key)
		if method then
			return method
		end
		if type(key) == "string" and key:find("^%u") then
			return noop
		end
	end
	function Widget:SetScript(event, fn)
		self.scripts[event] = fn
	end
	function Widget:HookScript(event, fn)
		local old = self.scripts[event]
		self.scripts[event] = old and function(...)
			old(...)
			fn(...)
		end or fn
	end
	function Widget:Fire(event, ...)
		if self.scripts[event] then
			self.scripts[event](self, ...)
		end
	end
	function Widget:SetText(text)
		self.text = text
		self:Fire("OnTextChanged", false)
	end
	function Widget:GetText()
		return self.text or ""
	end
	function Widget:Type(text)
		self.text = text
		self:Fire("OnTextChanged", true)
	end
	function Widget:SetChecked(v)
		self.checked = v and true or false
	end
	function Widget:GetChecked()
		return self.checked
	end
	function Widget:Show()
		self.shown = true
	end
	function Widget:Hide()
		self.shown = false
	end
	function Widget:SetShown(v)
		self.shown = v and true or false
	end
	function Widget:IsShown()
		return self.shown
	end
	function Widget:SetEnabled(v)
		self.enabled = v and true or false
	end
	function Widget:Enable()
		self.enabled = true
	end
	function Widget:Disable()
		self.enabled = false
	end
	function Widget:IsEnabled()
		return self.enabled
	end
	function Widget:SetMultiLine(v)
		self.multiLine = v
	end
	function Widget:HasFocus()
		return false
	end
	function Widget:Click()
		self:Fire("OnClick")
	end
	function Widget:CreateFontString()
		return M.newWidget("FontString")
	end

	function M.newWidget(kind, template)
		local widget = setmetatable({ kind = kind, template = template, scripts = {}, shown = true, enabled = true }, Widget)
		M.widgets[#M.widgets + 1] = widget
		return widget
	end

	_G.UIParent = M.newWidget("Frame")
	_G.CreateFrame = function(kind, name, parent, template)
		local widget = M.newWidget(kind, template)
		if name then
			_G[name] = widget
		end
		return widget
	end
end

function M.findWidget(predicate)
	for _, widget in ipairs(M.widgets) do
		if predicate(widget) then
			return widget
		end
	end
end

function M.findButton(text)
	return M.findWidget(function(w)
		return w.kind == "Button" and w.text == text
	end)
end

--------------------------------------------------------------------------------
-- LibStub and libraries
--------------------------------------------------------------------------------

function M.installLibStub()
	local libs = {}
	_G.LibStub = setmetatable({ libs = libs }, {
		__call = function(_, name, silent)
			if not libs[name] and not silent then
				error("no library " .. name)
			end
			return libs[name]
		end,
	})

	libs["LibSerialize"] = {
		Serialize = function(_, v)
			return serialize(v)
		end,
		Deserialize = function(_, s)
			return pcall(deserialize, s)
		end,
	}
	libs["LibDeflate"] = {
		CompressDeflate = function(_, s)
			return s
		end,
		DecompressDeflate = function(_, s)
			return s
		end,
		EncodeForPrint = function(_, s)
			return base64(s)
		end,
		DecodeForPrint = function(_, s)
			return unbase64(s)
		end,
	}
	return libs
end

--------------------------------------------------------------------------------
-- Target addons
--------------------------------------------------------------------------------

-- opts.exportPrefix: the string format this ElvUI reads. "!E2!" is current;
-- "!E1!" acts like ElvUI v15.13 and older.
function M.installElvUI(opts)
	opts = opts or {}
	local prefix = opts.exportPrefix or "!E2!"
	local D = {}
	function D:GetImportStringType(str)
		return (str:sub(1, #prefix) == prefix and "Deflate") or (str:find("^{") and "Table") or ""
	end
	function D:Decode(str)
		record("ElvUI.Decode", str)
		if self:GetImportStringType(str) ~= "Deflate" then
			return
		end
		local dataType, key = str:sub(#prefix + 1):match("^(%a+):(.*)$")
		if not dataType then
			return
		end
		return dataType, key ~= "" and key or nil, { from = str }
	end
	function D:SetImportedProfile(...)
		record("ElvUI.SetImportedProfile", ...)
	end
	function D:GetProfileExport(dataType, dataKey, dataFormat)
		if dataFormat ~= "text" then
			return
		end
		return dataType, "!E2!" .. dataType .. ":" .. (dataType == "profile" and "Current" or "")
	end

	-- Like real ElvUI: the live private table is the stored one, with defaults
	-- (nameplates on) filled in.
	local E = {
		version = 99.9,
		versionString = prefix == "!E1!" and "15.13" or "16.00",
		mynameRealm = "Tester - Realm",
		private = { nameplates = { enable = true } },
	}
	function E:GetModule(name)
		return name == "Distributor" and D or nil
	end
	function E:StaticPopup_Hide(name)
		record("ElvUI.StaticPopup_Hide", name)
	end
	_G.ElvUI = { E }
	_G.ElvPrivateDB = { profileKeys = { ["Tester - Realm"] = "Tester - Realm" }, profiles = { ["Tester - Realm"] = E.private } }
	M.loadedAddOns.ElvUI, M.installedAddOns.ElvUI = true, true
	return E, D
end

function M.installPlater()
	local db = {
		current = "Default",
		profile = {
			plate_config = { enemy = true },
			npc_cache = { [101] = { "Boar" }, [102] = { "Wolf" } },
			npc_colors = { [101] = { "red" } },
			npcs_renamed = {},
			hook_data = { { Name = "Hook", HooksTemp = { junk = true } } },
		},
	}
	function db:GetCurrentProfile()
		return self.current
	end
	function db:SetProfile(name)
		record("Plater.db.SetProfile", name)
		self.current = name
	end
	function db:ResetProfile()
		self.profile = {}
	end

	_G.Plater = {
		db = db,
		CompressData = function(data, dataType)
			return "!PLATER:2!" .. M.pack(data)
		end,
		DecompressData = function(data, dataType, silent)
			local body = data:match("^!PLATER:2!(.+)$")
			return body and M.unpack(body)
		end,
		ImportAndSwitchProfile = function(...)
			record("Plater.ImportAndSwitchProfile", ...)
		end,
	}
	_G.PLATER_DEFAULT_SETTINGS = { profile = { spell_animation_list = { default = true } } }
	M.loadedAddOns.Plater, M.installedAddOns.Plater = true, true
end

function M.installDetails()
	_G.Details = {
		ImportProfile = function(self, ...)
			record("Details.ImportProfile", ...)
			return true
		end,
		ExportCurrentProfile = function(self)
			return "DetailsString123"
		end,
	}
	M.loadedAddOns.Details, M.installedAddOns.Details = true, true
end

function M.installTipTac(libs)
	local profileTable = { fontSize = 12 }
	local configDb = {
		SetProfile = function(self, name)
			record("TipTac.configDb.SetProfile", name)
		end,
	}
	local cfg = { __GetLinkedTable = profileTable }
	libs["LibFroznFunctions-1.0"] = {
		CreateDbWithLibAceDB = function(self, name)
			assert(name == "TipTac_Config")
			return configDb, cfg
		end,
		MixinWholeObjects = function(self, target, source)
			record("TipTac.MixinWholeObjects", target, source)
		end,
	}
	_G.TipTac = {
		ApplyConfig = function(self)
			record("TipTac.ApplyConfig")
		end,
	}
	M.loadedAddOns.TipTac, M.installedAddOns.TipTac = true, true
	return cfg
end

return M
