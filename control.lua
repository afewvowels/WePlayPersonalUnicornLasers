-- WePlay: Personal Unicorn Lasers, runtime.
--
-- Every shot from a personal laser defense fires the "wp-pul|..." script
-- trigger (see data-final-fixes.lua). We keep one drawn beam per shooter and
-- target for as long as the real (invisible) beam lives, and redraw it every
-- tick as a chain of glowing pieces, each tinted by its own rainbow color.
--
-- Colors: hue = (distance along the beam + the shooter's world position
--               - flow speed * time) / rainbow length
-- so the colors stream toward the target, every beam in the world runs on the
-- same clock (in sync), and walking around slowly shifts the palette.

local beamlib = require("__WePlayBeamLib__/beamlib")
local ribbon = beamlib.ribbon

local EFFECT_PREFIX = "wp-pul|"
-- Rainbow scale setting 1..5: tiles per full rainbow, and the base flow speed
-- (tiles per second) that looks right at that size. Scale 5 is the tight
-- rainbow-every-tile look of the first demo.
local SCALES = {
  {length = 24, flow = 6},
  {length = 12, flow = 5},
  {length = 6, flow = 4},
  {length = 3, flow = 3.5},
  {length = 1.5, flow = 3},
}
local PIECES_PER_RAINBOW = 6  -- small rainbows need short pieces to show every color
local MAX_PIECE_LENGTH = 0.5  -- tiles
local MAX_PIECES = 96         -- long beams get longer pieces instead of more
local DEFAULT_DURATION = 30   -- ticks, for beams that report no duration
local INV_SQRT2 = 0.70710678

local cfg = {}

local function read_settings()
  local g = settings.global
  local scale = SCALES[g["wp-pul-scale"].value] or SCALES[1]
  cfg.rainbow_length = scale.length
  cfg.flow_speed = scale.flow * g["wp-pul-speed"].value / 60   -- tiles per tick
  cfg.piece_length = math.min(MAX_PIECE_LENGTH, scale.length / PIECES_PER_RAINBOW)
  cfg.saturation = g["wp-pul-saturation"].value
end

local function layers()
  return {
    {width = 0.5, sprite = "wp-beamlib-soft", intensity = 0.6},
    {width = 0.16, sprite = "wp-beamlib-core", intensity = 1},
    -- white-hot center line, keeps its own color under the rainbow
    {width = 0.05, sprite = "wp-beamlib-core", intensity = 0.7, own_color = true, color = {r = 1, g = 1, b = 1}},
  }
end

-- HSV to RGB with v = 1, writing into an existing table to avoid garbage.
local function hue_rgb(h, s, out)
  h = (h % 1) * 6
  local i = math.floor(h)
  local f = h - i
  local p, q, t = 1 - s, 1 - s * f, 1 - s * (1 - f)
  if i == 0 then out.r, out.g, out.b = 1, t, p
  elseif i == 1 then out.r, out.g, out.b = q, 1, p
  elseif i == 2 then out.r, out.g, out.b = p, 1, t
  elseif i == 3 then out.r, out.g, out.b = p, q, 1
  elseif i == 4 then out.r, out.g, out.b = t, p, 1
  else out.r, out.g, out.b = 1, p, q end
  return out
end

-- Scratch segments, reused every tick (ribbons only read them).
local scratch = {}
local function scratch_seg(k)
  local seg = scratch[k]
  if not seg then
    seg = {a = {x = 0, y = 0}, b = {x = 0, y = 0}, c = {r = 1, g = 1, b = 1}}
    scratch[k] = seg
  end
  return seg
end

local tip_color = {r = 1, g = 1, b = 1}

local function destroy(key)
  local b = storage.beams[key]
  if not b then return end
  ribbon.destroy(b.ribbon)
  if b.tip and b.tip.valid then b.tip.destroy() end
  storage.beams[key] = nil
end

local function draw(b, tick)
  local shooter = b.shooter
  local sp = shooter.position
  local ax, ay = sp.x + b.ox, sp.y + b.oy
  local bx, by
  if b.target then
    local tp = b.target.position
    bx, by = tp.x, tp.y
  else
    bx, by = b.tpos.x, b.tpos.y
  end

  local dx, dy = bx - ax, by - ay
  local len = math.sqrt(dx * dx + dy * dy)
  local n = math.max(1, math.min(MAX_PIECES, math.ceil(len / cfg.piece_length)))
  local L = cfg.rainbow_length
  local base = (ax + ay) * INV_SQRT2 - cfg.flow_speed * tick
  local sat = cfg.saturation

  for k = 1, n do
    local seg = scratch_seg(k)
    local t0, t1 = (k - 1) / n, k / n
    seg.a.x, seg.a.y = ax + dx * t0, ay + dy * t0
    seg.b.x, seg.b.y = ax + dx * t1, ay + dy * t1
    local s = len * (t0 + t1) / 2
    hue_rgb((base + s) / L, sat, seg.c)
  end
  ribbon.set_segments(b.ribbon, scratch, n)

  local tip = b.tip
  if tip and tip.valid then
    tip.target = {x = bx, y = by}
    tip.color = hue_rgb((base + len) / L, sat, tip_color)
  end
end

local on_tick

local function sync()
  if storage.beams and next(storage.beams) then
    script.on_event(defines.events.on_tick, on_tick)
  else
    script.on_event(defines.events.on_tick, nil)
  end
end

on_tick = function(event)
  local tick = event.tick
  for key, b in pairs(storage.beams) do
    if tick > b.expires
      or not (b.shooter and b.shooter.valid)
      or (b.target and not b.target.valid) then
      destroy(key)
    else
      draw(b, tick)
    end
  end
  if not next(storage.beams) then sync() end
end

local function parse(effect_id)
  local fields = {}
  for field in string.gmatch(effect_id, "[^|]+") do fields[#fields + 1] = field end
  return tonumber(fields[2]) or 0, tonumber(fields[3]) or 0, tonumber(fields[4]) or -1.2
end

script.on_event(defines.events.on_script_trigger_effect, function(event)
  local id = event.effect_id
  if string.sub(id, 1, #EFFECT_PREFIX) ~= EFFECT_PREFIX then return end

  local shooter = event.source_entity or event.cause_entity
  if not (shooter and shooter.valid and shooter.unit_number) then return end
  local target = event.target_entity
  if target and not (target.valid and target.unit_number) then target = nil end
  local tpos = event.target_position
  if not target and not tpos then return end

  local duration, ox, oy = parse(id)
  if duration <= 0 then duration = DEFAULT_DURATION end

  local key
  if target then
    key = shooter.unit_number .. ":" .. target.unit_number
  else
    key = shooter.unit_number .. "@" .. math.floor(tpos.x) .. "," .. math.floor(tpos.y)
  end

  local expires = event.tick + duration + 1
  local b = storage.beams[key]
  if b then
    if expires > b.expires then b.expires = expires end
    if not target then b.tpos = tpos end
    return
  end

  local surface = shooter.surface
  storage.beams[key] = {
    shooter = shooter,
    target = target,
    tpos = tpos and {x = tpos.x, y = tpos.y},
    ox = ox, oy = oy,
    expires = expires,
    ribbon = ribbon.new{surface = surface, layers = layers()},
    tip = rendering.draw_sprite{
      sprite = "wp-beamlib-dot",
      surface = surface,
      target = target and target.position or tpos,
      x_scale = 0.9, y_scale = 0.9,
      render_layer = "air-object",
    },
  }
  sync()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if string.sub(event.setting or "", 1, 7) == "wp-pul-" then read_settings() end
end)

script.on_init(function()
  storage.beams = {}
  read_settings()
end)

script.on_configuration_changed(function()
  storage.beams = storage.beams or {}
  read_settings()
  sync()
end)

script.on_load(function()
  read_settings()
  sync()
end)
