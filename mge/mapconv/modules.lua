-- The map converter's modules in load order, paths from MGE.scriptPath. One list for the game
-- (MGE.loadMapConv in main.lua), the tests (tests/run.lua) and tools/mapconv_baseline.lua. They need
-- utils/mat3, utils/file_handler and utils/mod_export loaded first
return { "mapconv/vmf.lua", "mapconv/bsp.lua", "mapconv/brush.lua", "mapconv/boxfit.lua", "mapconv/merge.lua",
    "mapconv/convert.lua", "mapconv/skyclips.lua" }
