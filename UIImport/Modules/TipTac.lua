local _, ns = ...
local UII = ns.UII

-- TipTac Reborn strings come from /tiptac > Profiles > Export Settings.
-- They are LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(LibSerialize(cfg))).
-- An entry is { strings = { "<TipTac settings string>" } }.

local function GetTipTac()
	if not (TipTac and TipTac.ApplyConfig and LibStub) then
		return nil, "TipTac is not loaded."
	end
	local LibFroznFunctions = LibStub("LibFroznFunctions-1.0", true)
	if not LibFroznFunctions then
		return nil, "TipTac's LibFroznFunctions library is missing."
	end
	-- Returns TipTac's existing AceDB object and its live config table.
	local configDb, cfg = LibFroznFunctions:CreateDbWithLibAceDB("TipTac_Config")
	return TipTac, LibFroznFunctions, configDb, cfg
end

-- TipTac only embeds LibSerialize/LibDeflate in its load-on-demand options addon.
local function GetCodecLibs()
	local LibSerialize = LibStub("LibSerialize", true)
	local LibDeflate = LibStub("LibDeflate", true)
	if not (LibSerialize and LibDeflate) then
		UII.LoadAddOn("TipTacOptions")
		LibSerialize = LibStub("LibSerialize", true)
		LibDeflate = LibStub("LibDeflate", true)
	end
	if not (LibSerialize and LibDeflate) then
		return nil, "LibSerialize/LibDeflate not found (is TipTacOptions installed?)"
	end
	return LibSerialize, LibDeflate
end

local function DecodeSettings(str)
	local LibSerialize, LibDeflate = GetCodecLibs()
	if not LibSerialize then
		return nil, LibDeflate
	end
	local compressed = LibDeflate:DecodeForPrint(str)
	local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
	if not serialized then
		return nil, "the TipTac string could not be read"
	end
	local ok, settings = LibSerialize:Deserialize(serialized)
	if not ok or type(settings) ~= "table" then
		return nil, "the TipTac string could not be read"
	end
	return settings
end

UII:RegisterModule({
	key = "TipTac",
	title = "TipTac Reborn",
	addon = "TipTac",
	order = 30,

	FromString = function(self, text)
		local str = UII.SplitStrings(text)[1]
		if LibStub and GetCodecLibs() then
			local settings, err = DecodeSettings(str)
			if not settings then
				return nil, err
			end
		end
		return { strings = { str } }
	end,

	Export = function(self)
		local _, _, _, cfg = GetTipTac()
		if not cfg then
			return nil, "TipTac is not loaded."
		end
		local LibSerialize, LibDeflate = GetCodecLibs()
		if not LibSerialize then
			return nil, LibDeflate
		end
		-- Matches TipTac's own Export Settings button.
		local serialized = LibSerialize:Serialize(cfg.__GetLinkedTable)
		return { strings = { LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(serialized)) } }
	end,

	Import = function(self, entry, ctx)
		local tiptac, LibFroznFunctions, configDb, cfg = GetTipTac()
		if not tiptac then
			return false, LibFroznFunctions
		end

		local str = entry.strings and entry.strings[1]
		local settings, err = DecodeSettings(str or "")
		if not settings then
			return false, err
		end

		-- Same steps as TipTac's Import Settings button, on a profile of our own.
		configDb:SetProfile(ctx.profileName)
		LibFroznFunctions:MixinWholeObjects(cfg, settings)
		tiptac:ApplyConfig()
		return true, ("profile \"%s\""):format(ctx.profileName)
	end,
})
