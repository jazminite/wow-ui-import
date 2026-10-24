-- Runs UI Import's logic against mocked WoW/addon APIs.
-- Usage (from the repo root): lua5.1 tests/run.lua
--   or, without a Lua install: python tests/run_with_lupa.py

local realPrint = print
package.path = "./tests/?.lua;" .. package.path
local mocks = require("mocks")

local ADDON_DIR = "UIImport/"
local TOC_FILES = {}
for line in io.lines(ADDON_DIR .. "UIImport.toc") do
	line = line:gsub("%s+$", "")
	if line ~= "" and not line:find("^#") then
		TOC_FILES[#TOC_FILES + 1] = line:gsub("\\", "/")
	end
end

local passed, failed = 0, 0

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		realPrint("ok    " .. name)
	else
		failed = failed + 1
		realPrint("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end

local function eq(actual, expected, label)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label or "value", tostring(expected), tostring(actual)), 2)
	end
end

-- Fresh game state + addon load for every test.
local function boot(opts)
	opts = opts or {}
	for _, key in ipairs({ "ElvUI", "ElvPrivateDB", "Plater", "PLATER_DEFAULT_SETTINGS", "Details", "TipTac", "LibStub", "UIImport", "UIImportDB", "UIImportFrame" }) do
		_G[key] = nil
	end
	mocks.widgets, mocks.popups = {}, {}
	mocks.reset()
	mocks.installWoW()
	local libs = mocks.installLibStub()
	if opts.elvui ~= false then mocks.installElvUI() end
	if opts.plater ~= false then mocks.installPlater() end
	if opts.details ~= false then mocks.installDetails() end
	if opts.tiptac ~= false then mocks.installTipTac(libs) end

	local ns = {}
	for _, file in ipairs(TOC_FILES) do
		local chunk = assert(loadfile(ADDON_DIR .. file))
		chunk("UIImport", ns)
	end
	-- ADDON_LOADED
	for _, widget in ipairs(mocks.widgets) do
		widget:Fire("OnEvent", "ADDON_LOADED", "UIImport")
	end
	return ns.UII
end

local function buildFromCurrent(UII, name)
	local sources = {}
	for _, module in ipairs(UII:GetModules()) do
		sources[module.key] = { text = "" }
	end
	return UII:BuildPack({ name = name or "Test UI", author = "Me", sources = sources })
end

--------------------------------------------------------------------------------

test("toc lists every lua file and they all load", function()
	local UII = boot()
	eq(type(UII), "table", "UII")
	eq(_G.UIImport, UII, "global API")
	eq(#UII:GetModules(), 4, "module count")
	eq(type(UIImportDB), "table", "saved variables")
end)

test("modules are sorted by order", function()
	local UII = boot()
	local keys = {}
	for _, module in ipairs(UII:GetModules()) do
		keys[#keys + 1] = module.key
	end
	eq(table.concat(keys, ","), "ElvUI,Plater,TipTac,Details", "order")
end)

test("codec round-trips and ignores whitespace/newlines", function()
	local UII = boot()
	local text = UII.Codec.Encode({ uii = 1, addons = {}, name = "Spaced name" })
	eq(text:sub(1, 7), "!UII:1!", "prefix")
	local wrapped = "  " .. text:sub(1, 20) .. "\n" .. text:sub(21) .. "\n"
	local pack = assert(UII:ReadPack(wrapped))
	eq(pack.name, "Spaced name", "name")
end)

test("codec falls back to LibSerialize/LibDeflate without C_EncodingUtil", function()
	local UII = boot()
	_G.C_EncodingUtil = nil
	local text = UII.Codec.Encode({ uii = 1, addons = {}, name = "Libs" })
	eq(text:sub(1, 8), "!UII:1L!", "prefix")
	eq(assert(UII:ReadPack(text)).name, "Libs", "name")
end)

test("wrong strings get helpful errors", function()
	local UII = boot()
	local _, err = UII:ReadPack("")
	assert(err:find("Paste"), err)
	_, err = UII:ReadPack("!E2!abcdef")
	assert(err:find("ElvUI string"), err)
	_, err = UII:ReadPack("hello")
	assert(err:find("isn't a UI Import string"), err)
	_, err = UII:ReadPack("!UII:1!!!!notbase64")
	assert(err, "damaged string should fail")
	_, err = UII:ReadPack(UII.Codec.Encode({ hello = true }))
	assert(err:find("isn't a UI Import pack"), err)
	_, err = UII:ReadPack(UII.Codec.Encode({ uii = 99, addons = {} }))
	assert(err:find("newer version"), err)
end)

test("build from current settings covers all four addons", function()
	local UII = boot()
	local text, report = buildFromCurrent(UII)
	assert(text, "no text")
	for _, line in ipairs(report) do
		eq(line.status, "ok", line.title .. " (" .. tostring(line.message) .. ")")
	end
	local pack = assert(UII:ReadPack(text))
	eq(#pack.addons.ElvUI.strings, 3, "ElvUI profile+private+global")
	eq(pack.addons.Details.strings[1], "DetailsString123", "Details string")
	assert(pack.addons.Plater.strings[1]:find("^!PLATER:2!"), "Plater string")
	assert(pack.addons.TipTac.strings[1], "TipTac string")
	eq(pack.build, 20506, "build")
	eq(pack.author, "Me", "author")
end)

test("plater export drops caches but keeps names used by colors", function()
	local UII = boot()
	local text = buildFromCurrent(UII)
	local pack = assert(UII:ReadPack(text))
	local profile = Plater.DecompressData(pack.addons.Plater.strings[1])
	assert(profile.npc_cache[101], "colored NPC kept")
	assert(not profile.npc_cache[102], "other cache dropped")
	assert(not next(profile.hook_data[1].HooksTemp), "HooksTemp cleared")
	eq(profile.profile_name, "Default", "profile_name")
	assert(Plater.db.profile.hook_data[1].HooksTemp.junk, "live profile untouched")
end)

test("import calls each addon with the chosen profile name", function()
	local UII = boot()
	local pack = assert(UII:ReadPack((buildFromCurrent(UII))))
	mocks.reset()
	local results = UII:ImportPack(pack, { profileName = "  Raid UI  " })
	for _, result in ipairs(results) do
		eq(result.status, "ok", result.title .. " (" .. tostring(result.message) .. ")")
	end

	local elv = mocks.find("ElvUI.SetImportedProfile")
	eq(#elv, 3, "ElvUI imports")
	eq(elv[1].args[1], "profile", "type")
	eq(elv[1].args[2], "Raid UI", "trimmed profile name")
	eq(elv[1].args[4], true, "force overwrite")
	eq(elv[2].args[1], "private", "private type")
	eq(ElvUI[1].private.install_complete, 99.9, "installer skipped (live)")
	eq(ElvPrivateDB.profiles["Tester - Realm"].install_complete, 99.9, "installer skipped (stored)")
	eq(#mocks.find("ElvUI.StaticPopup_Hide"), 1, "ElvUI reload popup hidden")

	local plater = mocks.find("Plater.ImportAndSwitchProfile")[1]
	eq(plater.args[1], "Raid UI", "Plater name")
	assert(plater.args[2].plate_config, "Plater profile table")
	eq(plater.args[2].profile_name, nil, "profile_name stripped")
	assert(plater.args[2].spell_animation_list, "spell animations defaulted")
	eq(plater.args[5], true, "Plater doNotReload")

	eq(mocks.find("TipTac.configDb.SetProfile")[1].args[1], "Raid UI", "TipTac profile")
	eq(mocks.find("TipTac.MixinWholeObjects")[1].args[2].fontSize, 12, "TipTac settings")
	eq(#mocks.find("TipTac.ApplyConfig"), 1, "TipTac applied")

	local details = mocks.find("Details.ImportProfile")[1]
	eq(details.args[1], "DetailsString123", "Details string")
	eq(details.args[2], "Raid UI", "Details name")
	eq(details.args[3], false, "Details auto-run code off")
	eq(details.args[5], true, "Details overwrite")

	eq(UIImportDB.lastImport.profileName, "Raid UI", "history")
end)

test("profile name defaults to the pack name", function()
	local UII = boot()
	local pack = assert(UII:ReadPack((buildFromCurrent(UII, "Cozy UI"))))
	UII:ImportPack(pack, { profileName = "" })
	eq(mocks.find("Plater.ImportAndSwitchProfile")[1].args[1], "Cozy UI", "name")
end)

test("missing addons and unknown modules are skipped, not failed", function()
	local UII = boot()
	local pack = assert(UII:ReadPack((buildFromCurrent(UII))))
	pack.addons.WeakAuras = { strings = { "x" } }

	UII = boot({ plater = false })
	local byKey = {}
	for _, result in ipairs(UII:ImportPack(pack, {})) do
		byKey[result.key] = result
	end
	eq(byKey.Plater.status, "skipped", "Plater status")
	eq(byKey.Plater.message, "not installed", "Plater reason")
	eq(byKey.WeakAuras.status, "skipped", "unknown status")
	assert(byKey.WeakAuras.message:find("no module"), byKey.WeakAuras.message)
	eq(byKey.ElvUI.status, "ok", "ElvUI still imports")
end)

test("only selected addons import", function()
	local UII = boot()
	local pack = assert(UII:ReadPack((buildFromCurrent(UII))))
	mocks.reset()
	UII:ImportPack(pack, { selected = { Details = true } })
	eq(#mocks.find("ElvUI.SetImportedProfile"), 0, "ElvUI skipped")
	eq(#mocks.find("Details.ImportProfile"), 1, "Details imported")
end)

test("an error inside a module is reported, others continue", function()
	local UII = boot()
	local pack = assert(UII:ReadPack((buildFromCurrent(UII))))
	Plater.ImportAndSwitchProfile = function()
		error("boom")
	end
	local byKey = {}
	for _, result in ipairs(UII:ImportPack(pack, {})) do
		byKey[result.key] = result
	end
	eq(byKey.Plater.status, "failed", "Plater status")
	assert(byKey.Plater.message:find("boom"), byKey.Plater.message)
	eq(byKey.Details.status, "ok", "Details still ran")
end)

test("pasted addon strings are used instead of current settings", function()
	local UII = boot()
	local text, report = UII:BuildPack({
		name = "Pasted",
		sources = {
			ElvUI = { text = "!E2!profile:Theirs\n\n!E2!private:" },
			Details = { text = "  OtherDetails  " },
		},
	})
	assert(text, report[1] and report[1].message)
	local pack = assert(UII:ReadPack(text))
	eq(#pack.addons.ElvUI.strings, 2, "two ElvUI strings")
	eq(pack.addons.Details.strings[1], "OtherDetails", "trimmed Details string")
	eq(pack.addons.Plater, nil, "unticked addon left out")
end)

test("bad pasted strings are rejected at build time", function()
	local UII = boot()
	local text, report = UII:BuildPack({
		sources = {
			ElvUI = { text = "not an elvui string" },
			Plater = { text = "!PLATER:2!" .. mocks.pack({ notAProfile = true }) },
		},
	})
	eq(text, nil, "no string when nothing is valid")
	for _, line in ipairs(report) do
		eq(line.status, "failed", line.title)
	end
end)

test("custom modules plug in and round-trip", function()
	local UII = boot()
	local received
	UIImport:RegisterModule({
		key = "MyAddon",
		order = 5,
		Export = function()
			return { data = { scale = 1.5 } }
		end,
		Import = function(self, entry, ctx)
			received = entry.data.scale
			return true, "ok"
		end,
	})
	eq(UII:GetModules()[1].key, "MyAddon", "sorted first")
	assert(not pcall(UIImport.RegisterModule, UIImport, { key = "MyAddon", Import = function() end }), "duplicate rejected")

	local pack = assert(UII:ReadPack((buildFromCurrent(UII))))
	UII:ImportPack(pack, {})
	eq(received, 1.5, "custom data")
end)

test("ui: paste, read, confirm, import, reload prompt", function()
	local UII = boot()
	local text = buildFromCurrent(UII, "Window UI")
	UII:ShowWindow("import")
	eq(UIImportFrame.shown, true, "window shown")

	local input = mocks.findWidget(function(w)
		return w.kind == "EditBox" and w.multiLine
	end)
	local importButton = mocks.findButton("Import Pack")
	eq(importButton.enabled, false, "import disabled before paste")

	input:Type(text)
	eq(importButton.enabled, true, "import enabled after paste")

	mocks.reset()
	importButton:Click()
	local confirm = mocks.popups[#mocks.popups]
	eq(confirm.name, "UIIMPORT_CONFIRM", "confirm popup")
	assert(confirm.text:find("4 addon"), confirm.text)
	eq(#mocks.find("Details.ImportProfile"), 0, "nothing imported before confirming")

	StaticPopupDialogs.UIIMPORT_CONFIRM.OnAccept(nil, confirm.data)
	eq(#mocks.find("Details.ImportProfile"), 1, "imported after confirming")
	eq(mocks.find("Plater.ImportAndSwitchProfile")[1].args[1], "Window UI", "profile name from pack")
	eq(mocks.popups[#mocks.popups].name, "UIIMPORT_RELOAD", "reload prompt")
end)

test("ui: build tab creates a string", function()
	local UII = boot()
	UII:ShowWindow("build")
	mocks.findButton("Create String"):Click()
	local output = mocks.findWidget(function(w)
		return w.kind == "EditBox" and w.multiLine and (w.value or ""):find("^!UII:1!")
	end)
	assert(output, "output box holds the string")
	assert(UII:ReadPack(output.value), "string reads back")
end)

test("slash commands open the window", function()
	local UII = boot()
	SlashCmdList.UIIMPORT("build")
	eq(UIImportFrame.shown, true, "shown")
	SlashCmdList.UIIMPORT("status")
end)

realPrint(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	os.exit(1)
end
