package.path = "gen1recomp/?.lua;gen1recomp/?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local Options = require("src.core.game3.options")

local previousVersion = GameVersion.get()
GameVersion.set("emerald")
Profile.reset()

local run = T.sdk.loadMod(os.getenv("EXP_QOL_MOD_PATH") or "mods/exp_qol", {
  data = T.sdk.gen3Data(),
  generation = 3,
})
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

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
end

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