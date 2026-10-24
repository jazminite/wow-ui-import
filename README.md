# UI Import

A World of Warcraft addon for **TBC Classic Anniversary** that sets up several addons from one import string.

Supported out of the box:

| Addon | What gets imported |
|---|---|
| ElvUI | profile, private (per-character) and global settings |
| Plater | profile (including its mods and scripts) |
| TipTac Reborn | settings |
| Details! Damage Meter | profile |

You can add more addons by writing a small module (see [Adding an addon](#adding-an-addon)).

## Install

Copy the `UIImport` folder into your AddOns folder:

```
World of Warcraft\_anniversary_\Interface\AddOns\UIImport
```

## Importing a pack

1. Type `/uii` (or `/uiimport`).
2. Paste a UI Import string (it starts with `!UII:1!`). The window lists the addons in the pack and whether each one is ready on this character.
3. Pick a profile name. Each addon gets a profile with that name. If a profile with that name already exists, it is replaced.
4. Untick anything you don't want, then click **Import Pack** and confirm.
5. Reload when asked.

Addons that aren't installed or enabled are skipped, and the rest still import. You can install the missing addon later and import the same string again.

The import also marks ElvUI as installed on the character, so ElvUI's install wizard doesn't open after the reload.

## Making a pack

Type `/uii build`. For each addon you tick, you can:

- **leave its box empty** to use this character's current settings, or
- **paste that addon's own export string** into the box (for example a string from Wago). For ElvUI you can paste several strings (profile, private, global) separated by spaces or new lines.

Click **Create String**, click the result and press Ctrl+C.

To ship a pack with the addon itself, add it to `UIImport/Packs.lua`. It then shows up as a one-click button in the import window:

```lua
UII:RegisterPack("Jazminite's UI", "!UII:1!...")
```

### Where each addon's own export string comes from

| Addon | Where to find its export |
|---|---|
| ElvUI | `/ec` → Profiles → Export Profile, using the **Text** format (the string starts with `!E2!`) |
| Plater | `/plater` → Profiles → Export Profile |
| TipTac Reborn | `/tiptac` → Profiles → Export Settings |
| Details! | `/details options` → Profiles → Export Profile |

## Commands

| Command | Does |
|---|---|
| `/uii` | open the import window |
| `/uii build` | open the pack builder |
| `/uii status` | list the supported addons and whether each is loaded |

## Safety

Import strings hold only data. UI Import never runs code from them. Some of the addons do run code from their own settings, though. Plater mods and scripts are Lua that Plater runs, so **only import packs from people you trust**. Details! "auto-run code" is always dropped on import.

## Adding an addon

Create `UIImport/Modules/YourAddon.lua`, add it to `UIImport.toc` before `Packs.lua`, and register a module:

```lua
local _, ns = ...
local UII = ns.UII

UII:RegisterModule({
	key = "Bartender4",   -- name stored in import strings; never change it later
	title = "Bartender4", -- shown in the window
	addon = "Bartender4", -- the addon's folder name, used to check it's loaded
	order = 50,           -- lower numbers import first

	-- Optional: turn the addon's own export string into an entry.
	-- Without this the text is stored as { strings = { text } }.
	FromString = function(self, text)
		return { strings = { text } }
	end,

	-- Optional: build an entry from this character's current settings.
	Export = function(self, ctx)
		return { strings = { Bartender4:SomeExportFunction() } }
	end,

	-- Required: apply an entry. ctx.profileName is the name the user picked.
	-- Return true plus a short summary, or false plus the reason it failed.
	Import = function(self, entry, ctx)
		local ok = Bartender4:SomeImportFunction(entry.strings[1], ctx.profileName)
		return ok, ok and ("profile \"%s\""):format(ctx.profileName) or "import failed"
	end,
})
```

An entry can be any plain data (strings, numbers, booleans and tables). If an addon has no export string of its own, return its settings table directly, for example `{ data = CopyTable(MyAddonDB) }`. Errors thrown inside `Import` are caught and shown as a failed row, and the other addons still import.

Other addons can register modules too, through the global `UIImport:RegisterModule(...)`.

## Import string format

```
!UII:1!<Base64(Deflate(CBOR(pack)))>
```

The string is built with the game's `C_EncodingUtil`, the same API ElvUI and Plater use. Clients without it fall back to LibSerialize plus LibDeflate, and those strings start with `!UII:1L!` instead. The decoded pack looks like this:

```lua
{
  uii = 1, name = "My UI", author = "Me", created = 1700000000, build = 20506,
  addons = {
    ElvUI   = { strings = { "!E2!...", "!E2!...", "!E2!..." } },
    Plater  = { strings = { "!PLATER:2!..." } },
    TipTac  = { strings = { "..." } },
    Details = { strings = { "..." } },
  },
}
```

Each module stores the addon's own export string, so the addon itself decodes it and handles version upgrades.

## Tests

The logic runs outside the game against mocked WoW and addon APIs:

```bash
lua5.1 tests/run.lua
```

Without a Lua install:

```bash
python -m pip install lupa
python tests/run_with_lupa.py
```

The tests check the import, export and build logic and the calls made to each addon's API. They can't check how the window looks or how the real addons behave, so test in game too.
