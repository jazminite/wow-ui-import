local _, ns = ...
local UII = ns.UII

-- ElvUI export strings carry one of four types: profile, private (per
-- character), global (account) or filters. An entry is { strings = { ... } }
-- holding any mix of them.
--
-- ElvUI changed its string format from !E1! (LibDeflate) to !E2!
-- (C_EncodingUtil) in 2026, and each ElvUI version reads only its own.
local EXPORT_TYPES = { "profile", "private", "global" }

local function GetElvUI()
	local E = ElvUI and ElvUI[1]
	if not E then
		return nil, "ElvUI is not loaded."
	end
	local D = E:GetModule("Distributor", true)
	if not D then
		return nil, "ElvUI's Distributor module is missing."
	end
	return E, D
end

-- Private settings live in two places after an import: E.private (the table
-- ElvUI loaded) and ElvPrivateDB (which an imported private string replaces,
-- and which is what gets saved). Change both.
local function SetPrivate(E, change)
	if E.private then
		change(E.private)
	end
	local keys = ElvPrivateDB and ElvPrivateDB.profileKeys
	local key = keys and keys[E.mynameRealm]
	local stored = key and ElvPrivateDB.profiles and ElvPrivateDB.profiles[key]
	if stored and stored ~= E.private then
		change(stored)
	end
end

-- ElvUI strips install_complete from imported private settings, which would
-- reopen its install wizard after the reload. Mark this character installed.
local function MarkInstalled(E)
	SetPrivate(E, function(private)
		private.install_complete = E.version
	end)
end

-- ElvUI's nameplates and Plater can't run together: ElvUI asks on every login
-- which to disable, and both draw on the same plates until you answer. The
-- Plater module calls this after setting up Plater. Returns true if ElvUI's
-- nameplates were on.
function ns.DisableElvUINamePlates()
	local E = ElvUI and ElvUI[1]
	if not (E and E.private and E.private.nameplates and E.private.nameplates.enable) then
		return false
	end
	SetPrivate(E, function(private)
		private.nameplates = private.nameplates or {}
		private.nameplates.enable = false
	end)
	return true
end

-- Explains a string the installed ElvUI can't read because of the format
-- change, or returns nil.
local function FormatProblem(E, D, str)
	local format = tonumber(str:match("^!E(%d+)!"))
	if not format or not D.GetImportStringType or D:GetImportStringType(str) ~= "" then
		return
	end
	if format >= 2 then
		return ("it needs a newer ElvUI than the installed v%s. Update ElvUI, then import again"):format(E.versionString or tostring(E.version))
	end
	return "it was exported from an old ElvUI that this version can't read. Get a fresh export of it"
end

UII:RegisterModule({
	key = "ElvUI",
	title = "ElvUI",
	addon = "ElvUI",
	order = 10,

	FromString = function(self, text)
		local strings = UII.SplitStrings(text)
		for _, str in ipairs(strings) do
			if not str:find("^!E%d+!") then
				return nil, "ElvUI export strings start with !E2! (use ElvUI's \"Text\" export format)"
			end
		end
		return { strings = strings }
	end,

	Export = function(self)
		local _, D = GetElvUI()
		if not D then
			return nil, "ElvUI is not loaded."
		end
		local strings = {}
		for _, dataType in ipairs(EXPORT_TYPES) do
			-- Current ElvUI takes (type, key, format); older builds took (type, format).
			local _, str = D:GetProfileExport(dataType, nil, "text")
			if not str then
				_, str = D:GetProfileExport(dataType, "text")
			end
			if str then
				strings[#strings + 1] = str
			end
		end
		if #strings == 0 then
			return nil, "ElvUI returned no export data."
		end
		return { strings = strings }
	end,

	Import = function(self, entry, ctx)
		local E, D = GetElvUI()
		if not E then
			return false, D
		end

		local imported, failed, problem = {}, 0, nil
		for _, str in ipairs(entry.strings or {}) do
			local formatProblem = FormatProblem(E, D, str)
			local dataType, dataKey, data
			if formatProblem then
				problem = formatProblem
			else
				dataType, dataKey, data = D:Decode(str)
			end
			if not dataType or type(data) ~= "table" then
				failed = failed + 1
			elseif dataType == "profile" then
				local name = ctx.profileName or dataKey
				D:SetImportedProfile(dataType, name, data, true)
				imported[#imported + 1] = ("profile \"%s\""):format(name)
			else
				D:SetImportedProfile(dataType, dataKey, data, true)
				imported[#imported + 1] = dataType
			end
		end

		if #imported == 0 then
			return false, problem or "none of the ElvUI strings could be read"
		end

		MarkInstalled(E)
		-- We ask for one reload at the end, so drop ElvUI's own reload prompt.
		if E.StaticPopup_Hide then
			E:StaticPopup_Hide("IMPORT_RL")
		end

		local message = table.concat(imported, ", ")
		if failed > 0 then
			message = message .. (" (%d string(s) unreadable%s)"):format(failed, problem and ": " .. problem or "")
		end
		return true, message
	end,
})
