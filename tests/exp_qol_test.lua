local engineRoot = os.getenv("GEN1RECOMP_ROOT") or "gen1recomp"
package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local Options = require("src.core.game3.options")
local Experience = require("src.core.game3.battle.experience")

-- Pokemon.speciesMeta reads a ROM-imported cache file this fixture never
-- populates; stub the one foe species this suite uses so expYield is
-- deterministic without a ROM import.
local originalExpYield = Experience.expYield
Experience.expYield = function(species)
  if tonumber(species) == 29 then return 59 end
  return originalExpYield(species)
end

local previousVersion = GameVersion.get()
GameVersion.set("emerald")
Profile.reset()

local modPath = os.getenv("EXP_QOL_MOD_PATH") or "mods/exp_qol"
local run = T.sdk.loadMod(modPath, {
  root = modPath:sub(1, 1) == "/" and "/" or nil,
  data = T.sdk.gen3Data(),
  generation = 3,
})
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.check(run.mod ~= nil, "the SDK loader discovers this mod path")

local session = { version = "emerald" }
local game = {
  options = {},
  session = session,
  writes = 0,
  writeOptions = function(self) self.writes = self.writes + 1 end,
}
Options.bind(session, game.options)

local OptionMenu = require("src.ui.game3.rse.option_menu")
local Rows = require("src.ui.game3.option_rows")
Rows._expQolOriginalBuild = function()
  return { { id = "battleScene" }, { id = "battleStyle" } }
end

local context = { options = game.options, session = session, game = game }
local builtRows = Rows.build(context)
local pages = {}
local root = Rows.group(builtRows, function(title, members)
  pages[#pages + 1] = { title = title, rows = members, index = 1, scroll = 0 }
end)
local battleGroup
for _, row in ipairs(root) do
  if row.id == "group.battle" then battleGroup = row end
end
T.check(battleGroup ~= nil, "BATTLE OPTIONS remains in the Emerald options menu")

if battleGroup then
  battleGroup.activate(context)
  local battlePage = pages[1]
  local expRow, expIndex
  for index, row in ipairs(battlePage.rows) do
    if row.id == "expQolMultiplier" then
      expRow, expIndex = row, index
    end
  end
  T.check(expRow ~= nil, "EXP. MULT. is inside BATTLE OPTIONS")

  if expRow then
    T.eq(expRow.value(game), "1x", "the default EXP rate is 1x")

    local function pressed(button)
      return { wasPressed = function(_, key) return key == button end }
    end
    OptionMenu._st.ctx = context
    OptionMenu._st.pages = { battlePage }
    battlePage.index = expIndex
    for _, rate in ipairs({ 2, 5, 10, 100, 1 }) do
      OptionMenu.handleInput(pressed("right"))
      T.eq(expRow.value(game), tostring(rate) .. "x", "right selects " .. rate .. "x")
    end
    OptionMenu.handleInput(pressed("left"))
    T.eq(expRow.value(game), "100x", "left selects the previous rate")

    local gained = Runtime.call("exp.gain", function() return 12 end, {
      battle = { session = session },
    })
    T.eq(gained, 1200, "the selected rate multiplies Emerald battle EXP")
    T.eq(game.writes, 6, "each selector change persists game options")
  end

  local shareRow, shareIndex
  for index, row in ipairs(battlePage.rows) do
    if row.id == "expQolShareMode" then
      shareRow, shareIndex = row, index
    end
  end
  T.check(shareRow ~= nil, "EXP SHARE is inside BATTLE OPTIONS")

  if shareRow then
    T.eq(shareRow.value(game), "OFF", "the default Exp Share mode is OFF")

    local function pressed(button)
      return { wasPressed = function(_, key) return key == button end }
    end
    OptionMenu._st.pages = { battlePage }
    battlePage.index = shareIndex
    for _, label in ipairs({ "OLD SCHOOL", "MODERN", "FULL", "BALANCE", "OFF" }) do
      OptionMenu.handleInput(pressed("right"))
      T.eq(shareRow.value(game), label, "right selects " .. label)
    end
    OptionMenu.handleInput(pressed("left"))
    T.eq(shareRow.value(game), "BALANCE", "left selects the previous mode")

    -- Direct math checks: a level 10 battler plus two bench mons (level 5
    -- and level 50) against a level 10 foe (expYield 59, calculated = 84).
    -- These call the exp.gain hook directly, mirroring the engine's own
    -- payload shape, since Experience.awardFoe needs a ROM-imported species
    -- name pack this fixture does not provide.
    game.options["expQolMultiplier"] = nil
    session.options["expQolMultiplier"] = nil
    local party = {
      { species = 4, level = 10, hp = 30, maxHp = 30 },
      { species = 4, level = 5, hp = 20, maxHp = 20 },
      { species = 4, level = 50, hp = 90, maxHp = 90 },
    }

    local function vanillaStub() return 999 end

    local function ctxFor(mode, partyIndex)
      session.options["expQolShareMode"] = mode
      return {
        battle = { playerParty = party, session = session, player = { partyIndex = 1 } },
        loser = { species = 29, level = 10 },
        level = 10,
        index = partyIndex,
        mon = party[partyIndex],
      }
    end

    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("off", 1)), 999,
      "OFF leaves the vanilla amount untouched")

    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("old_school", 1)), 98,
      "Old School: battler keeps its split plus the bonus share")
    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("old_school", 2)), 14,
      "Old School: bench gets only the bonus share")
    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("old_school", 3)), 14,
      "Old School: every bench slot gets the same bonus share")

    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("modern", 1)), 84,
      "Modern: the battler keeps the full amount")
    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("modern", 2)), 42,
      "Modern: the bench gets a flat half share")
    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("modern", 3)), 42,
      "Modern: every bench slot gets the same half share")

    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("full", 1)), 84,
      "Full: the battler gets the full amount")
    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("full", 2)), 84,
      "Full: the bench also gets the full amount")
    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("full", 3)), 84,
      "Full: every eligible slot gets the full amount")

    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("balance", 1)), 32,
      "Balance: the level 10 battler's weighted share")
    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("balance", 2)), 33,
      "Balance: the level 5 bench mon gets the largest share")
    T.eq(Runtime.call("exp.gain", vanillaStub, ctxFor("balance", 3)), 17,
      "Balance: the level 50 bench mon gets the smallest share")

    session.options["expQolShareMode"] = nil
  end
end

Experience.expYield = originalExpYield

OptionMenu.reset()
run.release()
local unloadedRows = Rows.build({ options = game.options, session = session })
local rowRemains = false
for _, row in ipairs(unloadedRows) do
  if row.id == "expQolMultiplier" then rowRemains = true end
end
T.eq(rowRemains, false, "the menu row is hidden when the mod unloads")
GameVersion.set(previousVersion)
Profile.reset()
T.finish("exp_qol")