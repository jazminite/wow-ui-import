local _, ns = ...
local UII = ns.UII

-- Plater profile strings come from Plater > Profiles > Export Profile.
-- An entry is { strings = { "<Plater profile string>" } }.

local function GetPlater()
	if not (Plater and Plater.db and Plater.DecompressData) then
		return nil, "Plater is not loaded."
	end
	return Plater
end

-- Same clean-up Plater's own "Export Profile" button does: drop caches that
-- are rebuilt at run time, but keep NPC names that colors/renames refer to.
local function PrepareProfileForExport(Plater)
	local current = Plater.db.profile
	local profile = CopyTable(current)

	profile.npc_cache = {}
	profile.saved_cvars_last_change = {}
	profile.script_data_trash = {}
	profile.hook_data_trash = {}
	profile.plugins_data = {}
	profile.captured_spells = {}
	profile.captured_casts = {}

	local npcCache = current.npc_cache or {}
	for npcID in pairs(profile.npc_colors or {}) do
		profile.npc_cache[npcID] = npcCache[npcID]
	end
	for npcID in pairs(profile.npcs_renamed or {}) do
		profile.npc_cache[npcID] = npcCache[npcID]
	end
	for _, hook in ipairs(profile.hook_data or {}) do
		hook.HooksTemp = {}
	end

	profile.profile_name = Plater.db:GetCurrentProfile()
	profile.tocversion = select(4, GetBuildInfo())
	return profile
end

UII:RegisterModule({
	key = "Plater",
	title = "Plater",
	addon = "Plater",
	order = 20,

	FromString = function(self, text)
		local str = UII.SplitStrings(text)[1]
		local P = GetPlater()
		if P then
			local profile = P.DecompressData(str, "print", true)
			if type(profile) ~= "table" or not profile.plate_config then
				return nil, "that isn't a Plater profile string (mod and script strings aren't supported)"
			end
		end
		return { strings = { str } }
	end,

	Export = function(self)
		local P, err = GetPlater()
		if not P then
			return nil, err
		end
		local str = P.CompressData(PrepareProfileForExport(P), "print")
		if not str then
			return nil, "Plater couldn't compress the profile."
		end
		return { strings = { str } }
	end,

	Import = function(self, entry, ctx)
		local P, err = GetPlater()
		if not P then
			return false, err
		end

		local str = entry.strings and entry.strings[1]
		local profile = str and P.DecompressData(str, "print", true)
		if type(profile) ~= "table" or not profile.plate_config then
			return false, "the Plater string could not be read"
		end

		local defaults = PLATER_DEFAULT_SETTINGS and PLATER_DEFAULT_SETTINGS.profile
		if not profile.spell_animation_list and defaults and defaults.spell_animation_list then
			profile.spell_animation_list = CopyTable(defaults.spell_animation_list)
		end
		profile.profile_name = nil

		local name = ctx.profileName
		if P.ImportAndSwitchProfile then
			-- (name, profile, isUpdate, keepModsNotInUpdate, doNotReload)
			P.ImportAndSwitchProfile(name, profile, false, false, true)
		else
			-- Older Plater without the import helper.
			P.db:SetProfile(name)
			P.db:ResetProfile(false, true)
			for key, value in pairs(profile) do
				P.db.profile[key] = value
			end
		end
		return true, ("profile \"%s\""):format(name)
	end,
})
