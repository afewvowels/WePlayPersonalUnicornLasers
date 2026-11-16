-- WePlay: Personal Unicorn Lasers, data stage.
--
-- For every personal laser defense (active-defense-equipment that fires a
-- laser beam, vanilla or modded):
--   * its beam is swapped for an invisible copy, so damage and targeting stay
--     exactly as they were but the game draws nothing;
--   * a script trigger is added at the target, so control.lua hears about
--     every shot and draws the rainbow with WePlay: Beam Library.
-- Laser turrets keep the vanilla beam: they don't share the copy.
--
-- The trigger's effect_id carries what control.lua needs to draw the beam:
--   "wp-pul|<duration ticks>|<source offset x>|<source offset y>"

local beamdata = require("__WePlayBeamLib__/datalib")

local PREFIX = "wp-pul-"

local function list(x)
  if x == nil then return {} end
  if x.type then return {x} end
  return x
end

local function offset_xy(o)
  if not o then return nil end
  return o.x or o[1] or 0, o.y or o[2] or 0
end

local function has_laser_category(params)
  if params.ammo_category == "laser" then return true end
  for _, category in pairs(params.ammo_categories or {}) do
    if category == "laser" then return true end
  end
  return false
end

local function is_laser(params, delivery)
  if has_laser_category(params) then return true end
  -- modded equipment without the laser ammo category: go by the beam's name
  return string.find(delivery.beam, "laser", 1, true) ~= nil
end

local copies = {}

local function invisible_copy(beam_name)
  local name = PREFIX .. beam_name
  if copies[name] then return name end
  local source = data.raw["beam"][beam_name]
  if not source then return nil end
  local copy = table.deepcopy(source)
  copy.name = name
  copy.hidden = true
  copy.graphics_set = beamdata.invisible_beam_graphics()
  data:extend{copy}
  copies[name] = true
  return name
end

local function fmt(n)
  return string.format("%.3f", n or 0)
end

for _, equipment in pairs(data.raw["active-defense-equipment"] or {}) do
  local params = equipment.attack_parameters
  local ammo = params and params.ammo_type
  if ammo and ammo.action then
    for _, trigger in pairs(list(ammo.action)) do
      for _, delivery in pairs(list(trigger.action_delivery)) do
        if delivery.type == "beam" and delivery.beam and is_laser(params, delivery) then
          local copy_name = invisible_copy(delivery.beam)
          if copy_name then
            delivery.beam = copy_name
            local ox, oy = offset_xy(delivery.source_offset)
            if not ox then ox, oy = offset_xy(params.source_offset) end
            if not ox then ox, oy = 0, -1.2 end
            local effects = list(delivery.target_effects)
            effects[#effects + 1] = {
              type = "script",
              effect_id = table.concat({"wp-pul", delivery.duration or 0, fmt(ox), fmt(oy)}, "|"),
            }
            delivery.target_effects = effects
          end
        end
      end
    end
  end
end
