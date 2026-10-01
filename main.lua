local MULTIPLIERS = { 1, 2, 5, 10, 100 }
local OPTION_KEY = "expQolMultiplier"
local ROW_ID = "expQolMultiplier"
local Options = require("src.core.game3.options")
local Rows = require("src.ui.game3.option_rows")
local Runtime = require("src.mods.Runtime")

local function multiplier(options)
  local value = tonumber(options and options[OPTION_KEY])
  for _, allowed in ipairs(MULTIPLIERS) do
    if value == allowed then return value end
  end
  return 1
end

local function optionsFor(ctx)
  if not ctx or type(ctx.options) ~= "table" then return nil end
  return Options.block(ctx.options, Options.blockId(ctx.session))
end

local function rowIndex(value)
  for index, allowed in ipairs(MULTIPLIERS) do
    if value == allowed then return index end
  end
  return 1
end

local function installed()
  local chains = Runtime.hooks and Runtime.hooks.chains
  for _, hook in ipairs(chains and chains["exp.gain"] or {}) do
    if hook.owner == "exp_qol" then return true end
  end
  return false
end

return function(mod)
  local battleGroup
  for _, group in ipairs(Rows.GROUPS) do
    if group.id == "group.battle" then battleGroup = group end
  end
  if battleGroup then
    local found = false
    for _, id in ipairs(battleGroup.members) do
      if id == ROW_ID then found = true end
    end
    if not found then battleGroup.members[#battleGroup.members + 1] = ROW_ID end
  end

  if not Rows._expQolOriginalBuild then
    Rows._expQolOriginalBuild = Rows.build
    Rows.build = function(ctx)
      local out = Rows._expQolOriginalBuild(ctx)
      if not installed() then return out end
      for _, row in ipairs(out) do
        if row.id == ROW_ID then return out end
      end
      out[#out + 1] = {
        id = ROW_ID,
        label = "EXP. MULT.",
        value = function(c)
          return tostring(multiplier(optionsFor(c))) .. "x"
        end,
        step = function(c, direction)
          local options = optionsFor(c)
          if not options then return false end
          local current = rowIndex(multiplier(options))
          local delta = direction and direction < 0 and -1 or 1
          local nextIndex = (current - 1 + delta) % #MULTIPLIERS + 1
          options[OPTION_KEY] = MULTIPLIERS[nextIndex]
          return true
        end,
      }
      return out
    end
  end

  mod.hooks:wrap("exp.gain", function(next, ctx)
    local amount = next(ctx)
    local battle = ctx and ctx.battle
    local session = battle and battle.session
    local rate = multiplier(session and session.options)
    if type(amount) ~= "number" or rate == 1 then return amount end
    return math.floor(amount * rate)
  end)
end