local mod = game.mod_runtime[game.current_mod]

--- Hash-based noise for stable per-tile randomness.
---@param x number
---@param y number
---@param seed number
---@return number
mod.hash_noise = function(x, y, seed)
  local n = x * 374761393 + y * 668265263 + seed * 2654435761
  n = (n ~ (n >> 13)) * 1274126177
  return ((n ~ (n >> 16)) % 1024) / 1024
end

--- Linear interpolate between a and b.
---@param a number
---@param b number
---@param t number
---@return number
mod.lerp = function(a, b, t)
  return a + (b - a) * t
end

--- Smoothstep curve for value noise blending.
---@param t number
---@return number
mod.smoothstep = function(t)
  return t * t * (3 - 2 * t)
end

--- Value noise at fractional coordinates.
---@param x number
---@param y number
---@param seed number
---@return number
mod.value_noise = function(x, y, seed)
  local x0 = math.floor(x)
  local y0 = math.floor(y)
  local x1 = x0 + 1
  local y1 = y0 + 1
  local sx = mod.smoothstep(x - x0)
  local sy = mod.smoothstep(y - y0)
  local n00 = mod.hash_noise(x0, y0, seed)
  local n10 = mod.hash_noise(x1, y0, seed)
  local n01 = mod.hash_noise(x0, y1, seed)
  local n11 = mod.hash_noise(x1, y1, seed)
  local ix0 = mod.lerp(n00, n10, sx)
  local ix1 = mod.lerp(n01, n11, sx)
  return mod.lerp(ix0, ix1, sy)
end

--- Simple multi-octave value noise (Perlin-ish).
---@param x number
---@param y number
---@param seed number
---@return number
mod.perlinish = function(x, y, seed)
  local total = 0
  local freq = 1 / 8
  local amp = 1
  local max_amp = 0
  for _ = 1, 3 do
    total = total + mod.value_noise(x * freq, y * freq, seed) * amp
    max_amp = max_amp + amp
    amp = amp * 0.5
    freq = freq * 2
  end
  return total / max_amp
end

--- Filter for window terrains we want to smash.
---@param ter_str string
---@return boolean
mod.is_glass_window = function(ter_str)
  if string.sub(ter_str, 1, 8) ~= "t_window" then
    return false
  end
  if string.find(ter_str, "frame", 1, true) then
    return false
  end
  if string.find(ter_str, "empty", 1, true) then
    return false
  end
  return true
end

--- Apply the perlin-driven overlay to road-like tiles.
---@param map Map
---@param p Tripoint
---@param heat number
---@param dirt_id TerIntId
---@param grass_id TerIntId
---@param dead_grass_id TerIntId
---@param tall_grass_id TerIntId
---@param young_tree_id TerIntId
mod.apply_road_overlay = function(map, p, heat, dirt_id, grass_id, dead_grass_id, tall_grass_id, young_tree_id)
  if heat < 0.15 then
    if gapi.rng(1, 100) <= 80 then
      map:set_ter_at(p, dirt_id)
    end
  elseif heat < 0.25 then
    if gapi.rng(1, 100) <= 80 then
      local target = gapi.rng(1, 5) == 1 and dead_grass_id or grass_id
      map:set_ter_at(p, target)
    end
  elseif heat < 0.35 then
    if gapi.rng(1, 100) <= 80 then
      map:set_ter_at(p, tall_grass_id)
    else
      map:set_ter_at(p, young_tree_id)
    end
  elseif heat < 0.45 then
    if gapi.rng(1, 100) <= 5 then
      map:set_ter_at(p, young_tree_id)
    end
  elseif heat < 0.55 then
    if gapi.rng(1, 199) <= 5 then
      map:set_ter_at(p, tall_grass_id)
    end
  elseif heat < 0.65 then
    if gapi.rng(1, 100) <= 5 then
      local target = gapi.rng(1, 3) == 1 and dead_grass_id or grass_id
      map:set_ter_at(p, target)
    end
  elseif heat < 0.75 then
    if gapi.rng(1, 100) <= 5 then
      map:set_ter_at(p, dirt_id)
    end
  end
end

--- Mapgen hook: replace selected terrains for a rough/overgrown feel + roof punch-outs.
---@param params OnMapgenPostprocessParams
mod.on_mapgen_postprocess = function(params)
  local map = params.map

  -- windows / glass / doors
  local frame_id = TerId.new("t_window_frame"):int_id()
  local frame_domestic_id = TerId.new("t_window_frame_domestic"):int_id()
  local empty_id = TerId.new("t_window_empty"):int_id()
  local empty_domestic_id = TerId.new("t_window_empty_domestic"):int_id()
  local curtains_id = TerId.new("t_curtains"):int_id()
  local glass_wall_id = TerId.new("t_wall_glass"):int_id()
  local glass_wall_alarm_id = TerId.new("t_wall_glass_alarm"):int_id()
  local laminated_glass_id = TerId.new("t_laminated_glass"):int_id()
  local door_glass_c_id = TerId.new("t_door_glass_c"):int_id()
  local door_o_id = TerId.new("t_door_o"):int_id()
  local door_locked_id = TerId.new("t_door_locked"):int_id()
  local door_c_id = TerId.new("t_door_c"):int_id()
  local door_b_id = TerId.new("t_door_b"):int_id()
  local door_frame_id = TerId.new("t_door_frame"):int_id()

  -- fences
  local chainfence_id = TerId.new("t_chainfence"):int_id()
  local chainfence_posts_id = TerId.new("t_chainfence_posts"):int_id()
  local fence_id = TerId.new("t_fence"):int_id()
  local fence_post_id = TerId.new("t_fence_post"):int_id()

  -- floors / roads
  local floor_id = TerId.new("t_floor"):int_id()
  local floor_waxed_id = TerId.new("t_floor_waxed"):int_id()
  local pavement_id = TerId.new("t_pavement"):int_id()
  local pavement_y_id = TerId.new("t_pavement_y"):int_id()
  local sidewalk_id = TerId.new("t_sidewalk"):int_id()
  local thconc_floor_id = TerId.new("t_thconc_floor"):int_id()

  -- nature
  local dirt_id = TerId.new("t_dirt"):int_id()
  local grass_id = TerId.new("t_grass"):int_id()
  local dead_grass_id = TerId.new("t_grass_dead"):int_id()
  local tall_grass_id = TerId.new("t_grass_tall"):int_id()
  local young_tree_id = TerId.new("t_tree_young"):int_id()

  -- roofs -> air
  local air_id = TerId.new("t_open_air"):int_id()
  local roof_shingle_id = TerId.new("t_shingle_flat_roof"):int_id()
  local roof_gutter_id = TerId.new("t_gutter"):int_id()
  local roof_gutter_drop_id = TerId.new("t_gutter_drop"):int_id()
  local roof_tar_id = TerId.new("t_tar_flat_roof"):int_id()
  local roof_flat_id = TerId.new("t_flat_roof"):int_id()
  local roof_metal_id = TerId.new("t_metal_flat_roof"):int_id()
  local roof_tile_id = TerId.new("t_tile_flat_roof"):int_id()

  local size = map:get_map_size()
  local seed = params.omt.x * 31 + params.omt.y * 17 + params.omt.z * 13

  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local p = Tripoint.new(x, y, 0)

      local ter = map:get_ter_at(p)

      if ter == glass_wall_id or ter == laminated_glass_id or ter == glass_wall_alarm_id or ter == door_glass_c_id then
        if gapi.rng(1, 100) <= 60 then
          map:set_ter_at(p, floor_id)
        end
      end

      if ter == door_c_id or ter == door_locked_id then
        local roll = gapi.rng(1, 3)
        local target = roll == 1 and door_o_id or roll == 2 and door_frame_id or door_b_id
        map:set_ter_at(p, target)
      end

      if ter == chainfence_id then
        if gapi.rng(1, 100) <= 50 then
          local roll = gapi.rng(1, 4)
          if roll == 1 then
            map:set_ter_at(p, chainfence_posts_id)
          elseif roll == 2 then
            map:set_ter_at(p, dirt_id)
          elseif roll == 3 then
            map:set_ter_at(p, grass_id)
          else
            map:set_ter_at(p, dead_grass_id)
          end
        end
      end

      if ter == fence_id then
        if gapi.rng(1, 100) <= 25 then
          map:set_ter_at(p, fence_post_id)
        end
      end

      local ter_str = ter:str_id():str()

      if ter == curtains_id then
        if gapi.rng(1, 100) <= 75 then
          map:set_ter_at(p, frame_domestic_id)
        end
      end

      if mod.is_glass_window(ter_str) then
        local is_domestic = string.find(ter_str, "domestic", 1, true)
        local use_empty = gapi.rng(1, 100) <= 50
        local target = is_domestic and (use_empty and empty_domestic_id or frame_domestic_id) or
          (use_empty and empty_id or frame_id)
        map:set_ter_at(p, target)
      end

      if ter == pavement_id or ter == pavement_y_id or ter == sidewalk_id or ter == thconc_floor_id then
        if gapi.rng(1, 100) <= 80 then
          local heat = mod.perlinish(x, y, seed)
          mod.apply_road_overlay(map, p, heat, dirt_id, grass_id, dead_grass_id, tall_grass_id, young_tree_id)
        end
      end

      if ter == grass_id then
        if gapi.rng(1, 100) <= 15 then
          local roll = gapi.rng(1, 3)
          if roll == 1 then
            map:set_ter_at(p, tall_grass_id)
          else
            map:set_ter_at(p, dead_grass_id)
          end
        end
      end

      if ter == floor_id or ter == floor_waxed_id then
        if gapi.rng(1, 100) <= 60 then
          local heat = mod.perlinish(x, y, seed)
          mod.apply_road_overlay(map, p, heat, dirt_id, grass_id, dead_grass_id, tall_grass_id, young_tree_id)
        end
      end
    end
  end
end
