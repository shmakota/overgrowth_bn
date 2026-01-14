local mod = game.mod_runtime[game.current_mod]

table.insert(game.hooks.on_mapgen_postprocess, function(...) return mod.on_mapgen_postprocess(...) end)
