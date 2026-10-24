local _, ns = ...
local UII = ns.UII

--[[
Import string format:

  "!UII:1!"  .. Base64( Deflate( CBOR(pack) ) )     using C_EncodingUtil
  "!UII:1L!" .. LibDeflate:EncodeForPrint( LibDeflate:Compress( LibSerialize(pack) ) )

C_EncodingUtil is the normal path (ElvUI and Plater use it on TBC Anniversary
too). The LibSerialize/LibDeflate path is only a fallback for clients without
it. Both decode to plain data only; nothing in an import string is executed.
]]

local Codec = {}
UII.Codec = Codec

local PREFIX_NATIVE = "!UII:1!"
local PREFIX_LIBS = "!UII:1L!"

local function GetNative()
	local EU = C_EncodingUtil
	if EU and EU.SerializeCBOR and EU.CompressString and EU.EncodeBase64 then
		return EU
	end
end

local function GetLibs()
	if not LibStub then
		return
	end
	local LibSerialize = LibStub("LibSerialize", true)
	local LibDeflate = LibStub("LibDeflate", true)
	if LibSerialize and LibDeflate then
		return LibSerialize, LibDeflate
	end
end

local function CompressionMethod()
	return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
end

local function CompressionLevel()
	local levels = Enum and Enum.CompressionLevel
	return levels and (levels.OptimizeForSize or levels.Default) or 0
end

function Codec.Encode(value)
	local EU = GetNative()
	if EU then
		local ok, result = pcall(function()
			local serialized = EU.SerializeCBOR(value)
			local compressed = EU.CompressString(serialized, CompressionMethod(), CompressionLevel())
			return PREFIX_NATIVE .. EU.EncodeBase64(compressed)
		end)
		if ok then
			return result
		end
		return nil, "Couldn't encode the pack: " .. tostring(result)
	end

	local LibSerialize, LibDeflate = GetLibs()
	if LibSerialize then
		local serialized = LibSerialize:Serialize(value)
		return PREFIX_LIBS .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(serialized))
	end
	return nil, "This client has no C_EncodingUtil and no LibSerialize/LibDeflate is loaded."
end

-- Names the addon an export string probably belongs to, so a wrong paste can
-- get a helpful message instead of "invalid string".
function Codec.Identify(text)
	if text:find("^!UII:") then
		return "UIImport"
	elseif text:find("^!E%d+!") then
		return "ElvUI"
	elseif text:find("^!PLATER") then
		return "Plater"
	elseif text:find("^!WA:") then
		return "WeakAuras"
	end
end

local function DecodeNative(body)
	local EU = GetNative()
	if not EU then
		return nil, "This client has no C_EncodingUtil, so it can't read this string."
	end
	local ok, result = pcall(function()
		local compressed = EU.DecodeBase64(body)
		local serialized = EU.DecompressString(compressed, CompressionMethod())
		return EU.DeserializeCBOR(serialized)
	end)
	if not ok or result == nil then
		return nil, "The string is damaged or incomplete. Copy it again and make sure you got all of it."
	end
	return result
end

local function DecodeLibs(body)
	local LibSerialize, LibDeflate = GetLibs()
	if not LibSerialize then
		return nil, "Reading this string needs LibSerialize and LibDeflate, and neither is loaded."
	end
	local compressed = LibDeflate:DecodeForPrint(body)
	local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
	if not serialized then
		return nil, "The string is damaged or incomplete. Copy it again and make sure you got all of it."
	end
	local ok, result = LibSerialize:Deserialize(serialized)
	if not ok then
		return nil, "The string is damaged or incomplete. Copy it again and make sure you got all of it."
	end
	return result
end

function Codec.Decode(text)
	if type(text) ~= "string" then
		return nil, "Nothing to import."
	end
	text = text:gsub("%s+", "")
	if text == "" then
		return nil, "Paste an import string first."
	end

	local body = text:match("^" .. PREFIX_NATIVE:gsub("%p", "%%%0") .. "(.+)$")
	if body then
		return DecodeNative(body)
	end
	body = text:match("^" .. PREFIX_LIBS:gsub("%p", "%%%0") .. "(.+)$")
	if body then
		return DecodeLibs(body)
	end

	local owner = Codec.Identify(text)
	if owner and owner ~= "UIImport" then
		return nil, ("That looks like a %s string. Import it in %s, or add it to a pack with /uii build."):format(owner, owner)
	end
	return nil, "That isn't a UI Import string (they start with " .. PREFIX_NATIVE .. ")."
end
