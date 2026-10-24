local _, ns = ...
local UII = ns.UII

-- Details! strings come from Details > Options > Profiles > Export Profile.
-- An entry is { strings = { "<Details profile string>" } }.

local function GetDetails()
	local Details = Details or _detalhes
	if not (Details and Details.ImportProfile) then
		return nil, "Details! is not loaded."
	end
	return Details
end

UII:RegisterModule({
	key = "Details",
	title = "Details! Damage Meter",
	addon = "Details",
	order = 40,

	FromString = function(self, text)
		return { strings = { UII.SplitStrings(text)[1] } }
	end,

	Export = function(self)
		local D, err = GetDetails()
		if not D then
			return nil, err
		end
		local str = D:ExportCurrentProfile()
		if type(str) ~= "string" then
			return nil, "Details! couldn't export the current profile."
		end
		return { strings = { str } }
	end,

	Import = function(self, entry, ctx)
		local D, err = GetDetails()
		if not D then
			return false, err
		end
		local str = entry.strings and entry.strings[1]
		if not str then
			return false, "no Details! string in this pack"
		end

		local name = ctx.profileName
		if #name < 2 then
			name = name .. " Details"
		end
		-- (string, name, importAutoRunCode, isFromImportPrompt, overwriteExisting)
		-- Auto-run code stays off: it's Lua that would run on every login.
		if not D:ImportProfile(str, name, false, false, true) then
			return false, "Details! rejected the string"
		end
		return true, ("profile \"%s\""):format(name)
	end,
})
