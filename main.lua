local MULTIPLIERS = { 1, 2, 5, 10, 100 }
local OPTION_KEY = "expQolMultiplier"
local ROW_ID = "expQolMultiplier"
local Options = require("src.core.game3.options")
local Rows = require("src.ui.game3.option_rows")
local Runtime = require("src.mods.Runtime")
local Experience = require("src.core.game3.battle.experience")

-- OFF leaves vanilla's own held-item Exp Share untouched; every other mode
-- widens the recipient set to the whole eligible party (eligiblePartyIndices)
-- and computes its own per-recipient share in the exp.gain hook below.
local SHARE_MODES = { "off", "old_school", "modern", "full", "balance" }
local SHARE_LABELS = {
  off = "OFF", old_school = "OLD SCHOOL", modern = "MODERN",
  full = "FULL", balance = "BALANCE",
}
local SHARE_OPTION_KEY = "expQolShareMode"
local SHARE_ROW_ID = "expQolShareMode"

local function multiplier(options)
  local value = tonumber(options and options[OPTION_KEY])
  for _, allowed in ipairs(MULTIPLIERS) do
    if value == allowed then return value end
  end
  return 1
end

local function shareMode(options)
  local value = options and options[SHARE_OPTION_KEY]
  for _, id in ipairs(SHARE_MODES) do
    if value == id then return id end
  end
  return "off"
end

local function shareModeIndex(mode)
  for index, id in ipairs(SHARE_MODES) do
    if id == mode then return index end
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

-- Eligible: alive, not an empty slot, below the level cap -- the same gate
-- Experience.awardFoe applies to any recipient before it splits exp.
local function eligiblePartyIndices(party)
  local out = {}
  for i = 1, 6 do
    local mon = party[i]
    if mon and (tonumber(mon.species or mon.speciesId) or 0) ~= 0
        and (tonumber(mon.hp) or 0) > 0
        and (tonumber(mon.level) or 1) < Experience.MAX_LEVEL then
      out[#out + 1] = i
    end
  end
  return out
end

-- Mirrors Experience.awardFoe's own on-field lookup: the mon(s) currently
-- battling, as opposed to a bench slot that only gets a share because the
-- recipient set below was widened.
local function partyIndexIsBattler(battle, index)
  if not battle or not index then return false end
  if battle.player and battle.player.partyIndex == index then return true end
  if battle.double and battle.battlers and battle.battlers[2]
      and battle.battlers[2].partyIndex == index then return true end
  return false
end

if not Experience._expQolOriginalAwardFoe then
  Experience._expQolOriginalAwardFoe = Experience.awardFoe
  Experience.awardFoe = function(st, foeBattler, opts)
    opts = opts or {}
    if not installed() or not st or not foeBattler then
      return Experience._expQolOriginalAwardFoe(st, foeBattler, opts)
    end
    local mode = shareMode(st.session and st.session.options)
    if mode == "off" then
      return Experience._expQolOriginalAwardFoe(st, foeBattler, opts)
    end
    opts.partyIndices = eligiblePartyIndices(st.playerParty or {})
    return Experience._expQolOriginalAwardFoe(st, foeBattler, opts)
  end
end

return function(mod)
  local battleGroup
  for _, group in ipairs(Rows.GROUPS) do
    if group.id == "group.battle" then battleGroup = group end
  end
  if battleGroup then
    local foundMultiplier, foundShare = false, false
    for _, id in ipairs(battleGroup.members) do
      if id == ROW_ID then foundMultiplier = true end
      if id == SHARE_ROW_ID then foundShare = true end
    end
    if not foundMultiplier then battleGroup.members[#battleGroup.members + 1] = ROW_ID end
    if not foundShare then battleGroup.members[#battleGroup.members + 1] = SHARE_ROW_ID end
  end

  if not Rows._expQolOriginalBuild then
    Rows._expQolOriginalBuild = Rows.build
    Rows.build = function(ctx)
      local out = Rows._expQolOriginalBuild(ctx)
      if not installed() then return out end
      local hasMultiplier, hasShare = false, false
      for _, row in ipairs(out) do
        if row.id == ROW_ID then hasMultiplier = true end
        if row.id == SHARE_ROW_ID then hasShare = true end
      end
      if not hasMultiplier then
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
      end
      if not hasShare then
        out[#out + 1] = {
          id = SHARE_ROW_ID,
          label = "EXP SHARE",
          value = function(c)
            return SHARE_LABELS[shareMode(optionsFor(c))]
          end,
          step = function(c, direction)
            local options = optionsFor(c)
            if not options then return false end
            local current = shareModeIndex(shareMode(options))
            local delta = direction and direction < 0 and -1 or 1
            local nextIndex = (current - 1 + delta) % #SHARE_MODES + 1
            options[SHARE_OPTION_KEY] = SHARE_MODES[nextIndex]
            return true
          end,
        }
      end
      return out
    end
  end

  -- Lower priority than the multiplier hook below, so it runs closer to
  -- vanilla: this computes the mode's base share, and the multiplier then
  -- scales whatever it returns.
  mod.hooks:wrap("exp.gain", function(next, ctx)
    local battle = ctx and ctx.battle
    local session = battle and battle.session
    local mode = shareMode(session and session.options)
    if mode == "off" then return next(ctx) end

    local party = (battle and battle.playerParty) or {}
    local eligible = {}
    for i = 1, 6 do
      local mon = party[i]
      if mon and (tonumber(mon.species or mon.speciesId) or 0) ~= 0
          and (tonumber(mon.hp) or 0) > 0
          and (tonumber(mon.level) or 1) < Experience.MAX_LEVEL then
        eligible[#eligible + 1] = { index = i, level = tonumber(mon.level) or 1 }
      end
    end
    if #eligible == 0 then return next(ctx) end

    local foeBattler = ctx.loser
    local foeMon = foeBattler and foeBattler.mon
    local foeSpecies = foeBattler and (foeBattler.species or (foeMon and (foeMon.species or foeMon.speciesId)))
    local foeLevel = tonumber(ctx.level) or (foeMon and foeMon.level) or 1
    local calculated = math.floor(Experience.expYield(foeSpecies) * math.max(1, foeLevel) / 7)
    local isParticipant = partyIndexIsBattler(battle, ctx.index)
    local amount

    if mode == "full" then
      -- Every eligible Pokemon gets the full solo-kill amount, undivided.
      amount = calculated
    elseif mode == "modern" then
      -- The active battler(s) keep the full amount; the bench gets a flat
      -- half-share each, matching the modern held-item Exp Share toggle.
      amount = isParticipant and calculated or math.floor(calculated * 50 / 100)
    elseif mode == "old_school" then
      -- Gen 1 Exp. All: battlers keep their usual undivided-by-item split,
      -- and every eligible Pokemon also gets a bonus half-pool share.
      local participantCount = 0
      for _, entry in ipairs(eligible) do
        if partyIndexIsBattler(battle, entry.index) then participantCount = participantCount + 1 end
      end
      participantCount = math.max(1, participantCount)
      local bonus = math.floor(calculated / (2 * #eligible))
      amount = (isParticipant and math.floor(calculated / participantCount) or 0) + bonus
    elseif mode == "balance" then
      -- A fixed pool split by distance from the level cap: the lowest-level
      -- member of the team gets the largest slice.
      local weightSum, myWeight = 0, 0
      for _, entry in ipairs(eligible) do
        local weight = Experience.MAX_LEVEL - entry.level
        weightSum = weightSum + weight
        if entry.index == ctx.index then myWeight = weight end
      end
      weightSum = math.max(1, weightSum)
      amount = math.floor(calculated * myWeight / weightSum)
    else
      amount = calculated
    end

    if ctx.luckyEgg then amount = math.floor(amount * 150 / 100) end
    if ctx.isTrainer then amount = math.floor(amount * 150 / 100) end
    if ctx.traded then amount = math.floor(amount * 150 / 100) end
    return math.max(1, amount)
  end, -10)

  mod.hooks:wrap("exp.gain", function(next, ctx)
    local amount = next(ctx)
    local battle = ctx and ctx.battle
    local session = battle and battle.session
    local rate = multiplier(session and session.options)
    if type(amount) ~= "number" or rate == 1 then return amount end
    return math.floor(amount * rate)
  end)
end