local _, ns = ...
local UII = ns.UII

-- ElvUI export strings start with !E2! and carry one of four types:
-- profile, private (per character), global (account) or filters.
-- An entry is { strings = { ... } } holding any mix of them.
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

-- ElvUI strips install_complete from imported private settings, which would
-- reopen its install wizard after the reload. Mark this character installed.
local function MarkInstalled(E)
	if E.private then
		E.private.install_complete = E.version
	end
	local keys = ElvPrivateDB and ElvPrivateDB.profileKeys
	local key = keys and keys[E.mynameRealm]
	local stored = key and ElvPrivateDB.profiles and ElvPrivateDB.profiles[key]
	if stored then
		stored.install_complete = E.version
	end
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

		local imported, failed = {}, 0
		for _, str in ipairs(entry.strings or {}) do
			local dataType, dataKey, data = D:Decode(str)
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
			return false, "none of the ElvUI strings could be read"
		end

		MarkInstalled(E)
		-- We ask for one reload at the end, so drop ElvUI's own reload prompt.
		if E.StaticPopup_Hide then
			E:StaticPopup_Hide("IMPORT_RL")
		end

		local message = table.concat(imported, ", ")
		if failed > 0 then
			message = message .. (" (%d string(s) unreadable)"):format(failed)
		end
		return true, message
	end,
})
