local ADDON_NAME, ns = ...

-- Public API: other addons (or your own Modules\*.lua files) can call
-- UIImport:RegisterModule(...) and UIImport:RegisterPack(...).
local UII = {}
ns.UII = UII
_G.UIImport = UII

UII.FORMAT_VERSION = 1
UII.DEFAULT_PROFILE_NAME = "UIImport"

UII.modules = {}     -- key -> module
UII.moduleList = {}  -- modules sorted by import order
UII.packs = {}       -- bundled packs: { name = ..., text = ... }

local C_AddOns = C_AddOns
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
local GetAddOnInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
local LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn

UII.LoadAddOn = LoadAddOn

function UII.Print(...)
	print("|cff33ccffUI Import|r:", ...)
end

--------------------------------------------------------------------------------
-- Modules
--------------------------------------------------------------------------------

--[[
A module teaches UI Import how to handle one addon. Fields:

  key         (string, required) The name used for this addon inside import
              strings. Never change it once strings using it exist.
  title       (string) Display name. Defaults to key.
  addon       (string) The addon's folder name, used to check it is loaded.
  order       (number) Lower numbers import first. Defaults to 100.

  Import(self, entry, ctx)  -> ok, message      (required)
      Apply an entry from an import string. ctx.profileName is the profile
      name the user picked. Return true plus a short summary, or false plus
      the reason it failed. Errors are caught and reported for you.

  Export(self, ctx)         -> entry | nil, err (optional)
      Build an entry from this character's current settings.

  FromString(self, text)    -> entry | nil, err (optional)
      Build an entry from the addon's own export string. Without this, the
      text is stored as { strings = { text } }.

An entry is any table of plain data (strings, numbers, booleans, tables). Most
modules use { strings = { "<the addon's own export string>", ... } }.
]]
function UII:RegisterModule(module)
	assert(type(module) == "table", "RegisterModule: expected a table")
	assert(type(module.key) == "string" and module.key ~= "", "RegisterModule: module.key must be a string")
	assert(type(module.Import) == "function", "RegisterModule: module.Import must be a function")
	assert(not self.modules[module.key], "RegisterModule: a module named '" .. module.key .. "' already exists")

	module.title = module.title or module.key
	module.order = module.order or 100
	self.modules[module.key] = module
	self.moduleList[#self.moduleList + 1] = module
	table.sort(self.moduleList, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.key < b.key
	end)

	if self.OnModulesChanged then
		self:OnModulesChanged()
	end
	return module
end

function UII:GetModule(key)
	return self.modules[key]
end

function UII:GetModules()
	return self.moduleList
end

-- Returns true when the module's addon is loaded, or false plus a reason.
function UII:IsModuleReady(module)
	if not module.addon then
		return true
	end
	if IsAddOnLoaded(module.addon) then
		return true
	end

	local _, _, _, loadable, reason = GetAddOnInfo(module.addon)
	if reason == "MISSING" then
		return false, "not installed"
	elseif reason == "DISABLED" then
		return false, "disabled"
	elseif loadable then
		return false, "not loaded"
	end
	return false, reason and reason:lower() or "not loaded"
end

-- Splits text on whitespace. Export strings never contain whitespace, so this
-- lets one text box hold several of them.
function UII.SplitStrings(text)
	local list = {}
	for piece in tostring(text or ""):gmatch("%S+") do
		list[#list + 1] = piece
	end
	return list
end

local function CaptureError(err)
	return tostring(err)
end

-- Runs fn, turning a thrown error into (false, message).
local function SafeCall(fn, ...)
	local args, n = { ... }, select("#", ...)
	local results = { xpcall(function()
		return fn(unpack(args, 1, n))
	end, CaptureError) }
	if not results[1] then
		return false, results[2]
	end
	return unpack(results, 2, table.maxn(results))
end

--------------------------------------------------------------------------------
-- Packs (the payload inside an import string)
--------------------------------------------------------------------------------

--[[
Decoded pack layout:
  {
    uii     = 1,             -- format version
    name    = "My UI",
    author  = "Someone",
    created = 1700000000,    -- time()
    build   = 20506,         -- interface version it was made on
    addons  = { [moduleKey] = entry, ... },
  }
]]

function UII:ReadPack(text)
	local pack, err = self.Codec.Decode(text)
	if not pack then
		return nil, err
	end
	if type(pack) ~= "table" or type(pack.addons) ~= "table" or not pack.uii then
		return nil, "That string decoded, but it isn't a UI Import pack."
	end
	if pack.uii > self.FORMAT_VERSION then
		return nil, "This string was made by a newer version of UI Import. Please update the addon."
	end
	return pack
end

-- Lists every addon in the pack, including ones we have no module for.
-- Each item: { key, module, entry, ready, reason }
function UII:GetPackContents(pack)
	local items, seen = {}, {}
	for _, module in ipairs(self.moduleList) do
		local entry = pack.addons[module.key]
		if entry ~= nil then
			local ready, reason = self:IsModuleReady(module)
			items[#items + 1] = { key = module.key, module = module, entry = entry, ready = ready, reason = reason }
			seen[module.key] = true
		end
	end
	local unknown = {}
	for key in pairs(pack.addons) do
		if not seen[key] then
			unknown[#unknown + 1] = key
		end
	end
	table.sort(unknown)
	for _, key in ipairs(unknown) do
		items[#items + 1] = { key = key, entry = pack.addons[key], ready = false, reason = "no module for this addon (update UI Import?)" }
	end
	return items
end

--[[
Imports a pack.
  opts.profileName  profile name to create in each addon (default: pack name)
  opts.selected     set of module keys to import; nil imports everything ready
Returns a list of { key, title, status = "ok"|"failed"|"skipped", message }.
]]
function UII:ImportPack(pack, opts)
	opts = opts or {}
	local profileName = opts.profileName
	if not profileName or profileName:match("^%s*$") then
		profileName = pack.name or self.DEFAULT_PROFILE_NAME
	end
	profileName = profileName:gsub("^%s+", ""):gsub("%s+$", "")

	local ctx = { profileName = profileName, pack = pack }
	local results = {}

	for _, item in ipairs(self:GetPackContents(pack)) do
		local result = { key = item.key, title = item.module and item.module.title or item.key }
		if opts.selected and not opts.selected[item.key] then
			result.status, result.message = "skipped", "not selected"
		elseif not item.module or not item.ready then
			result.status, result.message = "skipped", item.reason
		else
			local ok, message = SafeCall(item.module.Import, item.module, item.entry, ctx)
			result.status = ok and "ok" or "failed"
			result.message = message or (ok and "done" or "unknown error")
		end
		results[#results + 1] = result
	end

	if UIImportDB then
		UIImportDB.lastImport = {
			name = pack.name,
			profileName = profileName,
			time = time(),
			results = results,
		}
	end
	return results
end

--[[
Builds an import string.
  opts.name, opts.author
  opts.sources  { [moduleKey] = { text = "<addon export string>" } or { current = true } }
Returns text, report. text is nil when nothing could be included.
report is a list of { key, title, status = "ok"|"failed", message }.
]]
function UII:BuildPack(opts)
	local pack = {
		uii = self.FORMAT_VERSION,
		name = (opts.name and opts.name ~= "") and opts.name or "My UI",
		author = opts.author,
		created = time(),
		build = select(4, GetBuildInfo()),
		addons = {},
	}
	local ctx = { profileName = pack.name }
	local report, count = {}, 0

	for _, module in ipairs(self.moduleList) do
		local source = opts.sources and opts.sources[module.key]
		if source then
			local entry, err
			local fromText = source.text and source.text:match("%S") and true
			if fromText then
				if module.FromString then
					entry, err = SafeCall(module.FromString, module, source.text)
				else
					entry = { strings = UII.SplitStrings(source.text) }
				end
			elseif module.Export then
				local ready, reason = self:IsModuleReady(module)
				if ready then
					entry, err = SafeCall(module.Export, module, ctx)
				else
					err = module.title .. " is " .. reason .. "."
				end
			else
				err = "can't export current settings; paste " .. module.title .. "'s own export string instead"
			end

			if type(entry) == "table" then
				pack.addons[module.key] = entry
				count = count + 1
				report[#report + 1] = { key = module.key, title = module.title, status = "ok", message = fromText and "from pasted string" or "from current settings" }
			else
				report[#report + 1] = { key = module.key, title = module.title, status = "failed", message = err or "no data" }
			end
		end
	end

	if count == 0 then
		return nil, report
	end

	local text, err = self.Codec.Encode(pack)
	if not text then
		report[#report + 1] = { key = "", title = "UI Import", status = "failed", message = err }
	end
	return text, report
end

--------------------------------------------------------------------------------
-- Bundled packs
--------------------------------------------------------------------------------

--[[
Ship a pack inside the addon so it shows up as a one-click choice (see Packs.lua).
Pass either (name, importString) or a pack table holding each addon's own
export strings, which needs no trip into the game to build:

  UII:RegisterPack({
    name = "My UI",
    author = "Me",
    requires = { { addon = "SharedMedia", why = "fonts" } },  -- optional
    addons = { ElvUI = { strings = { "!E2!..." } } },
  })
]]
function UII:RegisterPack(nameOrPack, text)
	if type(nameOrPack) == "table" then
		local pack = nameOrPack
		assert(type(pack.name) == "string" and type(pack.addons) == "table", "RegisterPack: a pack table needs a name and an addons table")
		pack.uii = pack.uii or self.FORMAT_VERSION
		self.packs[#self.packs + 1] = { name = pack.name, pack = pack }
	else
		assert(type(nameOrPack) == "string" and type(text) == "string", "RegisterPack: expected (name, text) or a pack table")
		self.packs[#self.packs + 1] = { name = nameOrPack, text = text }
	end
end

-- Returns the pack's `requires` entries whose addon isn't loaded.
function UII:GetMissingRequirements(pack)
	local missing = {}
	for _, requirement in ipairs(pack.requires or {}) do
		if not IsAddOnLoaded(requirement.addon) then
			missing[#missing + 1] = requirement
		end
	end
	return missing
end

--------------------------------------------------------------------------------
-- Startup and slash commands
--------------------------------------------------------------------------------

local function PrintStatus()
	UII.Print("supported addons:")
	for _, module in ipairs(UII.moduleList) do
		local ready, reason = UII:IsModuleReady(module)
		print(("  %s: %s"):format(module.title, ready and "|cff40ff40ready|r" or ("|cff999999" .. reason .. "|r")))
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
	if name ~= ADDON_NAME then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	UIImportDB = UIImportDB or {}
end)

SLASH_UIIMPORT1 = "/uiimport"
SLASH_UIIMPORT2 = "/uii"
SlashCmdList.UIIMPORT = function(msg)
	local command = (msg or ""):lower():match("^%s*(%S*)")
	if command == "build" or command == "export" then
		UII:ShowWindow("build")
	elseif command == "status" or command == "list" then
		PrintStatus()
	elseif command == "" or command == "import" then
		UII:ShowWindow("import")
	else
		UII.Print("commands: /uii (import), /uii build, /uii status")
	end
end
